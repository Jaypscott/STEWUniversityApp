from __future__ import annotations

import uuid
from datetime import date, datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    JSON,
    String,
    UniqueConstraint,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.band.database import Base
from app.band.models import utcnow


class ProgressProfile(Base):
    __tablename__ = "progress_profiles"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    revision: Mapped[int] = mapped_column(BigInteger, default=0)
    import_completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    import_source_installation_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    time_zone: Mapped[str] = mapped_column(String(64), default="UTC")
    daily_goal: Mapped[int] = mapped_column(Integer, default=5)

    total_xp: Mapped[int] = mapped_column(Integer, default=0)
    current_ear_streak: Mapped[int] = mapped_column(Integer, default=0)
    longest_ear_streak: Mapped[int] = mapped_column(Integer, default=0)
    last_goal_completion_day: Mapped[date | None] = mapped_column(Date)
    achievements: Mapped[list[str]] = mapped_column(JSON, default=list)

    legacy_sudoku_solved_count: Mapped[int] = mapped_column(Integer, default=0)
    legacy_sudoku_current_streak: Mapped[int] = mapped_column(Integer, default=0)
    legacy_sudoku_longest_streak: Mapped[int] = mapped_column(Integer, default=0)
    legacy_sudoku_last_daily_day: Mapped[date | None] = mapped_column(Date)
    legacy_sudoku_completed_daily_days: Mapped[list[str]] = mapped_column(JSON, default=list)
    legacy_sudoku_best_unassisted_seconds: Mapped[dict[str, int]] = mapped_column(
        JSON, default=dict
    )

    legacy_melody_games_played: Mapped[int] = mapped_column(Integer, default=0)
    legacy_melody_high_score: Mapped[int] = mapped_column(Integer, default=0)
    legacy_melody_longest_sequence: Mapped[int] = mapped_column(Integer, default=0)
    legacy_melody_total_correct_rounds: Mapped[int] = mapped_column(Integer, default=0)
    legacy_melody_best_scores: Mapped[dict[str, int]] = mapped_column(JSON, default=dict)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )


class ProgressEvent(Base):
    __tablename__ = "progress_events"
    __table_args__ = (
        UniqueConstraint(
            "user_id", "client_event_id", name="uq_progress_events_user_client"
        ),
        Index("ix_progress_events_user_revision", "user_id", "revision"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    client_event_id: Mapped[uuid.UUID] = mapped_column(Uuid)
    installation_id: Mapped[uuid.UUID] = mapped_column(Uuid)
    session_id: Mapped[uuid.UUID] = mapped_column(Uuid)
    sequence_number: Mapped[int] = mapped_column(Integer)
    event_type: Mapped[str] = mapped_column(String(32))
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    payload: Mapped[dict] = mapped_column(JSON)
    revision: Mapped[int] = mapped_column(BigInteger)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class EarSkillProgress(Base):
    __tablename__ = "ear_skill_progress"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    skill_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    correct: Mapped[int] = mapped_column(Integer, default=0)
    mastery_score: Mapped[float] = mapped_column(Float, default=0.0)


class EarWorkoutProgress(Base):
    __tablename__ = "ear_workout_progress"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    session_id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    last_sequence_number: Mapped[int] = mapped_column(Integer, default=0)
    current_combo: Mapped[int] = mapped_column(Integer, default=0)
    best_combo: Mapped[int] = mapped_column(Integer, default=0)
    perfect_run: Mapped[bool] = mapped_column(Boolean, default=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )


class EarDailyProgress(Base):
    __tablename__ = "ear_daily_progress"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    day: Mapped[date] = mapped_column(Date, primary_key=True)
    answered: Mapped[int] = mapped_column(Integer, default=0)
    correct: Mapped[int] = mapped_column(Integer, default=0)
    xp_earned: Mapped[int] = mapped_column(Integer, default=0)
    best_combo: Mapped[int] = mapped_column(Integer, default=0)
    goal_reward_awarded: Mapped[bool] = mapped_column(Boolean, default=False)
    challenge_kind: Mapped[str] = mapped_column(String(32))
    challenge_progress: Mapped[int] = mapped_column(Integer, default=0)
    challenge_completed: Mapped[bool] = mapped_column(Boolean, default=False)


class SudokuCompletion(Base):
    __tablename__ = "sudoku_completions"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    puzzle_id: Mapped[str] = mapped_column(String(128), primary_key=True)
    mode: Mapped[str] = mapped_column(String(16))
    difficulty: Mapped[str] = mapped_column(String(16))
    day: Mapped[date | None] = mapped_column(Date)
    elapsed_seconds: Mapped[int | None] = mapped_column(Integer)
    mistakes: Mapped[int] = mapped_column(Integer, default=0)
    hints_used: Mapped[int] = mapped_column(Integer, default=0)
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    is_legacy: Mapped[bool] = mapped_column(Boolean, default=False)


class MelodyResult(Base):
    __tablename__ = "melody_results"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    session_id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    difficulty: Mapped[str] = mapped_column(String(16))
    score: Mapped[int] = mapped_column(Integer)
    completed_rounds: Mapped[int] = mapped_column(Integer)
    longest_sequence: Mapped[int] = mapped_column(Integer)
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
