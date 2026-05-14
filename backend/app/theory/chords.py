from app.theory.scales import NOTE_TO_SEMITONE, normalize_note

SEMITONE_TO_SHARP = {
    0: "C",
    1: "C#",
    2: "D",
    3: "D#",
    4: "E",
    5: "F",
    6: "F#",
    7: "G",
    8: "G#",
    9: "A",
    10: "A#",
    11: "B",
}

SEMITONE_TO_FLAT = {
    0: "C",
    1: "Db",
    2: "D",
    3: "Eb",
    4: "E",
    5: "F",
    6: "Gb",
    7: "G",
    8: "Ab",
    9: "A",
    10: "Bb",
    11: "B",
}

CHORD_PATTERNS = {
    "major": [0, 4, 7],
    "minor": [0, 3, 7],
    "diminished": [0, 3, 6],
    "augmented": [0, 4, 8],
    "major7": [0, 4, 7, 11],
    "minor7": [0, 3, 7, 10],
    "dominant7": [0, 4, 7, 10],
    "dim7": [0, 3, 6, 9],
}


def prefers_flats(root: str) -> bool:
    return "b" in root


def generate_chord(root: str, chord_type: str = "major") -> list[str]:
    root = normalize_note(root)
    chord_type = chord_type.strip().lower()

    if root not in NOTE_TO_SEMITONE:
        raise ValueError(f"Invalid root note: {root}")

    if chord_type not in CHORD_PATTERNS:
        raise ValueError(f"Invalid chord type: {chord_type}")

    root_value = NOTE_TO_SEMITONE[root]
    pattern = CHORD_PATTERNS[chord_type]

    spelling = SEMITONE_TO_FLAT if prefers_flats(root) else SEMITONE_TO_SHARP

    return [
        spelling[(root_value + interval) % 12]
        for interval in pattern
    ]