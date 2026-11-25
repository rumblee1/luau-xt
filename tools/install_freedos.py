"""Prepare a 20 MiB FreeDOS 1.4 classic-PC installation from the 720 KiB set."""
import argparse
import gzip
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
from zipfile import ZipFile

from prepare_media import ROOT, assemble, disk_modules, fetch, module


SECTOR_SIZE = 512
HEADS, SECTORS, CYLINDERS = 16, 32, 80
DISK_SECTORS = HEADS * SECTORS * CYLINDERS
PARTITION_START = SECTORS


def copy_from_image(image, source, destination):
    subprocess.run(["mcopy", "-o", "-i", image, source, destination], check=True)


def dos_path(name):
    parts = name.decode("cp437").replace("\\", "/").split("/")
    if any(part in (".", "..") or ":" in part for part in parts):
        raise ValueError(f"Invalid DOS archive path {name!r}")
    return [part.upper() for part in parts if part]


def archive_files(archive_parts):
    """Decode the File Slicer v1 records used by the pinned floppy release."""
    directories = {-1: []}
    files = {}
    category = ()
    for part in archive_parts:
        data = part.read_bytes()
        offset = data.index(b"\x1a") + 1 if part.suffix.lower() == ".saf" else 0
        while offset < len(data):
            kind, length = struct.unpack_from("<HI", data, offset)
            if length < 6 or offset + length > len(data):
                raise ValueError(f"Invalid Slicer block in {part.name} at {offset}")
            record = data[offset : offset + length]
            offset += length
            if kind == 3:
                category = tuple(record[6:-1].decode("ascii").upper().split(","))
            elif kind == 4:
                index = struct.unpack_from("<i", record, 6)[0]
                directories[index] = dos_path(record[16:-1])
            elif kind == 5:
                index, _, _, start, compression, _, size, _, directory = struct.unpack_from(
                    "<IHIIHHIIi", record, 6
                )
                end_name = record.index(0, 36)
                if start == 0:
                    path = directories[directory] + dos_path(record[36:end_name])
                    files[index] = (path, category, compression, size, bytearray())
                _, _, _, expected, payload = files[index]
                if start != len(payload) or start + length - end_name - 1 > expected:
                    raise ValueError(f"Invalid file fragment in {part.name}")
                payload.extend(record[end_name + 1 :])
    for path, category, compression, size, payload in files.values():
        if len(payload) != size:
            raise ValueError(f"Incomplete file: {path}")
        if compression == 0x101:
            payload = gzip.decompress(payload)
        elif compression != 0:
            raise ValueError(f"Unsupported Slicer compression {compression}")
        yield path, category, payload


def install_files(release, work):
    source = work / "floppies"
    parts = work / "parts"
    source.mkdir()
    parts.mkdir()
    with ZipFile(release) as zip_file:
        boot = source / "x86BOOT.img"
        boot.write_bytes(zip_file.read("720k/x86BOOT.img"))
        for number in range(1, 12):
            name = f"x86DSK{number:02}.img"
            image = source / name
            image.write_bytes(zip_file.read(f"720k/{name}"))
            copy_from_image(image, "::*", parts)

    indexes = sorted(path for path in parts.iterdir() if path.suffix[1:].isdigit())
    manifest = next(path for path in parts.iterdir() if path.suffix.lower() == ".saf")
    tree = work / "root"
    install = tree / "FDOS"
    installed = {}
    for relative, category, content in archive_files([manifest, *indexes]):
        location = install.joinpath(*relative)
        if location in installed:
            # The classic FDINST and 386 FDNPKG variants reuse three names.
            existing_category = installed[location]
            if "8088" in category and "8088" not in existing_category:
                alternate = tree / "FD386" / location.name
                alternate.parent.mkdir(exist_ok=True)
                location.replace(alternate)
            else:
                location = tree / "FD386" / location.name
        location.parent.mkdir(parents=True, exist_ok=True)
        location.write_bytes(content)
        installed[location] = category

    copy_from_image(boot, "::/KERNEL.SYS", tree / "KERNEL.SYS")
    copy_from_image(boot, "::/FREEDOS/BIN/COMMAND.COM", tree / "COMMAND.COM")
    assemble("cpu386.s", tree / "CPU386.COM", work)
    assemble("pm386.s", tree / "PM386.COM", work)
    config = b"DOS=LOW\r\nFILES=30\r\nBUFFERS=16\r\nLASTDRIVE=E\r\n"
    (tree / "FDCONFIG.SYS").write_bytes(config)
    (tree / "AUTOEXEC.BAT").write_bytes(
        b"@ECHO OFF\r\nSET DOSDIR=C:\\FDOS\r\nSET LANG=EN\r\n"
        b"PATH C:\\FDOS\\BIN;C:\\\r\nPROMPT $P$G\r\n"
    )
    return tree, len(installed)


def make_hard_disk(tree, work):
    sectors = DISK_SECTORS - PARTITION_START
    partition = work / "partition.img"
    command = [
        "mkfs.fat", "-C", "-F", "16", "-s", "8", "-g", f"{HEADS}/{SECTORS}",
        "-h", str(PARTITION_START), "-D", "0x80", "-n", "FREEDOS14",
    ]
    subprocess.run([*command, partition, str(sectors // 2)], check=True)
    subprocess.run(["mcopy", "-s", "-i", partition, *sorted(tree.iterdir()), "::/"], check=True)

    boot_code = work / "vbr.bin"
    assemble("fat16-boot.s", boot_code, work)
    loader = boot_code.read_bytes()
    with partition.open("r+b") as volume:
        bpb = volume.read(SECTOR_SIZE)
        volume.seek(0)
        volume.write(loader[:11] + bpb[11:62] + loader[62:])

    mbr_code = work / "mbr.bin"
    assemble("hard-disk-mbr.s", mbr_code, work)
    bootstrap = mbr_code.read_bytes()
    if len(bootstrap) > 446:
        raise ValueError("Master boot code overlaps the partition table")
    mbr = bytearray(SECTOR_SIZE * PARTITION_START)
    mbr[: len(bootstrap)] = bootstrap
    table = bytes([0x80, 1, 1, 0, 0x04, HEADS - 1, SECTORS, CYLINDERS - 1])
    mbr[446:462] = table + struct.pack("<II", PARTITION_START, sectors)
    mbr[510:512] = b"\x55\xaa"
    return mbr + partition.read_bytes()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=ROOT / ".boot_media")
    parser.add_argument("--output", type=Path, default=ROOT / "src/media")
    args = parser.parse_args()
    for tool in ("as", "objcopy", "mcopy", "mkfs.fat"):
        if shutil.which(tool) is None:
            parser.error(f"Install {tool} (GNU binutils, mtools, and dosfstools are required)")
    args.cache.mkdir(parents=True, exist_ok=True)
    args.output.mkdir(parents=True, exist_ok=True)
    release = fetch(args.cache, "FD14-FloppyEdition.zip")
    with tempfile.TemporaryDirectory(prefix="luau-xt-install-") as temporary:
        work = Path(temporary)
        tree, count = install_files(release, work)
        image = make_hard_disk(tree, work)
        rom = work / "harddisk.rom"
        assemble("hard-disk-rom.s", rom, work)
        firmware = bytearray(rom.read_bytes())
        firmware[-1] = -sum(firmware) % 256
        module(args.output / "DiskRom.luau", firmware)
        disk_modules(args.output / "full_disk", image)
        print(f"Prepared {count} archived files on a writable 20 MiB FreeDOS volume.")


if __name__ == "__main__":
    main()
