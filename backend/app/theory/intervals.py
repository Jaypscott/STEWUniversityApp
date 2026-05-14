CHROMATIC_SCALE_SHARPS = [
    "C", "C#", "D", "D#", "E", "F",
    "F#", "G", "G#", "A", "A#", "B"
]

INTERVAL_NAMES = {
    0: "Perfect unison",
    1: "Minor second",
    2: "Major second",
    3: "Minor third",
    4: "Major third",
    5: "Perfect fourth",
    6: "Tritone",
    7: "Perfect fifth",
    8: "Minor sixth",
    9: "Major sixth",
    10: "Minor seventh",
    11: "Major seventh",
    12: "Perfect octave",
}


def calculate_interval(note1: str, note2: str) -> dict:
    note1 = note1.strip().capitalize()
    note2 = note2.strip().capitalize()

    if note1 not in CHROMATIC_SCALE_SHARPS:
        raise ValueError(f"Invalid first note: {note1}")

    if note2 not in CHROMATIC_SCALE_SHARPS:
        raise ValueError(f"Invalid second note: {note2}")

    index1 = CHROMATIC_SCALE_SHARPS.index(note1)
    index2 = CHROMATIC_SCALE_SHARPS.index(note2)

    semitones = (index2 - index1) % 12

    interval_name = INTERVAL_NAMES[semitones]

    return {
        "note1": note1,
        "note2": note2,
        "semitones": semitones,
        "interval": interval_name
    }