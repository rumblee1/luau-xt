# Luau XT

Luau XT runs a 386 PC inside Roblox Studio. Bring your own bootable floppy or hard disk image and use it to run DOS, Windows 3.1, or other software that fits the emulated hardware.

## Quick start

This example boots a disk that already has DOS installed.

### 1. Gather your files

- Install Python 3, Roblox Studio, and Rojo 7.7.1 with the Rojo Studio plugin. [Rojo installation guide](https://rojo.space/docs/installation/)
- In the project folder, create a `roms/` folder. Save QEMU 10.1.0's [bios-256k.bin](https://raw.githubusercontent.com/qemu/qemu/v10.1.0/pc-bios/bios-256k.bin) and [vgabios.bin](https://raw.githubusercontent.com/qemu/qemu/v10.1.0/pc-bios/vgabios.bin) there, along with Linux's [font_8x8.c](https://raw.githubusercontent.com/torvalds/linux/v6.12/lib/fonts/font_8x8.c).
- Put your DOS hard disk image at `images/dos.img`, or substitute its path in the commands below. Use a raw image, which is a sector-by-sector copy of the disk. [Supported image sizes](docs/usage.md#choose-a-disk-image)

### 2. Import the disk

Run these commands from the project folder. If your Python 3 command is `python` or `py -3`, use that in place of `python3`.

```sh
python3 tools/media.py inspect ./images/dos.img
python3 tools/media.py import-firmware --bios ./roms/bios-256k.bin --vga-bios ./roms/vgabios.bin --font ./roms/font_8x8.c
python3 tools/media.py import-disk ./images/dos.img --name "My DOS PC"
```

Check that `inspect` reports a supported IDE size and a BIOS boot signature. Import the firmware once per checkout and reuse it for future disks. The disk import creates a profile called **My DOS PC** and leaves your original image intact.

### 3. Power on in Studio

```sh
rojo serve
```

Leave that terminal running. Open an empty place in Roblox Studio, connect the Rojo plugin to the server address shown in the terminal, and start **Play**. Select **My DOS PC** if the profile button shows a different name, then click **Power on**. With a working DOS installation, you should see a prompt such as `C:\>`. Type `DIR` to list the files on the disk.

## What to try next

- [Add your own files to a disk](docs/usage.md#add-files-to-a-disk)
- [Attach a second drive](docs/usage.md#attach-a-second-drive)
- [Boot a preinstalled Windows 3.1 image](docs/usage.md#boot-windows-31)
- [Fix a boot problem](docs/usage.md#troubleshoot)

## Tests

The smoke test uses the Luau CLI and runs without boot media.

```sh
luau --codegen tests/smoke.luau
```

## Media and license

Imported firmware and disks are stored in the Git-ignored `src/media/` folder. Rojo can include these files in a place build, so use a clean checkout if you want to share a build without your local media.

[Usage guide](docs/usage.md) · [MIT license](LICENSE) · [Third-party notices](THIRD_PARTY_NOTICES.md)
