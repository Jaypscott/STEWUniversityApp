from pydantic import BaseModel


class ChatRequest(BaseModel):
    message: str


class ChatResponse(BaseModel):
    response: str


class ScaleRequest(BaseModel):
    root: str
    scale_type: str = "major"


class ScaleResponse(BaseModel):
    root: str
    scale_type: str
    notes: list[str]


class ChordRequest(BaseModel):
    root: str
    chord_type: str = "major"


class ChordResponse(BaseModel):
    root: str
    chord_type: str
    notes: list[str]


class IntervalRequest(BaseModel):
    note1: str
    note2: str


class IntervalResponse(BaseModel):
    note1: str
    note2: str
    semitones: int
    interval: str


class ProgressionRequest(BaseModel):
    key: str
    scale_type: str = "major"
    style: str = "pop"


class DiatonicChord(BaseModel):
    degree: int
    roman_numeral: str
    root: str
    quality: str
    symbol: str


class ProgressionResponse(BaseModel):
    key: str
    scale_type: str
    style: str
    progression: list[DiatonicChord]