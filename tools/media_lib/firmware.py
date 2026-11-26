"""Validate and package user-supplied firmware and display glyphs."""

import hashlib
import re

from .rojo import disk_modules, module


ROM_HASHES = {
    "bios-256k.bin": "ae6f6aa973aaccc143f57aa960fb035fd9de4daee4ad0cd713322f8c259e7650",
    "vgabios.bin": "a7ea86bb06a58ff969fd0942e73b8eae00cb58e4c90bccbd900f6a3a01f54fbb",
}


def read_rom(path, expected):
    rom = path.read_bytes()
    if hashlib.sha256(rom).hexdigest() != ROM_HASHES[expected]:
        raise ValueError(f"{path}: expected the unmodified QEMU 10.1.0 {expected}")
    return rom


def write_firmware(folder, bios_path, vga_path, font_path):
    bios = read_rom(bios_path, "bios-256k.bin")
    vga_bios = read_rom(vga_path, "vgabios.bin")
    font = font_path.read_bytes()
    if font_path.suffix.lower() == ".c":
        font = bytes(int(value, 16) for value in re.findall(rb"^\s*0x([0-9a-fA-F]{2}),", font, re.M))
    if len(font) != 256 * 8:
        raise ValueError("Expected 256 eight-row glyphs in --font (2048 raw bytes or Linux font_8x8.c)")

    folder.mkdir()
    disk_modules(folder / "SeaBios", bios)
    module(folder / "SeaVgaBios.luau", vga_bios)
    module(folder / "Font.luau", font)
