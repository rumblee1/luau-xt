"""Build an optional BIOS-bootable hard disk for the 386 VGA profile."""
import argparse
import base64
from hashlib import sha256
from io import BytesIO
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile
from zipfile import ZipFile

from install_freedos import HEADS, SECTORS, SECTOR_SIZE, make_hard_disk
from prepare_media import ROOT, assemble, disk_modules, fetch, module, option_rom, unpack_dos_system, write_vga_programs
from vga_clip import write_video
from vga_library import write_library

BLASTER = b"SET BLASTER=A220 I5 D1 T3\r\n"
DOOM_AUDIO = (
    b"sfx_volume 8\r\nsnd_channels 8\r\nsnd_musicdevice 0\r\nsnd_sfxdevice 3\r\n"
    b"snd_sbport 544\r\nsnd_sbirq 5\r\nsnd_sbdma 1\r\n"
)

DOOM_LAUNCHERS = {"FAST": 5, "TINY": 3}
DOOM_LIGHT_AUDIO = DOOM_AUDIO.replace(b"snd_channels 8", b"snd_channels 2")

DOOM_19_SHAREWARE = "cacf0142b31ca1af00796b4a0339e07992ac5f21bc3f81e7532fe1b5e1b486e6"

FASTDOOM_130 = "4b805f3f712362d53797b3109ebf4651adb3bf28b903c91c4c477eba56121d6f"


def unpack_doom(source, target):
    if sha256(source.read_bytes()).hexdigest() != DOOM_19_SHAREWARE:
        raise ValueError("Expected the original Doom 1.9 shareware archive (doom19s.zip)")
    with ZipFile(source) as archive:
        installer = archive.read("DOOMS_19.1") + archive.read("DOOMS_19.2")
    with ZipFile(BytesIO(installer)) as payload:
        payload.extractall(target)
    configuration = target / "DEFAULT.CFG"
    if not configuration.exists():
        configuration.write_bytes(DOOM_AUDIO)


def write_doom_launchers(tree, existing_configs=()):
    for preset, blocks in DOOM_LAUNCHERS.items():
        config = f"{preset}.CFG"
        if config not in existing_configs:
            display = f"screenblocks {blocks}\r\ndetaillevel 1\r\n".encode("ascii")
            (tree / "DOOM" / config).write_bytes(DOOM_LIGHT_AUDIO + display)
        batch = (
            "@ECHO OFF\r\nC:\r\nCD \\DOOM\r\n"
            f"DOOM -CONFIG {config} -NOMUSIC -NOMOUSE -WARP 1 1 %1 %2 %3 %4 %5 %6 %7 %8 %9\r\n"
        )
        (tree / f"DOOM{preset}.BAT").write_bytes(batch.encode("ascii"))


def install_fastdoom(source, tree):
    if sha256(source.read_bytes()).hexdigest() != FASTDOOM_130:
        raise ValueError("Expected the official FastDoom_1.3.0.zip release archive")
    doom = tree / "DOOM"
    with ZipFile(source) as archive:
        for source_name, guest_name in (
            ("FDOOM.EXE", "FDOOM.EXE"),
            ("DOOM1.TCF", "DOOM1.TCF"),
            ("README.txt", "FDOOM.TXT"),
        ):
            (doom / guest_name).write_bytes(archive.read(source_name))
    license_text = (ROOT / "guest" / "fastdoom-license.txt").read_text(encoding="ascii")
    source_notice = "FastDoom 1.3.0 source: https://github.com/viti95/FastDoom/tree/1.3.0\n\n"
    (doom / "FDGPL.TXT").write_bytes((source_notice + license_text).replace("\n", "\r\n").encode("ascii"))
    (tree / "FASTDOOM.BAT").write_bytes(
        b"@ECHO OFF\r\nC:\r\nCD \\DOOM\r\n"
        b"FDOOM -386DX -POTATO -NOMELT -NOVSYNC -FLATSPAN -FLATSKY -WARP 1 1 -SIZE 3 -NOSOUND -NOMOUSE -CONFIG FDOOM.CFG\r\n"
    )


