# Usage

See the [quick start](../README.md#quick-start) for the initial firmware and disk import.

## Hardware and boot profiles

| Component | Luau XT |
| --- | --- |
| CPU | 386 core with the additional instructions used by the stock SeaBIOS build |
| Memory | 640 KiB conventional RAM and 15 MiB extended RAM |
| Firmware | SeaBIOS 1.17.0 and SeaVGABIOS |
| Storage | One 360 KiB floppy and up to two IDE disks |
| Video | 80×25 text, 320×200 indexed graphics, and 640×480 planar graphics |
| Input and sound | PC keyboard, Microsoft serial mouse on COM1, PC speaker, and Sound Blaster-compatible audio |

Click the profile button to cycle through the systems with media available, then click **Power on**. **Restart** preserves disks in the current Play session. Selecting a different system and powering it on loads that system's generated image. A fresh Play session also starts from the generated images.

Luau XT uses the original SeaBIOS and SeaVGABIOS binaries from QEMU 10.1.0. The media builder checks both SHA-256 digests. The emulator provides Intel 440FX shadow memory, QEMU's firmware configuration ports, and IDE. The client scheduler paces guest time against the 1.193 MHz PIT. [SeaBIOS source](https://qemu.googlesource.com/seabios/+/refs/tags/rel-1.17.0) · [QEMU firmware configuration](https://www.qemu.org/docs/master/specs/fw_cfg.html)

## Import your own media

`tools/media.py` reads local files and writes media modules under `src/media/`. Rojo sync is a separate step. The importer creates new entries and rejects names that already exist. Use `--output` to write to a different media folder.

Import firmware once with `import-firmware`. Use the two QEMU 10.1.0 ROMs from the quick start and either Linux's `font_8x8.c` or a raw 2,048-byte font with 256 eight-row glyphs. The importer checks the ROM hashes. [QEMU ROM files](https://github.com/qemu/qemu/tree/v10.1.0/pc-bios) · [Linux font source](https://github.com/torvalds/linux/blob/v6.12/lib/fonts/font_8x8.c)

Use `inspect` to check the geometry and see the partition layout before importing.

```sh
python3 tools/media.py inspect ./images/windows31.img
python3 tools/media.py import-floppy ./images/dos-boot.img --name "DOS floppy"
```

IDE images must be raw, contain 1–127 whole 256 KiB cylinders, and use 16 heads and 32 sectors per track for CHS addressing. A boot image needs a BIOS boot signature. Use `--attach IMAGE --slot ide1` for a second IDE disk or `--attach IMAGE --slot floppy0` to mount a 360 KiB floppy alongside the boot IDE disk.

### Copy files to a disk

Install `mtools` for file copying. The importer copies recursively into a temporary image. If a destination file already exists, the import stops. Your original images stay intact.

```sh
python3 tools/media.py import-disk ./images/windows31.img \
  --name "Windows 3.1 with my files" \
  --copy-from ./my-files --copy-to C:/EXTRAS
```

For IDE disks, the file-copy feature supports primary FAT partitions in an MBR. Use `C:/` for the first IDE disk and `D:/` for the second when each attached IDE disk has one primary FAT partition. For other layouts, use an explicit slot and MBR partition number, such as `ide1:1:/EXTRAS`. For a mounted FAT floppy, use `A:/EXTRAS`.

```sh
python3 tools/media.py import-disk ./images/windows31.img \
  --name "Windows 3.1 with a data disk" \
  --attach ./images/data.img --slot ide1 \
  --copy-from ./my-files --copy-to ide1:1:/EXTRAS
```

## FreeDOS apps, games, and media

If you already have a Luau XT FreeDOS library disk or demo floppy, boot it to run the included apps.

```dos
BMPVIEW SAMPLE.BMP
VGACLIP DEMO.VCL
```

`BMPVIEW` accepts uncompressed, indexed 8-bit BMPs up to 320×200. Press any key to close it. `VGACLIP` plays silent monochrome video at up to 9.1 frames per emulated second. Press Esc to return to DOS. Both run on the guest CPU and draw through VGA memory. The Roblox display uses EditableImage.

### VGA library

In **FreeDOS**, type `VGA` at `C:\>` to list the installed games, tools, and pictures.

| Command | Controls |
| --- | --- |
| `GAMES\ORBIT` | Arrow keys steer, and Space brakes. Collect eight yellow beacons and avoid the red sweeper. |
| `GAMES\SIGNAL` | Arrow keys move between tiles. Space or Enter reveals a tile. Find eight matching pairs. |
| `APPS\PIXEL` | Arrow keys move. Keys 0–8 select a color, and Space paints. S saves a new `SKETCH.BMP` in the current directory. The status light is green on success and red on failure, including when a sketch already exists. Open it with `BMPVIEW SKETCH.BMP`. |
| `APPS\PALETTE` | Arrow keys browse 256 color swatches. Enter prints the selected palette index and returns to DOS. |
| `BMPVIEW PICS\SUNSET.BMP` | View a mountain sunset. |
| `BMPVIEW PICS\NEBULA.BMP` | View a ringed planet. |

Press Esc to exit games and tools. Any key closes a picture. Guest writes such as `SKETCH.BMP` last for the current Play session, including restarts within that session.

### Play a local video

If your disk contains `VGACLIP.COM`, copy an existing `.VCL` file into its FAT partition and run `VGACLIP VIDEO.VCL` using the copied file's name. If your disk has the `BADAPPLE` launcher, type `BADAPPLE` from the DOS prompt. Press Esc to exit the player.

The player accepts 128×80 monochrome clips and doubles the pixels on both axes. Sound Blaster playback supports 20 kHz mono soundtracks and earlier 8 kHz clips.

### Doom

On disks with the Luau XT Doom launchers, run `DOOMFAST` for a smaller low-detail view with two digital sound channels, or `DOOMFAST -NOSOUND` to disable sound. `DOOMTINY -NOSOUND` uses a 96×48 viewport. On disks with FastDoom, run `FASTDOOM`. Arrow keys move and turn, Ctrl fires, and Space opens doors. Press F10 and then Y to quit.

From `C:\DOOM`, run `DOOM -NOMUSIC -NOMOUSE -WARP 1 1` to launch with your regular Doom configuration. Startup can take time while the DOS extender initializes and the game reads the WAD.

### Guest audio

The PC speaker works through PIT channel 2 and port 61h. The 386 profiles also provide Sound Blaster 2.0-compatible 8-bit mono playback at port 220h, IRQ 5, DMA 1. The VGA disk sets `BLASTER=A220 I5 D1 T3` and gives a fresh Doom install these settings for digital sound effects. For an existing Doom configuration, set the sound effects device to **Sound Blaster**, with those port, IRQ, and DMA values. Use `-NOMUSIC` for Doom's digital effects. [Creative Sound Blaster hardware guide](https://pdos.csail.mit.edu/6.1810/2017/readings/hardware/SoundBlaster.pdf)

In a Rojo-synced **Studio** Play session, run `BEEP` from the **FreeDOS** prompt for a short tone. In the Client explorer, `PlayerGui.LuauXT` shows `AudioStatus`. `Studio PCM` means Roblox is consuming PCM samples. `PC speaker only` uses a built-in Roblox tone to approximate the PC speaker, and `AudioDetail` shows why the PCM path is unavailable. Set `AudioVolume` between 0 and 1 to adjust or mute either path. `AudioUnderruns` counts times the guest sample queue emptied and had to refill during PCM playback. `AudioWriterUnderruns` counts times the Roblox output buffer was found empty during playback. The player adjusts its output reserve to cushion uneven Roblox frames and measures guest speed against elapsed time so tempo can adjust while preserving pitch.

Bad Apple and Doom's digital sounds require `AudioStreamWriter`. Roblox restricts it to Studio outside Team Create, and its availability depends on the Studio build and feature rollout. [Roblox audio output reference](https://create.roblox.com/docs/reference/engine/classes/AudioStreamWriter) · [Roblox engine team rollout notes](https://devforum.roblox.com/t/release-notes-for-747/4985911?page=3)

Run `luau --codegen tests/audio.luau` to check the speaker, DMA playback, and Sound Blaster interrupts.

## Windows 3.1 Standard Mode

The Windows profile presents a Microsoft serial mouse on COM1 (03F8h, IRQ4). Move or click over the guest display. Apps can use a serial driver such as CuteMouse with `CTMOUSE /S1`. [CuteMouse manual](https://github.com/FDOS/mouse/blob/master/ctmouse.txt)

Import a compatible raw disk image with DOS and Windows 3.1 already installed. After sync, choose the imported profile and power on. If the disk starts at a DOS prompt, run `WIN /S`. The profile uses the startup settings already on the disk.

To configure waveform audio, open **Control Panel → Drivers → Add**, choose **Creative Labs Sound Blaster 1.5**, and use I/O port **220**, **IRQ 5**, and **DMA 1**. If prompted for the driver disk, enter `C:\SETUP` or point to Windows 3.1 Disk 3. Restart Windows and open `C:\WINDOWS\CHIMES.WAV` in Media Player. Waveform audio uses the emulator's shared Sound Blaster PCM output. [Microsoft driver selection](https://jeffpar.github.io/kbarchive/kb/082/Q82583/) · [Microsoft SYSTEM.INI settings](https://mskb.pkisolutions.com/kb/84752)

## Measure performance in Studio

The CPU starts with a 4 ms budget per frame and adjusts it within 2–12 ms when the guest falls behind. Indexed VGA mode can use up to 16 ms on slower frames. The scheduler uses recent frame intervals to share time with Roblox, accounts for recent display and audio costs, and limits catch-up to 100 ms of guest time.

In a Play session, switch Studio to **Client** and inspect `PlayerGui.LuauXT.Performance`. Set `AdaptiveCpu` to false for a fixed 4 ms comparison. Use the same profile and workload for both runs. The attributes update every two seconds.

- `DiskLoadMs` measures the **Loading…** stage through machine creation. `FirstVgaMs` measures time from machine creation to the first VGA upload.
- `GuestClockPercent`, `RobloxFrameP95Ms`, `CpuP95Ms`, and `VgaP95Ms` show guest pace and frame costs. `PresentedVgaFps` counts frames with new guest pixels uploaded.
- `VgaConvertP95Ms`, `VgaUploadP95Ms`, and `VgaUploadP95KiB` report CPU conversion time, time to pack and submit the pixel buffers, and bytes submitted per frame. These are measured on presented frames in the latest active window.
- `MouseToUploadP95Ms` measures from Roblox sampling movement to the next VGA upload after the guest reads the last byte of its mouse packet. Use small movements on an idle Windows desktop so the next upload corresponds to the cursor. The last window with mouse samples stays visible after you stop moving.

For a Windows boot comparison, mark the moment Program Manager is visible in the **Client** command bar:

```lua
game.Players.LocalPlayer.PlayerGui.LuauXT.Performance.Mark:Fire("Windows desktop")
```

For Doom, enter the command from the DOS prompt in **FreeDOS** and mark the first playable frame. The client recognizes `DOOM`, `DOOM.EXE`, `DOOMFAST`, `DOOMTINY`, and `FASTDOOM` on the prompt when you press Enter. For a batch file or another launcher, use `Mark:Fire("Doom command")` just before launching.

```lua
game.Players.LocalPlayer.PlayerGui.LuauXT.Performance.Mark:Fire("Doom playable")
```

The results appear as `WindowsDesktopMs` and `DoomFirstPlayableMs`. For a VGA comparison, move the cursor on the idle Windows desktop, then move or repaint a window. In Doom, use `DOOM -NOSOUND -NOMUSIC -NOMOUSE -WARP 1 1` from the `DOOM` directory and repeat the same movement through E1M1. Compare `RobloxFrameP95Ms`, `GuestClockPercent`, `PresentedVgaFps`, and the three VGA conversion/upload attributes after each workload. The desktop targets are a Roblox 95th-percentile frame time of 20 ms, a Windows guest clock of at least 90%, and at least 20% more presented Doom frames when its guest clock was below real time in the fixed-budget run.

## Verify from the command line

```sh
python3 tests/media_import.py
luau --codegen tests/ide-drives.luau
luau --codegen tests/smoke.luau
```

The importer tests use `mtools` and temporary images. The Luau tests above use synthetic disks or run without media.

```sh
luau --codegen tests/seabios.luau -a dos
luau --codegen tests/seabios.luau -a grub
luau --codegen tests/seabios.luau -a reboot
```

These SeaBIOS cases use the existing `vga_disk`, `grub_disk`, and `full_disk` fixtures, respectively, plus the legacy firmware and font modules under `src/media/`. The older 8088 and GLaBIOS tests also require their original generated fixtures.
