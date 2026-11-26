"""Generate Luau modules for the unmodified SeaBIOS ROMs shipped with QEMU."""
import argparse
from pathlib import Path

from prepare_media import ROOT, disk_modules, fetch, module

QEMU_ROMS = "https://raw.githubusercontent.com/qemu/qemu/v10.1.0/pc-bios"
SOURCES = {
    "bios-256k.bin": (
        f"{QEMU_ROMS}/bios-256k.bin",
        "ae6f6aa973aaccc143f57aa960fb035fd9de4daee4ad0cd713322f8c259e7650",
    ),
    "vgabios.bin": (
        f"{QEMU_ROMS}/vgabios.bin",
        "a7ea86bb06a58ff969fd0942e73b8eae00cb58e4c90bccbd900f6a3a01f54fbb",
    ),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=ROOT / ".boot_media" / "seabios")
    parser.add_argument("--output", type=Path, default=ROOT / "src" / "media")
    args = parser.parse_args()

    args.cache.mkdir(parents=True, exist_ok=True)
    bios = fetch(args.cache, "bios-256k.bin", SOURCES).read_bytes()
    vga_bios = fetch(args.cache, "vgabios.bin", SOURCES).read_bytes()
    disk_modules(args.output / "SeaBios", bios)
    module(args.output / "SeaVgaBios.luau", vga_bios)


if __name__ == "__main__":
    main()
