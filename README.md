# Luau XT

A 386 PC emulator written in Luau for Roblox. It uses stock SeaBIOS and emulates VGA, IDE storage, keyboard and mouse input, and Sound Blaster audio.

## Quick start

Install Python 3, GNU binutils with x86 support, mtools, and Rojo 7.7.1. The pinned Rojo version is in `rokit.toml`.

```sh
python3 tools/prepare_media.py
python3 tools/prepare_seabios.py
rojo serve
```

Connect the Rojo plugin to an empty Roblox Studio place and start **Play**. Choose **FreeDOS**, click **Power on**, and run `BMPVIEW SAMPLE.BMP`.

## Tests

Install the Luau CLI, then run:

```sh
luau --codegen tests/seabios.luau -a dos
```

## Media and license

The repository ships source code. Boot images and optional guest media are generated locally in `src/media/`. Use a clean checkout for any public place build, since Rojo can include the generated images in its export.

See [usage and optional profiles](docs/usage.md), the [MIT license](LICENSE), and [third-party notices](THIRD_PARTY_NOTICES.md).