def unpack_windows_setup(archive, target, work):
    disks = work / "windows-floppies"
    disks.mkdir()
    subprocess.run(["7z", "x", "-y", f"-o{disks}", str(archive.resolve()), "DISK0?.IMG", "-r"],
                   check=True, stdout=subprocess.DEVNULL)
    target.mkdir()
    for number in range(1, 6):
        matches = list(disks.rglob(f"DISK{number:02}.IMG"))
        if len(matches) != 1 or matches[0].stat().st_size != 1228800:
            raise ValueError("Expected the five 1.2 MB Windows 3.0 setup floppy images")
        subprocess.run(["mcopy", "-n", "-i", matches[0], "::*", target], check=True)
    if not any(path.name.upper() == "SETUP.EXE" for path in target.iterdir()):
        raise ValueError("The Windows setup disks did not contain SETUP.EXE")


def read_disk_modules(folder):
    """Decode the existing generated VGA disk before updating its FAT volume."""
    index = (folder / "Index.luau").read_text(encoding="ascii")
    size = re.search(r"\bsize = (\d+)", index)
    if size is None:
        raise ValueError(f"Invalid disk index in {folder}")
    size_bytes = int(size[1])
    cylinder_bytes = HEADS * SECTORS * SECTOR_SIZE
    if size_bytes % cylinder_bytes or not 1 <= size_bytes // cylinder_bytes <= 127:
        raise ValueError(f"Invalid disk size in {folder}")
    image = bytearray(size_bytes)
    for block, name in re.findall(r'\{ (\d+), "(Part\d+)" \}', index):
        part = (folder / f"{name}.luau").read_text(encoding="ascii")
        for offset, encoded in re.findall(r'\{ (\d+), "([A-Za-z0-9+/=]+)" \}', part):
            start = int(block) + int(offset)
            data = base64.b64decode(encoded, validate=True)
            if start + len(data) > len(image):
                raise ValueError(f"{name} extends beyond the disk")
            image[start:start + len(data)] = data
    if image[510:512] != b"\x55\xaa":
        raise ValueError(f"No boot record in {folder}")
    return image


def write_videos(tree, clip, bad_apple):
    if clip:
        shutil.copyfile(clip, tree / "VIDEO.VCL")
    if bad_apple:
        with (tree / "BADAPPLE.VCL").open("wb") as video:
            write_video(video, bad_apple, with_audio=True)
        (tree / "BADAPPLE.BAT").write_bytes(
            b"@ECHO OFF\r\nC:\\VGACLIP.COM C:\\BADAPPLE.VCL\r\n"
        )


