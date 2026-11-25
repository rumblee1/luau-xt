"""Encode a local video for the DOS VGACLIP player."""
import argparse
from pathlib import Path
import shutil
import struct
import subprocess
from tempfile import NamedTemporaryFile, TemporaryFile

WIDTH, HEIGHT = 128, 80
FRAME_PIXELS = WIDTH * HEIGHT
TICKS_PER_FRAME = 2  # About 9.1 FPS with the default BIOS timer.
PCM_RATE = 20000
PCM_BYTES = 2197  # Mono unsigned samples per video frame in the VCL3 format.
THRESHOLD = bytes([0] * 128 + [1] * 128)


def write_clip(output, frames, pcm=None):
    """Packets store the VGA offset and a 15-bit span length plus its color."""
    output.write(struct.pack("<4sH", b"VCL1" if pcm is None else b"VCL3", TICKS_PER_FRAME))
    previous = bytes(FRAME_PIXELS)
    for frame in frames:
        if len(frame) != FRAME_PIXELS:
            raise ValueError("Incomplete monochrome video frame")
        spans = bytearray()
        for y in range(HEIGHT):
            row = y * WIDTH
            start = 0
            while start < WIDTH:
                offset = row + start
                color = frame[offset]
                if color == previous[offset]:
                    start += 1
                    continue
                end = start + 1
                while end < WIDTH and frame[row + end] == color and previous[row + end] != color:
                    end += 1
                # Double each pixel along both axes, centered in VGA mode 13h.
                video_offset = (20 + 2 * y) * 320 + 32 + 2 * start
                spans.extend(struct.pack("<HH", video_offset, (color << 15) | (end - start)))
                start = end
        output.write(struct.pack("<H", len(spans)))
        output.write(spans)
        if pcm is not None:
            output.write(pcm.read(PCM_BYTES).ljust(PCM_BYTES, b"\x80"))
        previous = frame


def demo_frames():
    for frame in range(36):
        pixels = bytearray(FRAME_PIXELS)
        x = 2 + frame * 3
        for y in range(25, 55):
            start = y * WIDTH + x
            pixels[start:start + 20] = bytes([1]) * 20
        yield bytes(pixels)


def video_frames(path):
    if shutil.which("ffmpeg") is None:
        raise ValueError("Install ffmpeg to convert a video")
    filters = (
        "fps=1193182/131072,"
        "scale=128:96:force_original_aspect_ratio=decrease,"
        "pad=128:96:(ow-iw)/2:(oh-ih)/2,"
        "scale=128:80:flags=area,setsar=1"
    )
    command = ["ffmpeg", "-nostdin", "-v", "error", "-i", path, "-map", "0:v:0", "-vf", filters,
               "-pix_fmt", "gray", "-f", "rawvideo", "-"]
    with subprocess.Popen(command, stdout=subprocess.PIPE) as process:
        with process.stdout:
            while frame := process.stdout.read(FRAME_PIXELS):
                yield frame.translate(THRESHOLD)
        if process.wait():
            raise subprocess.CalledProcessError(process.returncode, command)


def write_video(output, path, with_audio=False):
    if not with_audio:
        write_clip(output, video_frames(path))
        return

    streams = subprocess.check_output([
        "ffprobe", "-v", "error", "-select_streams", "a:0",
        "-show_entries", "stream=index", "-of", "csv=p=0", path,
    ])
    if not streams.strip():
        write_clip(output, video_frames(path))
        return

    with TemporaryFile() as pcm:
        subprocess.run([
            "ffmpeg", "-nostdin", "-v", "error", "-i", path, "-map", "0:a:0",
            "-af", f"aresample={PCM_RATE}:async=1:first_pts=0:dither_method=triangular",
            "-ac", "1", "-ar", str(PCM_RATE), "-f", "u8", "-",
        ], stdout=pcm, check=True)
        pcm.seek(0)
        write_clip(output, video_frames(path), pcm)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("video", type=Path)
    parser.add_argument("clip", type=Path)
    parser.add_argument("--audio", action="store_true", help="Include the first audio track for Sound Blaster playback")
    args = parser.parse_args()
    if args.audio and not shutil.which("ffprobe"):
        parser.error("Install ffprobe to detect the audio track")    # Avoid replacing an existing DOS file if conversion fails.
    with NamedTemporaryFile(dir=args.clip.parent, delete=False) as output:
        try:
            write_video(output, args.video, args.audio)
            output.close()
            Path(output.name).replace(args.clip)
        finally:
            Path(output.name).unlink(missing_ok=True)


if __name__ == "__main__":
    main()
