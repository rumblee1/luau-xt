"""Build the games, drawing tools, and original pictures on the VGA disk."""
from math import cos, hypot, sin
from pathlib import Path
from random import Random
import struct

from prepare_media import assemble

WIDTH, HEIGHT = 320, 200
FILES = {
    "GAMES": {"ORBIT.COM": "orbit.s", "SIGNAL.COM": "signal.s"},
    "APPS": {"PIXEL.COM": "pixel.s", "PALETTE.COM": "palette.s"},
}


def ramp(first, last, count):
    return [
        tuple(round(a + (b - a) * step / (count - 1)) for a, b in zip(first, last))
        for step in range(count)
    ]


def shade(value, colors):
    return max(0, min(colors - 1, int(value * colors)))


def bitmap(palette, pixel):
    """Store a bottom-up, uncompressed 8-bit BMP for BMPVIEW."""
    pixels = bytes(pixel(x, y) for y in range(HEIGHT - 1, -1, -1) for x in range(WIDTH))
    colors = b"".join(bytes((b, g, r, 0)) for r, g, b in palette).ljust(1024, b"\0")
    offset = 54 + len(colors)
    header = struct.pack("<2sIHHI", b"BM", offset + len(pixels), 0, 0, offset)
    info = struct.pack("<IiiHHIIiiII", 40, WIDTH, HEIGHT, 1, 8, 0, len(pixels), 0, 0, 256, 0)
    return header + info + colors + pixels


def sunset_bmp():
    palette = (
        ramp((19, 27, 79), (240, 133, 114), 64)
        + ramp((255, 152, 95), (255, 237, 168), 16)
        + ramp((61, 57, 106), (154, 83, 125), 24)
        + ramp((26, 38, 66), (79, 64, 101), 24)
        + ramp((18, 38, 62), (134, 86, 124), 32)
        + ramp((120, 78, 115), (249, 166, 93), 24)
        + ramp((9, 21, 39), (42, 47, 63), 16)
    )
    distant = [105 + 10 * sin(x / 29) + 8 * abs(sin(x / 8)) for x in range(WIDTH)]
    ridge = [123 + 10 * sin(x / 20) + 6 * sin(x / 8) for x in range(WIDTH)]

    def pixel(x, y):
        if y < distant[x]:
            if hypot((x - 224) / 1.18, y - 78) < 25 and not (y > 84 and y % 5 == 0):
                return 64 + shade((104 - y) / 52, 16)
            cloud = 0.05 * sin(x / 35 + y / 7) if 38 < y < 63 and y % 3 != 0 else 0
            return shade(y / 116 + cloud, 64)
        if y < ridge[x]:
            return 80 + shade((114 - distant[x]) / 30 + (y - distant[x]) / 90, 24)
        if y < 144 - 0.11 * abs(x - 217):
            return 104 + shade((y - 115) / 32, 24)
        if y < 192 - abs(x - 170) * 0.15:
            ripples = cos(x / 9 + y / 2) * 0.15 + sin(x / 21 - y) * 0.15
            if abs(x - 221) < 10 + (y - 122) / 2 and cos(y * 2.4 + x / 31) > 0:
                return 160 + shade(0.64 + ripples - abs(x - 221) / 70, 24)
            return 128 + shade(0.65 + ripples - (y - 128) / 90, 32)
        return 184 + shade((sin(x / 13) + cos(y / 4) + sin(x / 3 + y / 2)) / 9 + 0.38, 16)

    return bitmap(palette, pixel)


def nebula_bmp():
    palette = (
        ramp((7, 10, 28), (96, 63, 135), 64)
        + ramp((65, 73, 129), (205, 230, 250), 16)
        + ramp((18, 30, 81), (167, 120, 173), 48)
        + ramp((39, 86, 132), (166, 224, 210), 48)
        + ramp((72, 61, 106), (232, 179, 143), 32)
    )
    rng = Random(8547)
    stars = {(rng.randrange(WIDTH), rng.randrange(HEIGHT)): 64 + rng.randrange(16) for _ in range(480)}

    def pixel(x, y):
        dx, dy = (x - 206) / 1.18, y - 102
        distance = hypot(dx, dy)
        ring = hypot(dx + dy * 0.83, dy * 2.8)
        rings = 64 < ring < 81 or 88 < ring < 94
        if distance < 49 and (not rings or dy < 0):
            light = (1 - (dx + dy * 0.6) / 68) / 2
            bands = sin((dy - dx * 0.22) / 3) * 0.07 + sin(dy / 1.8) * 0.04
            return 128 + shade(light + bands, 48)
        if rings:
            return 176 + shade(0.88 - ring / 105 + 0.36 * sin(ring / 2), 32)
        if hypot((x - 74) / 1.18, y - 52) < 14:
            return 80 + shade(0.42 + (74 - x) / 30 + (52 - y) / 80, 48)
        if (x, y) in stars:
            return stars[x, y]
        cloud = 1 - abs(y - 88 - 31 * sin(x / 66)) / 68
        dust = (sin(x / 19 + y / 13) + cos(x / 11 - y / 21) + sin(x / 6 + y / 5)) / 9
        return shade((0.22 + dust) * cloud + 0.08, 64)

    return bitmap(palette, pixel)


def write_library(target: Path, work: Path):
    for folder, programs in FILES.items():
        directory = target / folder
        directory.mkdir()
        for name, source in programs.items():
            assemble(source, directory / name, work)

    pictures = target / "PICS"
    pictures.mkdir()
    (pictures / "SUNSET.BMP").write_bytes(sunset_bmp())
    (pictures / "NEBULA.BMP").write_bytes(nebula_bmp())

    commands = (
        "@ECHO OFF",
        "ECHO VGA Library",
        "ECHO.",
        "ECHO GAMES\\ORBIT         Arrows steer. Space brakes. Avoid red.",
        "ECHO GAMES\\SIGNAL        Arrows to move, Space to reveal. Find all eight pairs.",
        "ECHO APPS\\PIXEL          Arrows to move, 0-8 to pick a color, Space to paint.",
        "ECHO                     S saves SKETCH.BMP. Green saved. Red failed.",
        "ECHO APPS\\PALETTE        Arrows to browse. Enter prints the selected index.",
        "ECHO BMPVIEW PICS\\SUNSET.BMP",
        "ECHO BMPVIEW PICS\\NEBULA.BMP",
        "ECHO BEEP               Test the virtual PC speaker.",
        "ECHO VGACLIP DEMO.VCL",
        "IF EXIST C:\\BADAPPLE.VCL ECHO BADAPPLE            Play the Bad Apple video.",
        "ECHO.",
        "ECHO Press Esc to leave the games, tools and player. Any key closes a picture.",
        "",
    )
    assemble("beep.s", target / "BEEP.COM", work)
    (target / "VGA.BAT").write_bytes("\r\n".join(commands).encode("ascii"))
