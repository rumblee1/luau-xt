"""Copy supplied files onto a temporary raw FAT disk image."""

import re
import shutil
import subprocess

from .disk import partitions, validate_fat_volume


def dos_name(name):
    if (
        not name
        or name != name.strip()
        or name.endswith(".")
        or not name.isprintable()
        or any(char in name for char in '/\\<>:"|?*[]')
        or re.fullmatch(r"(?i)CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9]", name.split(".")[0])
    ):
        raise ValueError(f"Unsupported FAT name: {name!r}")
    return name


def resolve_destination(images, destination):
    match = re.fullmatch(r"(A|C|D|ide[01]:[1-4]):/(.*)", destination, re.IGNORECASE)
    if not match:
        raise ValueError("--copy-to expects A:/folder, C:/folder, D:/folder, or ide0:1:/folder")
    target, path = match.groups()
    components = [dos_name(name) for name in path.split("/")] if path else []
    if target.upper() == "A":
        slot = "floppy0"
        if slot not in images:
            raise ValueError("A: requires a mounted floppy image")
        image = images[slot]
        validate_fat_volume(image, 0, len(image))
        return slot, 0, components
    if target.upper() in ("C", "D"):
        slot = "ide0" if target.upper() == "C" else "ide1"
        layout = {drive: partitions(image) for drive, image in images.items() if drive.startswith("ide")}
        if slot not in layout or any(len(entries) != 1 or not entries[0].is_fat for entries in layout.values()):
            raise ValueError(f"Cannot resolve {target.upper()}: to a single FAT partition. Use ide0:1:/folder or ide1:1:/folder")
        partition = layout[slot][0]
    else:
        slot, number = target.lower().split(":")
        if slot not in images:
            raise ValueError(f"No disk attached to {slot}")
        partition = next((entry for entry in partitions(images[slot]) if entry.number == int(number)), None)
        if partition is None or not partition.is_fat:
            raise ValueError(f"{slot} partition {number} is not a supported primary FAT partition")
    validate_fat_volume(images[slot], partition.offset, partition.size)
    return slot, partition.offset, components


def copy_files(disk, offset, source, components):
    for tool in ("mdir", "mmd", "mcopy"):
        if shutil.which(tool) is None:
            raise ValueError("Install mtools to use --copy-from")
    if source.is_symlink() or not source.is_dir():
        raise ValueError("--copy-from must be a directory")
    volume = f"{disk}@@{offset}" if offset else str(disk)

    def run(tool, *args, check=True):
        result = subprocess.run(
            [tool, "-i", volume, *args],
            stdin=subprocess.DEVNULL, capture_output=True, text=True, errors="replace",
        )
        if check and result.returncode:
            detail = result.stderr.strip() or result.stdout.strip()
            raise ValueError(f"{tool} failed for {args[-1]}" + (f": {detail}" if detail else ""))
        return result.returncode == 0

    def ensure_directory(target):
        if not run("mdir", "-b", f"{target}/", check=False):
            run("mmd", target)

    def copy_directory(host, guest):
        for item in sorted(host.iterdir()):
            target = f"{guest}/{dos_name(item.name)}"
            if item.is_symlink():
                raise ValueError(f"Cannot copy symbolic link: {item}")
            if item.is_dir():
                ensure_directory(target)
                copy_directory(item, target)
            elif item.is_file():
                if run("mdir", "-b", target, check=False):
                    raise ValueError(f"Destination already exists: {target}")
                run("mcopy", "-D", "s", item.resolve(), target)
            else:
                raise ValueError(f"Cannot copy {item}: expected a regular file or directory")

    run("mdir", "-b", "::/")
    guest = "::"
    for component in components:
        guest += "/" + component
        ensure_directory(guest)
    copy_directory(source, guest)
