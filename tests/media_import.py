"""Regression coverage for the host-side media importer."""

import base64
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
import unittest


CLI = Path(__file__).resolve().parents[1] / "tools" / "media.py"


def reconstruct(folder):
    index = (folder / "Index.luau").read_text()
    image = bytearray(int(re.search(r"size = (\d+)", index)[1]))
    for disk_offset, part in re.findall(r'\{ (\d+), "(Part\d+)" \}', index):
        module = (folder / f"{part}.luau").read_text()
        for chunk_offset, encoded in re.findall(r'\{ (\d+), "([^"]+)" \}', module):
            data = base64.b64decode(encoded)
            offset = int(disk_offset) + int(chunk_offset)
            image[offset : offset + len(data)] = data
    return image


class MediaImportTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name)
        self.media = self.work / "media"
        self.floppy = self.work / "floppy.img"
        subprocess.run(["mformat", "-i", self.floppy, "-f", "360", "-C", "::"], check=True)
        self.original_floppy = self.floppy.read_bytes()

        self.offset = 32 * 512
        hard_disk = bytearray(512 * 1024)
        hard_disk[510:512] = b"\x55\xaa"
        struct.pack_into("<B3xB3xII", hard_disk, 446, 0x80, 0x01, 32, len(self.original_floppy) // 512)
        hard_disk[self.offset : self.offset + len(self.original_floppy)] = self.original_floppy
        self.primary = self.work / "primary.img"
        self.primary.write_bytes(hard_disk)
        self.secondary = self.work / "secondary.img"
        self.secondary.write_bytes(hard_disk)
        self.original_disk = bytes(hard_disk)

        self.files = self.work / "files"
        (self.files / "DOCS").mkdir(parents=True)
        (self.files / "DOCS" / "README.TXT").write_bytes(b"import test\r\n")

    def cli(self, *args, check=True):
        return subprocess.run(
            [sys.executable, CLI, *args, "--output", self.media],
            capture_output=True, text=True, check=check,
        )

    def read_added_file(self, folder, offset=0):
        recovered = self.work / "recovered.img"
        recovered.write_bytes(reconstruct(folder))
        volume = f"{recovered}@@{offset}" if offset else recovered
        return subprocess.check_output(["mtype", "-i", volume, "::/EXTRAS/DOCS/README.TXT"])

    def test_copy_to_second_ide_drive(self):
        for name, target in (("Explicit", "ide1:1:/EXTRAS"), ("Letter", "D:/EXTRAS")):
            with self.subTest(target=target):
                self.cli(
                    "import-disk", self.primary, "--name", name, "--attach", self.secondary, "--slot", "ide1",
                    "--copy-from", self.files, "--copy-to", target,
                )
                profile = self.media / "Imported" / name.lower()
                self.assertEqual(reconstruct(profile / "HardDisk"), self.original_disk)
                self.assertEqual(self.read_added_file(profile / "SecondHardDisk", self.offset), b"import test\r\n")
        self.assertEqual(self.primary.read_bytes(), self.original_disk)
        self.assertEqual(self.secondary.read_bytes(), self.original_disk)

    def test_floppy_copy_and_duplicate_profile(self):
        arguments = ("import-floppy", self.floppy, "--name", "DOS", "--copy-from", self.files, "--copy-to", "A:/EXTRAS")
        self.cli(*arguments)
        profile = self.media / "Imported" / "dos"
        self.assertEqual(self.read_added_file(profile / "Floppy"), b"import test\r\n")
        self.assertEqual(self.floppy.read_bytes(), self.original_floppy)
        self.assertIn("already exists", self.cli(*arguments, check=False).stderr)

    def test_copy_to_primary_ide_drive(self):
        self.cli(
            "import-disk", self.primary, "--name", "Primary",
            "--copy-from", self.files, "--copy-to", "C:/EXTRAS",
        )
        profile = self.media / "Imported" / "primary"
        self.assertEqual(self.read_added_file(profile / "HardDisk", self.offset), b"import test\r\n")
        self.assertEqual(self.primary.read_bytes(), self.original_disk)

    def test_failed_copy_leaves_no_profile(self):
        subprocess.run(
            ["mcopy", "-i", self.floppy, self.files / "DOCS" / "README.TXT", "::/README.TXT"], check=True,
        )
        source_before = self.floppy.read_bytes()
        (self.files / "README.TXT").write_bytes(b"replacement file")
        result = self.cli(
            "import-floppy", self.floppy, "--name", "Collision", "--copy-from", self.files, "--copy-to", "A:/", check=False,
        )
        self.assertIn("Destination already exists", result.stderr)
        self.assertEqual(self.floppy.read_bytes(), source_before)
        self.assertFalse((self.media / "Imported" / "collision").exists())


if __name__ == "__main__":
    unittest.main()
