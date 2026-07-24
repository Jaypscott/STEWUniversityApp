"""Generate the two-octave iOS piano sample set from the web app recordings."""

import math
import os
import subprocess
from pathlib import Path

import imageio_ffmpeg


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "frontend/assets/piano/package/audio"
OUTPUT = ROOT / "ios/STEWUniversity/Resources/Piano"
OUTPUT.mkdir(parents=True, exist_ok=True)

NOTE_INDEX = {name: index for index, name in enumerate(
    ["C", "Cs", "D", "Ds", "E", "F", "Fs", "G", "Gs", "A", "As", "B"]
)}
SOURCES = []
for path in SOURCE.glob("*.ogg"):
    stem = path.stem.replace("v8", "")
    octave = int(stem[-1])
    name = stem[:-1]
    if name in NOTE_INDEX:
        SOURCES.append((12 * (octave + 1) + NOTE_INDEX[name], path))

ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
for midi in range(48, 84):  # C3 through B5
    octave = midi // 12 - 1
    name = list(NOTE_INDEX)[midi % 12]
    source_midi, source_path = min(SOURCES, key=lambda item: abs(item[0] - midi))
    pitch_ratio = math.pow(2, (midi - source_midi) / 12)
    output_path = OUTPUT / f"Piano_{name}{octave}.m4a"
    audio_filter = (
        f"asetrate=44100*{pitch_ratio:.10f},aresample=44100,"
        "atrim=duration=4.0,afade=t=out:st=3.55:d=0.45"
    )
    subprocess.run([
        ffmpeg, "-y", "-loglevel", "error", "-i", str(source_path),
        "-af", audio_filter, "-ac", "1", "-c:a", "aac", "-b:a", "96k",
        str(output_path),
    ], check=True)

print(f"Generated 36 piano samples in {OUTPUT}")
