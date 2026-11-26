"""Check raw image geometry and locate MBR partitions."""

import struct
from dataclasses import dataclass


SECTOR_SIZE = 512
FLOPPY_SIZE = 360 * 1024
CYLINDER_SIZE = 16 * 32 * SECTOR_SIZE
FAT_TYPES = {0x01, 0x04, 0x06, 0x0B, 0x0C, 0x0E}
BOOT_SIGNATURE = b"\x55\xaa"


@dataclass(frozen=True)
class Partition:
    number: int
    kind: int
    offset: int
    size: int

    @property
    def is_fat(self):
        return self.kind in FAT_TYPES


def validate_geometry(size, slot):
    if slot == "floppy0":
        if size != FLOPPY_SIZE:
            raise ValueError("Expected a 360 KiB raw floppy image")
    elif not 1 <= size // CYLINDER_SIZE <= 127 or size % CYLINDER_SIZE:
        raise ValueError("Expected a raw IDE image with 1–127 whole 256 KiB cylinders (16 heads, 32 sectors per track)")


def read_image(path, slot, *, boot=False):
    with path.open("rb") as source:
        size = source.seek(0, 2)
        validate_geometry(size, slot)
        source.seek(0)
        image = source.read(size + 1)
    if len(image) != size:
        raise ValueError(f"{path}: size changed while reading")
    if boot and image[510:512] != BOOT_SIGNATURE:
        raise ValueError(f"{path}: no BIOS boot signature in the first sector")
    return image


def partitions(image):
    if image[510:512] != BOOT_SIGNATURE:
        return []
    result = []
    for number in range(1, 5):
        status, kind, start, count = struct.unpack_from("<B3xB3xII", image, 446 + (number - 1) * 16)
        if kind == 0:
            continue
        if status not in (0, 0x80) or not start or not count or (start + count) * SECTOR_SIZE > len(image):
            raise ValueError(f"MBR partition {number} has an invalid status or sector range")
        result.append(Partition(number, kind, start * SECTOR_SIZE, count * SECTOR_SIZE))
    ordered = sorted(result, key=lambda partition: partition.offset)
    if any(first.offset + first.size > second.offset for first, second in zip(ordered, ordered[1:])):
        raise ValueError("MBR partitions overlap")
    return result


def validate_fat_volume(image, offset, size):
    sector = image[offset : offset + SECTOR_SIZE]
    bytes_per_sector = struct.unpack_from("<H", sector, 11)[0]
    sector_count = struct.unpack_from("<H", sector, 19)[0] or struct.unpack_from("<I", sector, 32)[0]
    if (
        sector[0] not in (0xE9, 0xEB)
        or bytes_per_sector != SECTOR_SIZE
        or not sector_count
        or sector_count * SECTOR_SIZE > size
    ):
        raise ValueError("Target does not contain a readable FAT boot sector within the volume")
