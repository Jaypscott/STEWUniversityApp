from datetime import datetime
from enum import Enum

from pydantic import BaseModel, Field, field_validator


class ChatMode(str, Enum):
    general = "general"
    songwriting = "songwriting"
    ear_explanation = "ear_explanation"
    theory_chat = "theory_chat"


class ChatHistoryItem(BaseModel):
    role: str
    content: str = Field(min_length=1, max_length=1200)

    @field_validator("role")
    @classmethod
    def validate_role(cls, value: str) -> str:
        normalized = value.strip().lower()
        if normalized not in {"user", "assistant"}:
            raise ValueError("role must be user or assistant")
        return normalized


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=1200)
    mode: ChatMode = ChatMode.general
    history: list[ChatHistoryItem] = Field(default_factory=list, max_length=8)
    installation_id: str | None = Field(default=None, min_length=16, max_length=128)

    @field_validator("message")
    @classmethod
    def message_must_not_be_blank(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("message must not be blank")
        return value


class ChatResponse(BaseModel):
    response: str
    remaining: int | None = None
    limit: int | None = None
    reset_at: datetime | None = None


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