def update_library(folder, work, clip, bad_apple, fastdoom=None):
    """Refresh the library and optional video while keeping existing DOS files."""
    disk = work / "vga.img"
    image = read_disk_modules(folder)
    partition = image[446:510]
    for entry in range(0, len(partition), 16):
        if partition[entry] == 0x80 and partition[entry + 4] in (0x01, 0x04, 0x06, 0x0B, 0x0C, 0x0E):
            start, count = struct.unpack_from("<II", partition, entry + 8)
            if start and count and (start + count) * SECTOR_SIZE <= len(image):
                break
    else:
        raise ValueError("The VGA disk must contain an active FAT partition")
    disk.write_bytes(image)
    tree = work / "library"
    tree.mkdir()
    volume = f"{disk}@@{start * SECTOR_SIZE}"
    write_library(tree, work)
    assemble("vgaclip.s", tree / "VGACLIP.COM", work)
    write_videos(tree, clip, bad_apple)
    check_startup = subprocess.run(["mdir", "-i", volume, "::/AUTOEXEC.BAT"], capture_output=True)
    startup = b""
    if check_startup.returncode == 0:
        startup = subprocess.check_output(["mtype", "-i", volume, "::/AUTOEXEC.BAT"])
    if not re.search(rb"^\s*@?\s*SET\s+BLASTER\s*=", startup, flags=re.I | re.M):
        separator = b"\r\n" if startup and not startup.endswith(b"\n") else b""
        (tree / "AUTOEXEC.BAT").write_bytes(startup + separator + BLASTER)
    doom = subprocess.run(["mdir", "-i", volume, "::/DOOM/DOOM.EXE"], capture_output=True)
    if doom.returncode == 0:
        (tree / "DOOM").mkdir()
        existing_configs = [
            f"{preset}.CFG" for preset in DOOM_LAUNCHERS
            if subprocess.run(["mdir", "-i", volume, f"::/DOOM/{preset}.CFG"], capture_output=True).returncode == 0
        ]
        write_doom_launchers(tree, existing_configs)
    if fastdoom:
        subprocess.run(["mdir", "-i", volume, "::/DOOM/DOOM1.WAD"], check=True, stdout=subprocess.DEVNULL)
        (tree / "DOOM").mkdir(exist_ok=True)
        install_fastdoom(fastdoom, tree)
    for item in sorted(tree.iterdir()):
        if item.is_dir():
            target = f"::/{item.name}"
            exists = subprocess.run(["mdir", "-i", volume, target], capture_output=True)
            if exists.returncode:
                subprocess.run(["mmd", "-i", volume, target], check=True)
            for guest_file in sorted(item.iterdir()):
                subprocess.run(["mcopy", "-o", "-i", volume, guest_file, f"{target}/{guest_file.name}"], check=True)
        else:
            subprocess.run(["mcopy", "-o", "-i", volume, item, f"::/{item.name}"], check=True)
    if doom.returncode == 0:
        settings = subprocess.run(["mdir", "-i", volume, "::/DOOM/DEFAULT.CFG"], capture_output=True)
        if settings.returncode:
            configuration = work / "DEFAULT.CFG"
            configuration.write_bytes(DOOM_AUDIO)
            subprocess.run(["mcopy", "-i", volume, configuration, "::/DOOM/DEFAULT.CFG"], check=True)
    return disk.read_bytes()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=ROOT / ".boot_media")
    parser.add_argument("--output", type=Path, default=ROOT / "src/media")
    parser.add_argument("--doom-shareware", type=Path, help="Original doom19s.zip to install in C:\\DOOM")
    parser.add_argument("--fastdoom", type=Path, help="Official FastDoom_1.3.0.zip release archive")
    parser.add_argument("--windows-setup", type=Path, help="Local Windows 3.0 five-floppy 7z setup archive")
    parser.add_argument("--windows-profile", action="store_true", help="Use the separate 386 Windows 3.0 profile")
    parser.add_argument("--guest-dir", type=Path, help="Directory of files to copy to C:")
    parser.add_argument("--clip", type=Path, help="VGA clip to install as C:\\VIDEO.VCL")
    parser.add_argument("--bad-apple", type=Path, help="Local video to convert for the BADAPPLE command")
    parser.add_argument("--disk-image", type=Path, help="Bootable raw image with 16 heads and 32 sectors per track")
    parser.add_argument("--update", action="store_true", help="Refresh the library on the existing 386 VGA disk")
    args = parser.parse_args()
    if args.update and (args.disk_image or args.doom_shareware or args.windows_setup or args.windows_profile or args.guest_dir):
        parser.error("--update uses the existing FreeDOS VGA disk and accepts --clip, --bad-apple, or --fastdoom")
    if args.update and not (args.output / "vga_hard_disk" / "Index.luau").is_file():
        parser.error("--update requires an existing VGA hard disk in --output")
    if args.disk_image and (args.guest_dir or args.clip or args.bad_apple or args.doom_shareware or args.windows_setup):
        parser.error("--disk-image takes a complete disk. Build a new FreeDOS disk to add files.")
    if args.guest_dir and not args.guest_dir.is_dir():
        parser.error("--guest-dir must be a directory")
    if args.bad_apple:
        if not args.bad_apple.is_file():
            parser.error("--bad-apple must point to a local video file")
        if args.windows_setup or args.windows_profile:
            parser.error("--bad-apple installs the clip on the FreeDOS VGA disk")
    if args.fastdoom:
        if not args.fastdoom.is_file():
            parser.error("--fastdoom must point to a local FastDoom_1.3.0.zip archive")
        if args.disk_image or args.windows_setup or args.windows_profile or not (args.update or args.doom_shareware):
            parser.error("--fastdoom requires --update on a VGA disk with Doom shareware or --doom-shareware")
    tools = ("as", "objcopy")
    if args.bad_apple:
        tools += ("ffmpeg", "ffprobe")
    if args.update:
        tools += ("mcopy", "mdir", "mmd", "mtype")
    elif not args.disk_image:
        tools += ("mcopy", "mkfs.fat")
    if args.windows_setup:
        tools += ("7z",)
    for tool in tools:
        if shutil.which(tool) is None:
            parser.error(f"Install {tool} first")
    with tempfile.TemporaryDirectory(prefix="luau-vga-disk-") as temporary:
        work = Path(temporary)
        if args.update:
            image = update_library(args.output / "vga_hard_disk", work, args.clip, args.bad_apple, args.fastdoom)
        elif args.disk_image:
            cylinder_bytes = HEADS * SECTORS * SECTOR_SIZE
            size = args.disk_image.stat().st_size
            if size % cylinder_bytes or not 1 <= size // cylinder_bytes <= 127:
                parser.error("--disk-image must have 1–127 whole cylinders (256 KiB each)")
            image = args.disk_image.read_bytes()
            if image[510:512] != bytes.fromhex("55aa"):
                parser.error("--disk-image must contain a BIOS boot sector")
        else:
            args.cache.mkdir(parents=True, exist_ok=True)
            release = fetch(args.cache, "FD14-FloppyEdition.zip")
            tree = work / "system"
            tree.mkdir()
            unpack_dos_system(release, work / "boot-floppy.img", tree)
            write_vga_programs(tree, work)
            if not (args.windows_setup or args.windows_profile):
                write_library(tree, work)
            if args.doom_shareware:
                unpack_doom(args.doom_shareware, tree / "DOOM")
                write_doom_launchers(tree)
                if args.fastdoom:
                    install_fastdoom(args.fastdoom, tree)
            if args.windows_setup:
                unpack_windows_setup(args.windows_setup, tree / "SETUP", work)
            startup = b"@ECHO OFF\r\nPATH C:\\;A:\\\r\nPROMPT $P$G\r\n"
            if not (args.windows_setup or args.windows_profile):
                startup += BLASTER
            (tree / "AUTOEXEC.BAT").write_bytes(startup)
            write_videos(tree, args.clip, args.bad_apple)
            if args.guest_dir:
                system = {file.name.upper() for file in tree.iterdir()}
                for item in args.guest_dir.iterdir():
                    if item.name.upper() in system:
                        parser.error(f"{item.name} would replace a boot file")
                    if item.is_dir():
                        shutil.copytree(item, tree / item.name)
                    else:
                        shutil.copyfile(item, tree / item.name)
            image = make_hard_disk(tree, work)
        args.output.mkdir(parents=True, exist_ok=True)
        if not args.update:
            module(args.output / "DiskRom.luau", option_rom("hard-disk-rom.s", work))
        profile = "vga_windows_disk" if args.windows_setup or args.windows_profile else "vga_hard_disk"
        folder = args.output / profile
        disk_modules(folder, image)
        print(f"Prepared {len(image) // 1024} KiB of bootable storage for 386 VGA")


if __name__ == "__main__":
    main()
