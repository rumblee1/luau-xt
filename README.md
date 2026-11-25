# Luau XT

A PC emulator written in Luau for Roblox, with 8088 and experimental 386 profiles. It boots FreeDOS and emulates CGA text, VGA graphics, a keyboard, a serial mouse, and basic sound hardware.

## Quick start

Install Python 3, GNU binutils with x86 support, mtools, and Rojo 7.7.1. The pinned Rojo version is in `rokit.toml`.

```sh
python3 tools/prepare_media.py
rojo serve
```

Connect the Rojo plugin to an empty Roblox Studio place, start **Play**, and click **Power on**. At the FreeDOS prompt, run `HELLO`. For VGA demos, select **386 VGA** before powering on and run `BMPVIEW SAMPLE.BMP`.

## Tests

Install the Luau CLI, then run:

```sh
luau --codegen tests/smoke.luau tests/boot.luau tests/vga.luau
```

## Media and license

The repository ships source code. Boot images and optional guest media are generated locally in `src/media/`. Use a clean checkout for any public place build, since Rojo can include the generated images in its export.

See [usage and optional profiles](docs/usage.md), the [MIT license](LICENSE), and [third-party notices](THIRD_PARTY_NOTICES.md).
