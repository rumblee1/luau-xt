"""Build a bootable Luau 386 disk using GNU GRUB Legacy 0.97 boot stages."""
import argparse
import gzip
import io
from pathlib import Path
import struct
import subprocess
import tarfile
import tempfile
from zipfile import ZipFile

from install_freedos import CYLINDERS, DISK_SECTORS, HEADS, SECTOR_SIZE, SECTORS
from prepare_media import ROOT, disk_modules, fetch

GRUB_PACKAGE = {
    "grub-etch.deb": (
        "https://archive.debian.org/debian/pool/main/g/grub/grub_0.97-27etch1_i386.deb",
        "b08773b973aa6f958a426fc668d755b58c2bad89245f842853c9020ea36555bb",
    )
}
FREESCO_RELEASE = {
    "freesco-045.zip": (
        "https://downloads.sourceforge.net/project/freesco/freesco/v0.4.5/freesco-045.zip",
        "9e67f0f89078eefa2ebc14e65bb83143b8a81be60f9107b9218f90f8822d506f",
    )
}
NANO_PACKAGES = {
    "nano_0.9.23-1_i386.deb": (
        "https://archive.debian.org/debian/pool/main/n/nano/nano_0.9.23-1_i386.deb",
        "c36de297e8a13566938105d6e7287ed726a1d0428ecc25ce8cdf1835e6484da4",
    ),
    "libc6_2.1.3-20_i386.deb": (
        "https://archive.debian.org/debian/pool/main/g/glibc/libc6_2.1.3-20_i386.deb",
        "0c3937f80ae515abc69d44d18b4d8d924491f4b6c6420a0bfdaf2da91c174be6",
    ),
    "libncurses5_5.0-6.0potato2_i386.deb": (
        "https://archive.debian.org/debian/pool/main/n/ncurses/libncurses5_5.0-6.0potato2_i386.deb",
        "b6730854b4cbbd24e89b882e40e36aa6bffc81dafe10070a66d9ee90939c5d48",
    ),
    "ncurses-base_5.0-6.0potato2_all.deb": (
        "https://archive.debian.org/debian/pool/main/n/ncurses/ncurses-base_5.0-6.0potato2_all.deb",
        "b272ec39a7f00c58854f876f32693bf2a64a810449f96033cde7044da9457ec0",
    ),
}
NANO_FILES = {
    "nano_0.9.23-1_i386.deb": {"./usr/bin/nano": "/bin/nano"},
    "libc6_2.1.3-20_i386.deb": {
        "./lib/ld-2.1.3.so": "/lib/ld-linux.so.2",
        "./lib/libc-2.1.3.so": "/lib/libc.so.6",
    },
    "libncurses5_5.0-6.0potato2_i386.deb": {"./lib/libncurses.so.5.0": "/lib/libncurses.so.5"},
    "ncurses-base_5.0-6.0potato2_all.deb": {"./etc/terminfo/l/linux": "/etc/terminfo/l/linux"},
}
BUSYBOX_COMMANDS = (
    "busybox", "clear", "cmp", "cp", "dd", "df", "dmesg", "find", "gzip",
    "gunzip", "ls", "mkdir", "more", "mv", "pwd", "rm", "sleep", "sort",
    "tar", "touch", "wc", "zcat",
)
PARTITION_START = 512


def deb_payload(package):
    members = subprocess.check_output(["ar", "t", package], text=True).splitlines()
    member = next(name for name in members if name.startswith("data.tar"))
    payload = subprocess.check_output(["ar", "p", package, member])
    return tarfile.open(fileobj=io.BytesIO(payload))


def freesco_media(archive, cache, work):
    # The default floppy kernel requires an x87. Use the software-math build.
    floppy = work / "freesco.img"
    kernel = work / "kernel.sx"
    initrd = work / "ramdisk.gz"
    with ZipFile(archive) as release:
        floppy.write_bytes(release.read("FREESCO-045/freesco.045"))
        kernel.write_bytes(release.read("FREESCO-045/kernel.sx"))
    subprocess.run(["mcopy", "-i", floppy, "::/RAMDISK", initrd], check=True)

    # FREESCO normally installs BusyBox links from its startup scripts.
    # Install the standard shell utilities before starting ash directly.
    rootfs = work / "root.ext2"
    rootfs.write_bytes(gzip.decompress(initrd.read_bytes()))
    uname_object = work / "uname.o"
    uname = work / "uname"
    subprocess.run(["as", "--32", ROOT / "guest/uname.s", "-o", uname_object], check=True)
    subprocess.run(["ld", "-m", "elf_i386", "-static", "-s", uname_object, "-o", uname], check=True)
    commands = [f"symlink /bin/{name} mount" for name in BUSYBOX_COMMANDS]
    commands.extend(["mkdir /etc/terminfo", "mkdir /etc/terminfo/l"])
    # This ash build searches its built-ins at the %builtin entry in PATH.
    profile = work / "profile"
    profile.write_text("PATH=/bin:/sbin:/usr/bin:/usr/sbin:%builtin\nexport PATH\n", encoding="ascii")
    files = {"/bin/uname": uname, "/etc/profile": profile}
    for name, members in NANO_FILES.items():
        with deb_payload(fetch(cache, name, NANO_PACKAGES)) as package:
            for member, destination in members.items():
                source = work / Path(destination).name
                source.write_bytes(package.extractfile(member).read())
                source.chmod(package.getmember(member).mode & 0o777)
                files[destination] = source
    commands.extend(f'write "{source}" {destination}' for destination, source in files.items())
    script = work / "debugfs-commands"
    script.write_text("\n".join(commands) + "\n", encoding="utf-8")
    subprocess.run(["debugfs", "-w", "-f", script, rootfs], check=True)
    for path in [*(f"/bin/{name}" for name in BUSYBOX_COMMANDS), *files]:
        result = subprocess.check_output(["debugfs", "-R", f"stat {path}", rootfs], text=True)
        if not result.startswith("Inode:"):
            raise ValueError(f"Could not install {path} into the FREESCO RAM disk")
    # Copying ext2 blocks in the guest is faster than inflating them on the emulated CPU.
    return kernel, rootfs


