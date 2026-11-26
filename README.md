# Luau XT

A 386 PC emulator written in Luau for Roblox. It uses stock SeaBIOS and emulates VGA, IDE storage, keyboard and mouse input, and Sound Blaster audio.

## Quick start

Install Python 3 and Rojo 7.7.1. Supply your own compatible raw boot image, the SeaBIOS and VGA BIOS binaries from QEMU 10.1.0, and an 8×8 display font.

```sh
python3 tools/media.py import-firmware \
  --bios ./roms/bios-256k.bin --vga-bios ./roms/vgabios.bin --font ./roms/font_8x8.c
python3 tools/media.py import-disk ./images/boot.img --name "My PC"
rojo serve
```

Connect the Rojo plugin to an empty Roblox Studio place and start **Play**. Choose **My PC** and click **Power on**. For a 360 KiB boot floppy, use `import-floppy` instead of `import-disk`.

## Tests

Install the Luau CLI. This smoke test runs without boot media.

```sh
luau --codegen tests/smoke.luau
```

## Media and license

The repository ships source code. Imported firmware and disk images are encoded locally in `src/media/`. Use a clean checkout for any public place build, since Rojo can include the generated images in its export.

See [usage and optional profiles](docs/usage.md), the [MIT license](LICENSE), and [third-party notices](THIRD_PARTY_NOTICES.md).
