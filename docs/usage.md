# Usage

See the [quick start](../README.md#quick-start) to set up the starter profiles.

## Hardware and timing

| Component | Luau XT profile |
| --- | --- |
| CPU | Intel 8088, 16-bit real mode, 8-bit external data bus, nominal 4.77 MHz |
| Memory | 640 KiB conventional RAM in a 1 MiB physical address space |
| Board | PC/XT-compatible 8259 PIC, 8253 PIT, 8237 DMA, and XT keyboard interface |
| Firmware | GLaBIOS 0.4.2 XT/8088, plus the Luau XT hard-disk option ROM |
| Video | CGA 80×25 color text, rasterized into a 640×200 framebuffer |
| Storage | Writable 360 KiB FAT12 floppy on A: and optional writable 20 MiB FAT16 hard disk on C: |
| Input | XT keyboard scan codes and keyboard navigation in DOS applications |

The original XT crystal sets the nominal **4.77 MHz CPU** and **1.193 MHz PIT** rates. Roblox paces guest time from the PIT rate and adjusts the CPU budget per frame. Instruction timing is estimated and slower clients can fall behind real time. [IBM PC/XT Technical Reference](https://minuszerodegrees.net/manuals/IBM/IBM_5160_Technical_Reference_APR83.pdf)

In FreeDOS EDIT, tap **Alt** and use the arrow keys and **Enter**, or press **Alt+F** to open File. Luau XT currently routes keyboard input to DOS. `DIR /S` searches subdirectories and lists matching files. The current CGA text display shows their filenames. [FreeDOS EDIT guide](https://www.freedos.org/books/get-started/11-using-edit/)

## Full FreeDOS Floppy Edition

To prepare the complete classic-PC bundle, also install dosfstools and run:

```sh
python3 tools/install_freedos.py
```

Sync with Rojo and click **Power on** in a new Play session. With the generated media present, GLaBIOS loads the XT disk option ROM and boots the installed FreeDOS kernel from a 20 MiB FAT16 hard disk. At `C:\>`, try `VER`, `MEM`, or `DIR FDOS\BIN`. The bundled commands are on the PATH at `C:\FDOS\BIN`. The original test floppy remains mounted as `A:`.

The disk contains all 1,411 files from the official 720 KiB Floppy Edition data disks. Where the 8088 and 386 package variants use the same filename, the 8088 version is in the normal program directory and the 386 variant is in `C:\FD386`. Guest disk changes survive **Restart** during the current Play session.

The Floppy Edition is the classic-PC package set. Tools that require a 286 or 386, extended memory, EGA/VGA, or peripheral hardware need a matching machine. OpenGEM is supplied separately on the FreeDOS Bonus CD.

Run `luau tests/full-freedos.luau` to verify the generated hard disk and run bundled tools headlessly.

## Luau 386

Generate the 386 BIOS extension and FreeDOS diagnostics along with the existing media.

```sh
python3 tools/prepare_media.py
python3 tools/install_freedos.py
python3 tools/prepare_grub.py
```

In Studio, the button beside **Power on** cycles through the profiles with boot media available. Restarting the same profile preserves its disks. Starting a different profile opens a new session from that profile's boot image.

- **386 FreeDOS** boots the DOS disk. Run `CPU386` to check 32-bit arithmetic and addressing and return to DOS. Run `PM386` to check protected mode, paging, and a user-mode interrupt round trip. The latter writes its result to the screen and halts. Click **Restart** to return to DOS.
- **386 GRUB** boots GRUB Legacy 0.97. Press Enter on the first menu entry to run a standalone Multiboot program loaded above 1 MiB.
- The 386 profile targets a nominal 16 MHz and has 640 KiB of conventional RAM and 15 MiB of extended RAM. The same GLaBIOS image probes the CPU on both profiles. POST reads extended memory from the emulated CMOS and gets disk geometry from the controller. The BIOS extension provides the extended memory map and A20 services.

```sh
luau tests/386.luau
luau tests/386.luau -a grub
luau tests/386.luau -a post
```

With `debugfs` from e2fsprogs installed, build the **386 Linux** profile:

```sh
python3 tools/prepare_grub.py --freesco
```

It uses the FREESCO 0.4.5 software-math build of Linux 2.0.40 and its initial RAM disk. Choose **386 Linux** in Studio and press Enter on the Linux entry in GRUB. Once the ash prompt appears, try `uname -a`, `ls /`, or `pwd`. The disk exposes the bundled BusyBox commands through `/bin` and includes GNU nano 0.9.23 from Debian. Open a file with `nano /tmp/notes.txt`, save with Ctrl+O and Enter, and exit with Ctrl+X. The initial RAM disk is stored as raw ext2 to reduce boot time. [FREESCO release and kernel sources](https://freesco.sourceforge.net/) · [Debian nano package and source](https://archive.debian.org/debian/pool/main/n/nano/)

Run `luau --codegen tests/386.luau -a linux` to verify Linux boot, the shell utilities, and a nano edit and save.

To try a different i386 Linux kernel and RAM disk, use `--kernel` and `--initrd` with `--output src/media/linux_disk`.

## 386 VGA

Generate the starter media, sync with Rojo, and select **386 VGA** in Studio. The profile boots its FreeDOS floppy at `A:\>` or boots the optional VGA hard disk at `C:\>`. Run either command at the DOS prompt.

```dos
BMPVIEW SAMPLE.BMP
VGACLIP DEMO.VCL
```

`BMPVIEW` accepts uncompressed, indexed 8-bit BMPs up to 320×200. Press any key to close it. `VGACLIP` plays silent monochrome video at up to 9.1 frames per emulated second. Press Esc to return to DOS. Both run on the guest CPU and draw through VGA memory. The Roblox display uses EditableImage.

### VGA library

In **386 VGA**, type `VGA` at `C:\>` to list the installed games, tools, and pictures.

| Command | Controls |
| --- | --- |
| `GAMES\ORBIT` | Arrow keys steer, and Space brakes. Collect eight yellow beacons and avoid the red sweeper. |
| `GAMES\SIGNAL` | Arrow keys move between tiles. Space or Enter reveals a tile. Find eight matching pairs. |
| `APPS\PIXEL` | Arrow keys move. Keys 0–8 select a color, and Space paints. S saves a new `SKETCH.BMP` in the current directory. The status light is green on success and red on failure, including when a sketch already exists. Open it with `BMPVIEW SKETCH.BMP`. |
| `APPS\PALETTE` | Arrow keys browse 256 color swatches. Enter prints the selected palette index and returns to DOS. |
| `BMPVIEW PICS\SUNSET.BMP` | View a mountain sunset. |
| `BMPVIEW PICS\NEBULA.BMP` | View a ringed planet. |

Press Esc to exit games and tools. Any key closes a picture. Guest writes such as `SKETCH.BMP` last for the current Play session, including restarts within that session.

Run `python3 tools/prepare_vga_disk.py` to create a VGA hard disk with the library. Use `--update` to refresh an existing disk. Run `luau --codegen tests/vga-library.luau` to check the guest programs and picture files.

### Play a local video

If Bad Apple is installed, type `BADAPPLE` at `C:\>` in **386 VGA**. The video player uses the emulated Sound Blaster to play the soundtrack and pace the frames. Press Esc to return to DOS. To install your own copy, pass the source video to the disk builder.

```sh
python3 tools/prepare_vga_disk.py --update --bad-apple BadApple.mov
```

For other local videos, convert a file such as an FFmpeg-readable `.mov`, `.mp4`, `.webm`, or `.mkv` and install it as `VIDEO.VCL`. The converter resizes the picture and creates a `.VCL`. Add `--audio` to the converter command to include the first audio track when available.

```sh
python3 tools/vga_clip.py input.mp4 VIDEO.VCL
python3 tools/prepare_vga_disk.py --update --clip VIDEO.VCL
```

After syncing and starting a new Play session, select **386 VGA** and run `VGACLIP VIDEO.VCL` from `C:\>`. For a fresh hard disk, use the same build command without `--update`. The converter encodes 128×80 monochrome frames as changed spans. The guest doubles the pixels on both axes. New soundtracks use 20 kHz mono through two DMA buffers. The player also accepts the earlier 8 kHz clips. The hard disk holds 20 MiB. [FFmpeg filters](https://ffmpeg.org/ffmpeg-filters.html)

### Doom 1.9 shareware

Build the optional VGA hard disk from the original archive with dosfstools installed. You can combine `--doom-shareware` and `--clip` to put both on one disk. The importer verifies the archive by SHA-256 and extracts the original game files. [Doom 1.9 shareware archive](https://ftp.fu-berlin.de/pc/games/idgames/idstuff/doom/doom19s.zip)

```sh
python3 tools/prepare_vga_disk.py --doom-shareware doom19s.zip
```

Sync the disk with Rojo and boot **386 VGA**. Run `DOOMFAST` from `C:\>` for a smaller low-detail view with two digital sound channels. Startup takes time because the guest initializes the DOS extender and reads the WAD before it switches to VGA. `DOOMFAST -NOSOUND` also disables digital sound. Run `DOOM -NOMUSIC -NOMOUSE -WARP 1 1` from `C:\DOOM>` to use your regular Doom configuration. [id Software's Doom renderer](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/r_main.c)

For the smallest in-game view, run `DOOMTINY -NOSOUND` from `C:\>`. It uses Doom’s 96×48 viewport with low detail. You can increase the view with `+` if the game has enough headroom.

On disks with FastDoom 1.3.0, run `FASTDOOM` from `C:\>` for the faster DOS port. The launcher uses a small viewport, quarter-width detail, flat floors and ceilings, and disables sound. It uses the installed shareware WAD. To add it to an existing VGA disk, pass the official zip to the builder. [FastDoom release](https://github.com/viti95/FastDoom/releases/tag/1.3.0) · [Source for the bundled version](https://github.com/viti95/FastDoom/tree/1.3.0)

```sh
python3 tools/prepare_vga_disk.py --update --fastdoom FastDoom_1.3.0.zip
```

Arrow keys move and turn, Ctrl fires, and Space opens doors. Press F10 and then Y to quit. Run `luau --codegen tests/doom.luau` on the prepared disk to check the graphics and quit path.

### Guest audio

The PC speaker works through PIT channel 2 and port 61h. The 386 profiles also provide Sound Blaster 2.0-compatible 8-bit mono playback at port 220h, IRQ 5, DMA 1. The VGA disk sets `BLASTER=A220 I5 D1 T3` and gives a fresh Doom install these settings for digital sound effects. For an existing Doom configuration, set the sound effects device to **Sound Blaster**, with those port, IRQ, and DMA values. Use `-NOMUSIC` for Doom's digital effects. [Creative Sound Blaster hardware guide](https://pdos.csail.mit.edu/6.1810/2017/readings/hardware/SoundBlaster.pdf)

In a Rojo-synced **Studio** Play session, run `BEEP` from the **386 VGA** prompt for a short tone. In the Client explorer, `PlayerGui.LuauXT` shows `AudioStatus`. `Studio PCM` means Roblox is consuming PCM samples. `PC speaker only` uses a built-in Roblox tone to approximate the PC speaker, and `AudioDetail` shows why the PCM path is unavailable. Set `AudioVolume` between 0 and 1 to adjust or mute either path. `AudioUnderruns` counts times the guest sample queue emptied and had to refill during PCM playback. `AudioWriterUnderruns` counts times the Roblox output buffer was found empty during playback. The player adjusts its output reserve to cushion uneven Roblox frames and measures guest speed against elapsed time so tempo can adjust while preserving pitch.

Bad Apple and Doom's digital sounds require `AudioStreamWriter`. Roblox restricts it to Studio outside Team Create, and its availability depends on the Studio build and feature rollout. [Roblox audio output reference](https://create.roblox.com/docs/reference/engine/classes/AudioStreamWriter) · [Roblox engine team rollout notes](https://devforum.roblox.com/t/release-notes-for-747/4985911?page=3)

Run `luau --codegen tests/audio.luau` to check the speaker, DMA playback, and Sound Blaster interrupts.

### Windows 3.0 real-mode target

In Studio, use the MicroProfiler scopes `Luau XT CPU`, `Luau XT VGA Convert`, and `Luau XT VGA Upload` to see the cost of each stage. On the Windows desktop, the renderer tracks changed pixel groups and sends tightly cropped rectangles. Palette changes and Doom's display page flips refresh the frame, using a contiguous conversion when the VGA stride matches the visible width.

The VGA device implements 640×480 16-color mode 12h with planar reads and writes. The profile presents a Microsoft serial mouse on COM1 (03F8h, IRQ4). Apps can use a native serial driver such as CuteMouse with `CTMOUSE /S1`. In Studio, move or click over the guest display. [IBM VGA technical reference](https://bitsavers.trailing-edge.com/pdf/ibm/pc/cards/IBM_VGA_XGA_Technical_Reference_Manual_May92.pdf) · [CuteMouse manual](https://github.com/FDOS/mouse/blob/master/ctmouse.txt)

With the installed disk loaded, **386 Windows 3.0** boots FreeDOS and runs `C:\WINDOWS\WIN.COM /R` from `AUTOEXEC.BAT`. Each new Play session starts from the generated Windows disk modules. Keep the source disk image in `.boot_media/` if you want to rebuild them. The image uses a minimal FreeDOS startup for Windows real mode. Use **Restart** to retain guest writes within the same Play session.

To prepare the Windows installer, supply a local Windows 3.0 five-floppy 7z archive. The builder needs 7-Zip, mtools, and dosfstools. It places the installer under `C:\SETUP` on a separate FreeDOS disk. The **386 Windows 3.0** profile appears after Rojo sync.

```sh
python3 tools/prepare_vga_disk.py --windows-setup Windows3.0.7z
```

For an installer disk, boot the Windows profile and run `C:\SETUP\SETUP.EXE`. Let Setup use the VGA display setting. Import an installed disk directly from its raw image. Use 16 heads, 32 sectors per track, and 1–127 whole 256 KiB cylinders. An 80-cylinder image is 20 MiB.

```sh
python3 tools/prepare_vga_disk.py --windows-profile --disk-image .boot_media/windows30.img
```

The Windows acceptance test is to start with `WIN /R`, open an application in Program Manager, use the mouse, and exit to DOS. The graphics and serial mouse hardware can be checked with `luau --codegen tests/vga.luau`. [Microsoft Windows 3.0 modes](https://www.betaarchive.com/wiki/index.php/Microsoft_KB_Archive/58317)

## Measure performance in Studio

The CPU starts with a 4 ms budget per frame and adjusts it within 2–12 ms when the guest falls behind. Indexed VGA mode can use up to 16 ms on slower frames. The scheduler uses recent frame intervals to share time with Roblox, accounts for recent display and audio costs, and limits catch-up to 100 ms of guest time.

In a Play session, switch Studio to **Client** and inspect `PlayerGui.LuauXT.Performance`. Set `AdaptiveCpu` to false for a fixed 4 ms comparison. Use the same profile and workload for both runs. The attributes update every two seconds.

- `DiskLoadMs` measures the **Loading disk** stage through machine creation. `FirstVgaMs` measures time from machine creation to the first VGA upload.
- `GuestClockPercent`, `RobloxFrameP95Ms`, `CpuP95Ms`, and `VgaP95Ms` show guest pace and frame costs. `PresentedVgaFps` counts frames with new guest pixels uploaded.
- `VgaConvertP95Ms`, `VgaUploadP95Ms`, and `VgaUploadP95KiB` report CPU conversion time, time to pack and submit the pixel buffers, and bytes submitted per frame. These are measured on presented frames in the latest active window.
- `MouseToUploadP95Ms` measures from Roblox sampling movement to the next VGA upload after the guest reads the last byte of its mouse packet. Use small movements on an idle Windows desktop so the next upload corresponds to the cursor. The last window with mouse samples stays visible after you stop moving.

For a Windows boot comparison, mark the moment Program Manager is visible in the **Client** command bar:

```lua
game.Players.LocalPlayer.PlayerGui.LuauXT.Performance.Mark:Fire("Windows desktop")
```

For Doom, enter the command from the DOS prompt in **386 VGA** and mark the first playable frame. The client recognizes `DOOM`, `DOOM.EXE`, `DOOMFAST`, `DOOMTINY`, and `FASTDOOM` on the prompt when you press Enter. For a batch file or another launcher, use `Mark:Fire("Doom command")` just before launching.

```lua
game.Players.LocalPlayer.PlayerGui.LuauXT.Performance.Mark:Fire("Doom playable")
```

The results appear as `WindowsDesktopMs` and `DoomFirstPlayableMs`. For a VGA comparison, move the cursor on the idle Windows desktop, then move or repaint a window. In Doom, use `DOOM -NOSOUND -NOMUSIC -NOMOUSE -WARP 1 1` from the `DOOM` directory and repeat the same movement through E1M1. Compare `RobloxFrameP95Ms`, `GuestClockPercent`, `PresentedVgaFps`, and the three VGA conversion/upload attributes after each workload. The desktop targets are a Roblox 95th-percentile frame time of 20 ms, a Windows guest clock of at least 90%, and at least 20% more presented Doom frames when its guest clock was below real time in the fixed-budget run.

## Verify from the command line

```sh
luau tests/smoke.luau
luau tests/boot.luau
luau tests/performance.luau
```

The first test runs the original reset-vector diagnostic. The second boots both a test sector and FreeDOS through the real BIOS, checks keyboard input and CGA framebuffer updates, and verifies that FreeDOS can copy and run a file on the floppy.

The emulator targets the boot and text-mode features needed by this PC/XT configuration. Device timing is approximate. Floppy changes live in memory for the duration of the Roblox session.

## Boot media sources

`tools/prepare_media.py` checks the upstream downloads against pinned SHA-256 digests. It repacks the FreeDOS boot sector, kernel, and FreeCOM onto the 360 KiB image and assembles the original guest programs in `guest/`. Generated media and the download cache are ignored by Git.

- GLaBIOS v0.4.2 XT 5160 / 8088 ROM, GPLv3. [ROM release](https://github.com/640-KB/GLaBIOS/releases/tag/v0.4.2) · [Source](https://github.com/640-KB/GLaBIOS/tree/v0.4.2)
- FreeDOS 1.4 Floppy Edition. [Distribution](https://www.freedos.org/download/) · [Kernel source](https://github.com/FDOS/kernel) · [FreeCOM source](https://github.com/FDOS/freecom)
- Linux v6.12 8×8 console font, GPL-2.0. [Font source](https://github.com/torvalds/linux/blob/v6.12/lib/fonts/font_8x8.c)

The full-install builder reads the release's File Slicer archives. [File Slicer source](https://gitlab.com/DOSx86/slicer)