def grub_stages(package):
    with deb_payload(package) as files:
        stage1 = bytearray(files.extractfile("./usr/lib/grub/i386-pc/stage1").read())
        stage2 = bytearray(files.extractfile("./usr/lib/grub/i386-pc/stage2").read())

    if len(stage1) != SECTOR_SIZE or stage1[510:] != b"\x55\xaa" or stage2[518:520] != b"\x03\x02":
        raise ValueError("Unexpected GRUB 0.97 boot stage format")
    stage1[0x40] = 0xFF  # The BIOS supplies the boot drive in DL.
    stage1[0x41] = 0
    struct.pack_into("<HIH", stage1, 0x42, 0x8000, 1, 0x0800)

    sectors = (len(stage2) + SECTOR_SIZE - 1) // SECTOR_SIZE
    stage2.extend(bytes(sectors * SECTOR_SIZE - len(stage2)))
    # Stage 2's first sector reads the rest as a contiguous block list.
    struct.pack_into("<IHH", stage2, SECTOR_SIZE - 8, 2, sectors - 1, 0x0820)
    struct.pack_into("<I", stage2, SECTOR_SIZE + 8, 0x0000FFFF)  # First primary partition.
    return stage1, stage2


def make_image(package, work, kernel, initrd, linux_title):
    stage1, stage2 = grub_stages(package)
    if len(stage2) + SECTOR_SIZE > PARTITION_START * SECTOR_SIZE:
        raise ValueError("The GRUB stages overlap the boot partition")
    partition_sectors = DISK_SECTORS - PARTITION_START
    start_cylinder = PARTITION_START // (HEADS * SECTORS)
    entry = bytes([0x80, 0, 1, start_cylinder, 4, HEADS - 1, SECTORS, CYLINDERS - 1])
    stage1[446:462] = entry + struct.pack("<II", PARTITION_START, partition_sectors)

    partition = work / "partition.img"
    subprocess.run([
        "mkfs.fat", "-C", "-F", "16", "-s", "8", "-g", f"{HEADS}/{SECTORS}",
        "-h", str(PARTITION_START), "-D", "0x80", "-n", "LUAU386",
        partition, str(partition_sectors // 2),
    ], check=True)
    boot = work / "boot"
    grub = boot / "grub"
    grub.mkdir(parents=True)
    menu = (
        "default 0\n"
        "title Luau 386 - GRUB Legacy 0.97\n"
        "  root (hd0,0)\n"
        "  kernel /boot/diag386\n"
        "title Halt machine\n"
        "  halt --no-apm\n"
    )
    obj = work / "grub386.o"
    subprocess.run(["as", "--32", ROOT / "guest/grub386.s", "-o", obj], check=True)
    subprocess.run(["ld", "-m", "elf_i386", "--nmagic", "-Ttext", "0x100000", obj, "-o", boot / "diag386"], check=True)
    if kernel:
        (boot / "linux").write_bytes(kernel.read_bytes())
        (boot / "initrd").write_bytes(initrd.read_bytes())
        menu = (
            "default 0\n"
            f"title {linux_title}\n"
            "  root (hd0,0)\n"
            "  kernel /boot/linux root=/dev/ram0 rw mem=16M ramdisk_size=4096 init=/bin/sh\n"
            "  initrd /boot/initrd\n"
            + menu.removeprefix("default 0\n")
        )
    (grub / "menu.lst").write_text(menu, encoding="ascii")
    subprocess.run(["mcopy", "-s", "-i", partition, boot, "::/"], check=True)

    boot_track = (stage1 + stage2).ljust(PARTITION_START * SECTOR_SIZE, b"\0")
    return boot_track + partition.read_bytes()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=ROOT / ".boot_media")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--freesco", action="store_true", help="Use the FREESCO 0.4.5 software-math kernel and RAM disk")
    parser.add_argument("--kernel", type=Path)
    parser.add_argument("--initrd", type=Path)
    args = parser.parse_args()
    if bool(args.kernel) != bool(args.initrd):
        parser.error("--kernel and --initrd must be provided together")
    if args.freesco and args.kernel:
        parser.error("--freesco downloads a kernel and initrd and cannot be used with --kernel")
    args.cache.mkdir(parents=True, exist_ok=True)
    package = fetch(args.cache, "grub-etch.deb", GRUB_PACKAGE)
    archive = fetch(args.cache, "freesco-045.zip", FREESCO_RELEASE) if args.freesco else None
    with tempfile.TemporaryDirectory(prefix="luau-386-") as directory:
        work = Path(directory)
        kernel, initrd = freesco_media(archive, args.cache, work) if archive else (args.kernel, args.initrd)
        title = "Linux 2.0.40 (FREESCO)" if archive else "Linux (experimental)"
        image = make_image(package, work, kernel, initrd, title)
    output = args.output or ROOT / "src/media" / ("linux_disk" if args.freesco else "grub_disk")
    disk_modules(output, image)
    print("Prepared the GRUB Legacy disk.")


if __name__ == "__main__":
    main()
