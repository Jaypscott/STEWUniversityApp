"""Generate iOS guitar and bass samples from the web app recordings."""

import math
import subprocess
from pathlib import Path

import imageio_ffmpeg


ROOT = Path(__file__).resolve().parents[2]
NOTE_NAMES = ["C", "Cs", "D", "Ds", "E", "F", "Fs", "G", "Gs", "A", "As", "B"]
NOTE_INDEX = {name: index for index, name in enumerate(NOTE_NAMES)}
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()


def source_samples(folder: Path):
    samples = []
    for path in folder.glob("*.ogg"):
        stem = path.stem
        octave = int(stem[-1])
        name = stem[:-1]
        if name in NOTE_INDEX:
            samples.append((12 * (octave + 1) + NOTE_INDEX[name], path))
    return samples


def generate(instrument: str, source_folder: Path, midi_range: range):
    samples = source_samples(source_folder)
    output = ROOT / f"ios/STEWUniversity/Resources/{instrument}"
    output.mkdir(parents=True, exist_ok=True)
    for midi in midi_range:
        source_midi, source_path = min(samples, key=lambda item: abs(item[0] - midi))
        pitch_ratio = math.pow(2, (midi - source_midi) / 12)
        target = output / f"{instrument}_{midi}.m4a"
        audio_filter = (
            f"asetrate=44100*{pitch_ratio:.10f},aresample=44100,"
            "atrim=duration=3.6,afade=t=out:st=3.15:d=0.45"
        )
        subprocess.run([
            FFMPEG, "-y", "-loglevel", "error", "-i", str(source_path),
            "-af", audio_filter, "-ac", "1", "-c:a", "aac", "-b:a", "96k", str(target),
        ], check=True)
    print(f"Generated {len(midi_range)} {instrument.lower()} samples")


generate("Guitar", ROOT / "frontend/assets/guitar/package", range(40, 77))
generate("Bass", ROOT / "frontend/assets/bass/package", range(28, 56))
