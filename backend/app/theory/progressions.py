from app.theory.scales import generate_scale

TRIAD_QUALITIES_MAJOR = [
    "major", "minor", "minor", "major", "major", "minor", "diminished"
]

TRIAD_QUALITIES_MINOR = [
    "minor", "diminished", "major", "minor", "minor", "major", "major"
]

ROMAN_NUMERALS_MAJOR = [
    "I", "ii", "iii", "IV", "V", "vi", "vii°"
]

ROMAN_NUMERALS_MINOR = [
    "i", "ii°", "III", "iv", "v", "VI", "VII"
]


def build_diatonic_chords(key: str, scale_type: str = "major") -> list[dict]:
    scale = generate_scale(key, scale_type)

    if scale_type == "major":
        qualities = TRIAD_QUALITIES_MAJOR
        numerals = ROMAN_NUMERALS_MAJOR
    elif scale_type in ["minor", "natural_minor"]:
        qualities = TRIAD_QUALITIES_MINOR
        numerals = ROMAN_NUMERALS_MINOR
    else:
        raise ValueError("Only major and natural minor keys are supported for now.")

    chords = []

    for index, note in enumerate(scale):
        quality = qualities[index]

        if quality == "major":
            symbol = note
        elif quality == "minor":
            symbol = f"{note}m"
        elif quality == "diminished":
            symbol = f"{note}dim"
        else:
            symbol = note

        chords.append({
            "degree": index + 1,
            "roman_numeral": numerals[index],
            "root": note,
            "quality": quality,
            "symbol": symbol
        })

    return chords


COMMON_PROGRESSIONS = {
    "pop": [1, 5, 6, 4],
    "classic": [1, 4, 5, 1],
    "jazz": [2, 5, 1],
    "sad": [6, 4, 1, 5],
    "minor_pop": [1, 6, 3, 7],
}


def generate_progression(key: str, scale_type: str = "major", style: str = "pop") -> dict:
    chords = build_diatonic_chords(key, scale_type)

    style = style.strip().lower()

    if style not in COMMON_PROGRESSIONS:
        raise ValueError(f"Invalid progression style: {style}")

    degrees = COMMON_PROGRESSIONS[style]

    progression = []

    for degree in degrees:
        chord = chords[degree - 1]
        progression.append(chord)

    return {
        "key": key,
        "scale_type": scale_type,
        "style": style,
        "progression": progression
    }