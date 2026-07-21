from __future__ import annotations

from datetime import date, datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


class EarAnsweredPayload(BaseModel):
    skill_id: str = Field(min_length=1, max_length=64)
    mode: Literal["interval", "chord", "note"]
    correct: bool


class SudokuCompletedPayload(BaseModel):
    puzzle_id: str = Field(min_length=1, max_length=128)
    mode: Literal["daily", "practice"]
    difficulty: Literal["easy", "medium", "hard"]
    day_key: date | None = None
    elapsed_seconds: int = Field(ge=0, le=86400)
    mistakes: int = Field(default=0, ge=0, le=1000)
    hints_used: int = Field(default=0, ge=0, le=1000)


class MelodyCompletedPayload(BaseModel):
    difficulty: Literal["easy", "medium", "hard"]
    score: int = Field(ge=0, le=10_000_000)
    completed_rounds: int = Field(ge=0, le=100_000)
    longest_sequence: int = Field(ge=0, le=100_000)


class EventBase(BaseModel):
    client_event_id: UUID
    installation_id: UUID
    session_id: UUID
    sequence_number: int = Field(ge=1, le=1_000_000_000)
    occurred_at: datetime

    @field_validator("occurred_at")
    @classmethod
    def require_time_zone(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("occurred_at must include a time zone")
        return value


class EarAnsweredEvent(EventBase):
    type: Literal["ear_answered"]
    payload: EarAnsweredPayload


class SudokuCompletedEvent(EventBase):
    type: Literal["sudoku_completed"]
    payload: SudokuCompletedPayload


class MelodyCompletedEvent(EventBase):
    type: Literal["melody_completed"]
    payload: MelodyCompletedPayload


ProgressEventRequest = Annotated[
    EarAnsweredEvent | SudokuCompletedEvent | MelodyCompletedEvent,
    Field(discriminator="type"),
]


class EventBatchRequest(BaseModel):
    events: list[ProgressEventRequest] = Field(min_length=1, max_length=100)

    @model_validator(mode="after")
    def unique_client_ids(self):
        identifiers = [event.client_event_id for event in self.events]
        if len(identifiers) != len(set(identifiers)):
            raise ValueError("client_event_id values must be unique within a batch")
        return self


class ProgressPreferences(BaseModel):
    daily_goal: int
    time_zone: str


class AccountProgress(BaseModel):
    xp: int
    level: int
    level_title: str
    xp_into_level: int
    xp_to_next_level: int | None


class MasteryProgress(BaseModel):
    attempts: int
    correct: int
    score: float


class DailyEarProgress(BaseModel):
    day: date
    answered: int
    correct: int
    xp_earned: int
    best_combo: int
    goal_target: int
    goal_completed: bool
    challenge_kind: str
    challenge_progress: int
    challenge_target: int
    challenge_completed: bool


class EarTrainingProgress(BaseModel):
    current_streak: int
    longest_streak: int
    mastery: dict[str, MasteryProgress]
    achievements: list[str]
    completed_goal_days: list[date]
    today: DailyEarProgress


class SudokuStatistics(BaseModel):
    solved_count: int
    current_daily_streak: int
    longest_daily_streak: int
    last_daily_completion_day: date | None
    completed_daily_days: list[date]
    best_unassisted_seconds: dict[str, int]
    completed_puzzle_ids: list[str]


class MelodyStatistics(BaseModel):
    games_played: int
    high_score: int
    longest_sequence: int
    total_correct_rounds: int
    best_scores: dict[str, int]


class GameStatistics(BaseModel):
    sudoku: SudokuStatistics
    melody: MelodyStatistics


class ProgressSnapshot(BaseModel):
    revision: int
    updated_at: datetime
    import_state: Literal["awaiting_choice", "complete"]
    preferences: ProgressPreferences
    account: AccountProgress
    ear_training: EarTrainingProgress
    games: GameStatistics


class RejectedEvent(BaseModel):
    client_event_id: UUID
    code: str
    message: str


class EventBatchResponse(BaseModel):
    accepted: list[UUID]
    duplicate: list[UUID]
    rejected: list[RejectedEvent]
    snapshot: ProgressSnapshot


class LegacyMastery(BaseModel):
    attempts: int = Field(default=0, ge=0)
    correct: int = Field(default=0, ge=0)
    score: float = Field(default=0, ge=0, le=100)


class LegacyDailyEarProgress(BaseModel):
    day: date
    answered: int = Field(default=0, ge=0)
    correct: int = Field(default=0, ge=0)
    xp_earned: int = Field(default=0, ge=0)
    best_combo: int = Field(default=0, ge=0)
    challenge_kind: Literal[
        "comboThree", "intervalThree", "chordThree", "noteThree", "perfectFive"
    ] | None = None
    challenge_progress: int = Field(default=0, ge=0)
    challenge_completed: bool = False


class LegacyEarTraining(BaseModel):
    total_xp: int = Field(default=0, ge=0)
    current_streak: int = Field(default=0, ge=0)
    longest_streak: int = Field(default=0, ge=0)
    last_goal_completion_day: date | None = None
    daily_goal: Literal[5, 10, 15] = 5
    mastery: dict[str, LegacyMastery] = Field(default_factory=dict)
    achievements: list[str] = Field(default_factory=list, max_length=100)
    today: LegacyDailyEarProgress | None = None
    completed_goal_days: list[date] = Field(default_factory=list, max_length=5000)


class LegacySudoku(BaseModel):
    solved_count: int = Field(default=0, ge=0)
    current_daily_streak: int = Field(default=0, ge=0)
    longest_daily_streak: int = Field(default=0, ge=0)
    last_daily_completion_day: date | None = None
    completed_daily_days: list[date] = Field(default_factory=list, max_length=5000)
    best_unassisted_seconds: dict[str, int] = Field(default_factory=dict)
    completed_puzzle_ids: list[str] = Field(default_factory=list, max_length=5000)


class LegacyMelody(BaseModel):
    games_played: int = Field(default=0, ge=0)
    high_score: int = Field(default=0, ge=0)
    longest_sequence: int = Field(default=0, ge=0)
    total_correct_rounds: int = Field(default=0, ge=0)
    best_scores: dict[str, int] = Field(default_factory=dict)


class LegacyProgress(BaseModel):
    ear_training: LegacyEarTraining = Field(default_factory=LegacyEarTraining)
    sudoku: LegacySudoku = Field(default_factory=LegacySudoku)
    melody: LegacyMelody = Field(default_factory=LegacyMelody)


class ProgressImportRequest(BaseModel):
    strategy: Literal["use_device", "use_account"]
    installation_id: UUID
    time_zone: str = Field(default="UTC", min_length=1, max_length=64)
    legacy: LegacyProgress | None = None

    @model_validator(mode="after")
    def require_legacy_for_device(self):
        if self.strategy == "use_device" and self.legacy is None:
            raise ValueError("legacy is required when strategy is use_device")
        return self


class ProgressImportResponse(BaseModel):
    applied: bool
    snapshot: ProgressSnapshot


class ProgressPreferencesPatch(BaseModel):
    daily_goal: Literal[5, 10, 15] | None = None
    time_zone: str | None = Field(default=None, min_length=1, max_length=64)

    @model_validator(mode="after")
    def at_least_one_value(self):
        if self.daily_goal is None and self.time_zone is None:
            raise ValueError("at least one preference is required")
        return self


class ProgressPreferencesResponse(BaseModel):
    snapshot: ProgressSnapshot


class ProgressFlagResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")
    enabled: bool
