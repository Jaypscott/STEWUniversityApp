NOTE_TO_SEMITONE = {
    "C": 0,
    "C#": 1, "Db": 1,
    "D": 2,
    "D#": 3, "Eb": 3,
    "E": 4,
    "F": 5,
    "F#": 6, "Gb": 6,
    "G": 7,
    "G#": 8, "Ab": 8,
    "A": 9,
    "A#": 10, "Bb": 10,
    "B": 11,
}

MAJOR_KEY_SPELLINGS = {
    "C":  ["C", "D", "E", "F", "G", "A", "B"],
    "G":  ["G", "A", "B", "C", "D", "E", "F#"],
    "D":  ["D", "E", "F#", "G", "A", "B", "C#"],
    "A":  ["A", "B", "C#", "D", "E", "F#", "G#"],
    "E":  ["E", "F#", "G#", "A", "B", "C#", "D#"],
    "B":  ["B", "C#", "D#", "E", "F#", "G#", "A#"],
    "F#": ["F#", "G#", "A#", "B", "C#", "D#", "E#"],

    "F":  ["F", "G", "A", "Bb", "C", "D", "E"],
    "Bb": ["Bb", "C", "D", "Eb", "F", "G", "A"],
    "Eb": ["Eb", "F", "G", "Ab", "Bb", "C", "D"],
    "Ab": ["Ab", "Bb", "C", "Db", "Eb", "F", "G"],
    "Db": ["Db", "Eb", "F", "Gb", "Ab", "Bb", "C"],
    "Gb": ["Gb", "Ab", "Bb", "Cb", "Db", "Eb", "F"],
}

MINOR_KEY_SPELLINGS = {
    "A":  ["A", "B", "C", "D", "E", "F", "G"],
    "E":  ["E", "F#", "G", "A", "B", "C", "D"],
    "B":  ["B", "C#", "D", "E", "F#", "G", "A"],
    "F#": ["F#", "G#", "A", "B", "C#", "D", "E"],
    "C#": ["C#", "D#", "E", "F#", "G#", "A", "B"],
    "G#": ["G#", "A#", "B", "C#", "D#", "E", "F#"],

    "D":  ["D", "E", "F", "G", "A", "Bb", "C"],
    "G":  ["G", "A", "Bb", "C", "D", "Eb", "F"],
    "C":  ["C", "D", "Eb", "F", "G", "Ab", "Bb"],
    "F":  ["F", "G", "Ab", "Bb", "C", "Db", "Eb"],
    "Bb": ["Bb", "C", "Db", "Eb", "F", "Gb", "Ab"],
    "Eb": ["Eb", "F", "Gb", "Ab", "Bb", "Cb", "Db"],
}

SCALE_PATTERNS = {
    "major": [2, 2, 1, 2, 2, 2, 1],
    "minor": [2, 1, 2, 2, 1, 2, 2],
    "natural_minor": [2, 1, 2, 2, 1, 2, 2],
    "harmonic_minor": [2, 1, 2, 2, 1, 3, 1],
    "melodic_minor": [2, 1, 2, 2, 2, 2, 1],
}


def normalize_note(note: str) -> str:
    note = note.strip()

    if not note:
        raise ValueError("Root note cannot be empty.")

    letter = note[0].upper()
    accidental = note[1:]

    return letter + accidental


def generate_scale(root: str, scale_type: str = "major") -> list[str]:
    root = normalize_note(root)
    scale_type = scale_type.strip().lower()

    if root not in NOTE_TO_SEMITONE:
        raise ValueError(f"Invalid root note: {root}")

    if scale_type not in SCALE_PATTERNS:
        raise ValueError(f"Invalid scale type: {scale_type}")

    if scale_type == "major" and root in MAJOR_KEY_SPELLINGS:
        return MAJOR_KEY_SPELLINGS[root]

    if scale_type in ["minor", "natural_minor"] and root in MINOR_KEY_SPELLINGS:
        return MINOR_KEY_SPELLINGS[root]

    # Fallback for harmonic/melodic minor or unsupported spellings
    base_scale = MINOR_KEY_SPELLINGS.get(root)

    if scale_type == "harmonic_minor" and base_scale:
        scale = base_scale.copy()
        seventh = scale[6]
        scale[6] = raise_note(seventh)
        return scale

    if scale_type == "melodic_minor" and base_scale:
        scale = base_scale.copy()
        scale[5] = raise_note(scale[5])
        scale[6] = raise_note(scale[6])
        return scale

    raise ValueError(f"Proper spelling for {root} {scale_type} is not supported yet.")


def raise_note(note: str) -> str:
    if note.endswith("b"):
        return note.replace("b", "")
    if note.endswith("#"):
        return note + "#"
    return note + "#"