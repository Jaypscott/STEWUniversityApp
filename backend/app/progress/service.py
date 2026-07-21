from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.band.models import User, utcnow
from app.progress.models import (
    EarDailyProgress,
    EarSkillProgress,
    EarWorkoutProgress,
    MelodyResult,
    ProgressEvent,
    ProgressProfile,
    SudokuCompletion,
)
from app.progress.schemas import (
    AccountProgress,
    DailyEarProgress,
    EarAnsweredEvent,
    EarTrainingProgress,
    EventBatchRequest,
    EventBatchResponse,
    GameStatistics,
    LegacyProgress,
    MasteryProgress,
    MelodyCompletedEvent,
    MelodyStatistics,
    ProgressImportRequest,
    ProgressPreferences,
    ProgressSnapshot,
    RejectedEvent,
    SudokuCompletedEvent,
    SudokuStatistics,
)


CHALLENGES = ("comboThree", "intervalThree", "chordThree", "noteThree", "perfectFive")
CHALLENGE_TARGETS = {kind: 3 for kind in CHALLENGES}
CHALLENGE_TARGETS["perfectFive"] = 5

SKILLS_BY_MODE = {
    "interval": {
        "interval.minor3",
        "interval.major3",
        "interval.perfect5",
        "interval.octave",
        "interval.major2",
        "interval.perfect4",
        "interval.minor2",
    },
    "chord": {
        "chord.major",
        "chord.minor",
        "chord.diminished",
        "chord.augmented",
    },
    "note": {f"note.{index}" for index in range(12)},
}
ALL_SKILLS = set().union(*SKILLS_BY_MODE.values())

LEVELS = (
    (0, "Curious Listener"),
    (250, "Developing Listener"),
    (600, "Focused Listener"),
    (1_200, "Tuned Listener"),
    (2_200, "Skilled Listener"),
    (3_600, "Golden Ear"),
)


@dataclass(frozen=True)
class BatchResult:
    response: EventBatchResponse
    origin_installation_id: uuid.UUID | None


class EventRejected(Exception):
    def __init__(self, code: str, message: str):
        self.code = code
        self.message = message
        super().__init__(message)


def validate_time_zone(value: str) -> str:
    try:
        ZoneInfo(value)
    except ZoneInfoNotFoundError as exc:
        raise ValueError("time_zone must be a valid IANA time zone") from exc
    return value


def _account_day(moment: datetime, time_zone: str) -> date:
    return moment.astimezone(ZoneInfo(time_zone)).date()


def _challenge_for(day: date) -> str:
    day_key = day.isoformat()
    return CHALLENGES[sum(day_key.encode("utf-8")) % len(CHALLENGES)]


def _level(xp: int) -> AccountProgress:
    index = max(i for i, (threshold, _) in enumerate(LEVELS) if xp >= threshold)
    minimum, title = LEVELS[index]
    next_minimum = LEVELS[index + 1][0] if index + 1 < len(LEVELS) else None
    return AccountProgress(
        xp=xp,
        level=index + 1,
        level_title=title,
        xp_into_level=xp - minimum,
        xp_to_next_level=None if next_minimum is None else next_minimum - xp,
    )


async def locked_profile(session: AsyncSession, user_id: uuid.UUID) -> ProgressProfile:
    profile = await session.scalar(
        select(ProgressProfile)
        .where(ProgressProfile.user_id == user_id)
        .with_for_update()
    )
    if profile is None:
        try:
            async with session.begin_nested():
                profile = ProgressProfile(user_id=user_id)
                session.add(profile)
                await session.flush()
        except IntegrityError:
            profile = await session.scalar(
                select(ProgressProfile)
                .where(ProgressProfile.user_id == user_id)
                .with_for_update()
            )
            if profile is None:  # pragma: no cover - protects against a broken database
                raise
    return profile


async def get_or_create_profile(
    session: AsyncSession, user_id: uuid.UUID
) -> ProgressProfile:
    profile = await session.get(ProgressProfile, user_id)
    if profile is None:
        try:
            async with session.begin_nested():
                profile = ProgressProfile(user_id=user_id)
                session.add(profile)
                await session.flush()
        except IntegrityError:
            profile = await session.get(ProgressProfile, user_id)
            if profile is None:  # pragma: no cover - protects against a broken database
                raise
    return profile


async def _daily_row(
    session: AsyncSession, user_id: uuid.UUID, day: date
) -> EarDailyProgress:
    row = await session.get(EarDailyProgress, (user_id, day))
    if row is None:
        row = EarDailyProgress(
            user_id=user_id,
            day=day,
            answered=0,
            correct=0,
            xp_earned=0,
            best_combo=0,
            goal_reward_awarded=False,
            challenge_kind=_challenge_for(day),
            challenge_progress=0,
            challenge_completed=False,
        )
        session.add(row)
    return row


async def process_events(
    session: AsyncSession, user: User, body: EventBatchRequest
) -> BatchResult:
    profile = await locked_profile(session, user.id)
    if profile.import_completed_at is None:
        snapshot = await build_snapshot(session, profile)
        rejected = [
            RejectedEvent(
                client_event_id=event.client_event_id,
                code="progress_import_required",
                message="Choose device or account progress before syncing activity.",
            )
            for event in body.events
        ]
        return BatchResult(
            EventBatchResponse(
                accepted=[], duplicate=[], rejected=rejected, snapshot=snapshot
            ),
            None,
        )

    identifiers = [event.client_event_id for event in body.events]
    existing = set(
        (
            await session.scalars(
                select(ProgressEvent.client_event_id).where(
                    ProgressEvent.user_id == user.id,
                    ProgressEvent.client_event_id.in_(identifiers),
                )
            )
        ).all()
    )
    accepted: list[uuid.UUID] = []
    duplicate: list[uuid.UUID] = []
    rejected: list[RejectedEvent] = []
    origins: set[uuid.UUID] = set()

    for event in body.events:
        if event.client_event_id in existing:
            duplicate.append(event.client_event_id)
            continue
        try:
            _validate_event_time(event.occurred_at)
            if isinstance(event, EarAnsweredEvent):
                await _apply_ear_answer(session, profile, event)
            elif isinstance(event, SudokuCompletedEvent):
                await _apply_sudoku(session, user.id, event)
            elif isinstance(event, MelodyCompletedEvent):
                await _apply_melody(session, user.id, event)
            else:  # pragma: no cover - Pydantic prevents unknown event types
                raise EventRejected("unsupported_event", "This event type is unsupported.")
        except EventRejected as exc:
            rejected.append(
                RejectedEvent(
                    client_event_id=event.client_event_id,
                    code=exc.code,
                    message=exc.message,
                )
            )
            continue

        profile.revision += 1
        profile.updated_at = utcnow()
        session.add(
            ProgressEvent(
                user_id=user.id,
                client_event_id=event.client_event_id,
                installation_id=event.installation_id,
                session_id=event.session_id,
                sequence_number=event.sequence_number,
                event_type=event.type,
                occurred_at=event.occurred_at,
                payload=event.payload.model_dump(mode="json"),
                revision=profile.revision,
            )
        )
        accepted.append(event.client_event_id)
        origins.add(event.installation_id)

    if accepted:
        await _recompute_ear_streaks(session, profile)
        await _evaluate_achievements(session, profile)
        await session.flush()
    snapshot = await build_snapshot(session, profile)
    origin = next(iter(origins)) if len(origins) == 1 else None
    return BatchResult(
        EventBatchResponse(
            accepted=accepted,
            duplicate=duplicate,
            rejected=rejected,
            snapshot=snapshot,
        ),
        origin,
    )


def _validate_event_time(value: datetime) -> None:
    if value > datetime.now(timezone.utc) + timedelta(minutes=5):
        raise EventRejected("event_in_future", "The event time is too far in the future.")


async def _apply_ear_answer(
    session: AsyncSession, profile: ProgressProfile, event: EarAnsweredEvent
) -> None:
    payload = event.payload
    if payload.skill_id not in SKILLS_BY_MODE[payload.mode]:
        raise EventRejected(
            "invalid_skill", "The skill does not belong to the supplied training mode."
        )
    workout = await session.get(
        EarWorkoutProgress, (profile.user_id, event.session_id)
    )
    if workout is None:
        if event.sequence_number != 1:
            raise EventRejected(
                "invalid_sequence", "A workout session must start at sequence number 1."
            )
        workout = EarWorkoutProgress(
            user_id=profile.user_id,
            session_id=event.session_id,
            last_sequence_number=0,
            current_combo=0,
            best_combo=0,
            perfect_run=True,
        )
        session.add(workout)
    elif event.sequence_number != workout.last_sequence_number + 1:
        raise EventRejected(
            "invalid_sequence", "Workout events must be submitted in sequence."
        )

    if payload.correct:
        workout.current_combo += 1
        workout.best_combo = max(workout.best_combo, workout.current_combo)
    else:
        workout.current_combo = 0
        workout.perfect_run = False
    workout.last_sequence_number = event.sequence_number
    workout.updated_at = utcnow()

    day = _account_day(event.occurred_at, profile.time_zone)
    daily = await _daily_row(session, profile.user_id, day)
    daily.answered += 1
    answer_xp = 0
    if payload.correct:
        daily.correct += 1
        daily.best_combo = max(daily.best_combo, workout.best_combo)
        answer_xp = 10 + min(10, max(0, workout.current_combo - 1) * 2)
        daily.xp_earned += answer_xp
        profile.total_xp += answer_xp

    mastery = await session.get(EarSkillProgress, (profile.user_id, payload.skill_id))
    if mastery is None:
        mastery = EarSkillProgress(
            user_id=profile.user_id,
            skill_id=payload.skill_id,
            attempts=0,
            correct=0,
            mastery_score=0,
        )
        session.add(mastery)
    mastery.attempts += 1
    if payload.correct:
        mastery.correct += 1
        mastery.mastery_score += (100 - mastery.mastery_score) * 0.15
    else:
        mastery.mastery_score *= 0.80
    mastery.mastery_score = min(100, max(0, mastery.mastery_score))

    if not daily.challenge_completed:
        kind = daily.challenge_kind
        if kind == "comboThree":
            daily.challenge_progress = max(
                daily.challenge_progress, min(3, workout.current_combo)
            )
        elif kind == "perfectFive":
            perfect_count = workout.current_combo if workout.perfect_run else 0
            daily.challenge_progress = max(
                daily.challenge_progress, min(5, perfect_count)
            )
        elif payload.correct and kind == f"{payload.mode}Three":
            daily.challenge_progress = min(3, daily.challenge_progress + 1)
        if daily.challenge_progress >= CHALLENGE_TARGETS[kind]:
            daily.challenge_completed = True
            daily.xp_earned += 30
            profile.total_xp += 30

    if daily.answered >= profile.daily_goal and not daily.goal_reward_awarded:
        daily.goal_reward_awarded = True
        daily.xp_earned += 25
        profile.total_xp += 25


async def _apply_sudoku(
    session: AsyncSession, user_id: uuid.UUID, event: SudokuCompletedEvent
) -> None:
    payload = event.payload
    if payload.mode == "daily" and payload.day_key is None:
        raise EventRejected("day_required", "day_key is required for a daily puzzle.")
    existing = await session.get(SudokuCompletion, (user_id, payload.puzzle_id))
    if existing is not None:
        return
    session.add(
        SudokuCompletion(
            user_id=user_id,
            puzzle_id=payload.puzzle_id,
            mode=payload.mode,
            difficulty=payload.difficulty,
            day=payload.day_key,
            elapsed_seconds=payload.elapsed_seconds,
            mistakes=payload.mistakes,
            hints_used=payload.hints_used,
            occurred_at=event.occurred_at,
            is_legacy=False,
        )
    )


async def _apply_melody(
    session: AsyncSession, user_id: uuid.UUID, event: MelodyCompletedEvent
) -> None:
    existing = await session.get(MelodyResult, (user_id, event.session_id))
    if existing is not None:
        return
    payload = event.payload
    session.add(
        MelodyResult(
            user_id=user_id,
            session_id=event.session_id,
            difficulty=payload.difficulty,
            score=payload.score,
            completed_rounds=payload.completed_rounds,
            longest_sequence=payload.longest_sequence,
            occurred_at=event.occurred_at,
        )
    )


async def _recompute_ear_streaks(
    session: AsyncSession, profile: ProgressProfile
) -> None:
    completed = sorted(
        set(
            (
                await session.scalars(
                    select(EarDailyProgress.day).where(
                        EarDailyProgress.user_id == profile.user_id,
                        EarDailyProgress.goal_reward_awarded.is_(True),
                    )
                )
            ).all()
        )
    )
    if not completed:
        return
    profile.last_goal_completion_day = completed[-1]
    longest = current_run = 1
    for previous, current in zip(completed, completed[1:]):
        current_run = current_run + 1 if current == previous + timedelta(days=1) else 1
        longest = max(longest, current_run)
    today = _account_day(datetime.now(timezone.utc), profile.time_zone)
    if completed[-1] not in {today, today - timedelta(days=1)}:
        current = 0
    else:
        current = 1
        cursor = completed[-1]
        completed_set = set(completed)
        while cursor - timedelta(days=1) in completed_set:
            cursor -= timedelta(days=1)
            current += 1
    profile.current_ear_streak = current
    profile.longest_ear_streak = max(profile.longest_ear_streak, longest)


async def _evaluate_achievements(
    session: AsyncSession, profile: ProgressProfile
) -> None:
    mastery = list(
        (
            await session.scalars(
                select(EarSkillProgress).where(EarSkillProgress.user_id == profile.user_id)
            )
        ).all()
    )
    daily = list(
        (
            await session.scalars(
                select(EarDailyProgress).where(EarDailyProgress.user_id == profile.user_id)
            )
        ).all()
    )
    unlocked = set(profile.achievements or [])
    if sum(item.correct for item in mastery) > 0:
        unlocked.add("firstCorrect")
    if any(item.goal_reward_awarded for item in daily):
        unlocked.add("firstGoal")
    if max((item.best_combo for item in daily), default=0) >= 5:
        unlocked.update(("comboFive", "perfectFive"))
    if profile.current_ear_streak >= 7:
        unlocked.add("weekStreak")
    scores = {item.skill_id: item.mastery_score for item in mastery}
    for mode, achievement in (
        ("interval", "intervalMastery"),
        ("chord", "chordMastery"),
        ("note", "noteMastery"),
    ):
        if all(scores.get(skill, 0) >= 85 for skill in SKILLS_BY_MODE[mode]):
            unlocked.add(achievement)
    if profile.total_xp >= 3_600:
        unlocked.add("goldenEar")
    profile.achievements = sorted(unlocked)


async def build_snapshot(
    session: AsyncSession, profile: ProgressProfile
) -> ProgressSnapshot:
    await session.flush()
    now = datetime.now(timezone.utc)
    today = _account_day(now, profile.time_zone)
    daily = await session.get(EarDailyProgress, (profile.user_id, today))
    if daily is None:
        daily_snapshot = DailyEarProgress(
            day=today,
            answered=0,
            correct=0,
            xp_earned=0,
            best_combo=0,
            goal_target=profile.daily_goal,
            goal_completed=False,
            challenge_kind=_challenge_for(today),
            challenge_progress=0,
            challenge_target=CHALLENGE_TARGETS[_challenge_for(today)],
            challenge_completed=False,
        )
    else:
        daily_snapshot = DailyEarProgress(
            day=daily.day,
            answered=daily.answered,
            correct=daily.correct,
            xp_earned=daily.xp_earned,
            best_combo=daily.best_combo,
            goal_target=profile.daily_goal,
            goal_completed=daily.goal_reward_awarded,
            challenge_kind=daily.challenge_kind,
            challenge_progress=daily.challenge_progress,
            challenge_target=CHALLENGE_TARGETS[daily.challenge_kind],
            challenge_completed=daily.challenge_completed,
        )
    skill_rows = list(
        (
            await session.scalars(
                select(EarSkillProgress).where(EarSkillProgress.user_id == profile.user_id)
            )
        ).all()
    )
    completed_goal_days = list(
        (
            await session.scalars(
                select(EarDailyProgress.day).where(
                    EarDailyProgress.user_id == profile.user_id,
                    EarDailyProgress.goal_reward_awarded.is_(True),
                )
            )
        ).all()
    )
    sudoku_rows = list(
        (
            await session.scalars(
                select(SudokuCompletion).where(SudokuCompletion.user_id == profile.user_id)
            )
        ).all()
    )
    melody_rows = list(
        (
            await session.scalars(
                select(MelodyResult).where(MelodyResult.user_id == profile.user_id)
            )
        ).all()
    )
    sudoku = _sudoku_snapshot(profile, sudoku_rows, today)
    melody = _melody_snapshot(profile, melody_rows)
    return ProgressSnapshot(
        revision=profile.revision,
        updated_at=profile.updated_at,
        import_state=(
            "complete" if profile.import_completed_at is not None else "awaiting_choice"
        ),
        preferences=ProgressPreferences(
            daily_goal=profile.daily_goal, time_zone=profile.time_zone
        ),
        account=_level(profile.total_xp),
        ear_training=EarTrainingProgress(
            current_streak=profile.current_ear_streak,
            longest_streak=profile.longest_ear_streak,
            mastery={
                row.skill_id: MasteryProgress(
                    attempts=row.attempts,
                    correct=row.correct,
                    score=row.mastery_score,
                )
                for row in skill_rows
            },
            achievements=sorted(profile.achievements or []),
            completed_goal_days=sorted(set(completed_goal_days))[-90:],
            today=daily_snapshot,
        ),
        games=GameStatistics(sudoku=sudoku, melody=melody),
    )


def _sudoku_snapshot(
    profile: ProgressProfile, rows: list[SudokuCompletion], today: date
) -> SudokuStatistics:
    new_rows = [row for row in rows if not row.is_legacy]
    new_daily_days = {row.day for row in new_rows if row.mode == "daily" and row.day}
    legacy_daily_days = {
        date.fromisoformat(value) for value in profile.legacy_sudoku_completed_daily_days
    }
    daily_days = sorted(legacy_daily_days | new_daily_days)
    last_day = max(
        [day for day in (profile.legacy_sudoku_last_daily_day, *daily_days) if day],
        default=None,
    )
    longest = _longest_consecutive(daily_days)
    current = _current_consecutive(daily_days, today)
    best_times = dict(profile.legacy_sudoku_best_unassisted_seconds or {})
    for row in new_rows:
        if row.elapsed_seconds is not None and row.hints_used == 0:
            best_times[row.difficulty] = min(
                best_times.get(row.difficulty, row.elapsed_seconds), row.elapsed_seconds
            )
    return SudokuStatistics(
        solved_count=profile.legacy_sudoku_solved_count + len(new_rows),
        current_daily_streak=max(
            current,
            profile.legacy_sudoku_current_streak
            if profile.legacy_sudoku_last_daily_day in {today, today - timedelta(days=1)}
            else 0,
        ),
        longest_daily_streak=max(profile.legacy_sudoku_longest_streak, longest),
        last_daily_completion_day=last_day,
        completed_daily_days=daily_days,
        best_unassisted_seconds=best_times,
        completed_puzzle_ids=sorted({row.puzzle_id for row in rows}),
    )


def _melody_snapshot(
    profile: ProgressProfile, rows: list[MelodyResult]
) -> MelodyStatistics:
    best_scores = dict(profile.legacy_melody_best_scores or {})
    for row in rows:
        best_scores[row.difficulty] = max(best_scores.get(row.difficulty, 0), row.score)
    return MelodyStatistics(
        games_played=profile.legacy_melody_games_played + len(rows),
        high_score=max(
            [profile.legacy_melody_high_score, *(row.score for row in rows)]
        ),
        longest_sequence=max(
            [
                profile.legacy_melody_longest_sequence,
                *(row.longest_sequence for row in rows),
            ]
        ),
        total_correct_rounds=profile.legacy_melody_total_correct_rounds
        + sum(row.completed_rounds for row in rows),
        best_scores=best_scores,
    )


def _longest_consecutive(days: list[date]) -> int:
    longest = current = 0
    previous: date | None = None
    for value in sorted(set(days)):
        current = current + 1 if previous and value == previous + timedelta(days=1) else 1
        longest = max(longest, current)
        previous = value
    return longest


def _current_consecutive(days: list[date], today: date) -> int:
    values = set(days)
    cursor = today if today in values else today - timedelta(days=1)
    if cursor not in values:
        return 0
    count = 0
    while cursor in values:
        count += 1
        cursor -= timedelta(days=1)
    return count


async def import_progress(
    session: AsyncSession, user: User, body: ProgressImportRequest
) -> tuple[bool, ProgressSnapshot]:
    profile = await locked_profile(session, user.id)
    if profile.import_completed_at is not None:
        return False, await build_snapshot(session, profile)
    profile.time_zone = validate_time_zone(body.time_zone)
    profile.import_completed_at = utcnow()
    profile.import_source_installation_id = body.installation_id
    if body.strategy == "use_device" and body.legacy is not None:
        await _apply_legacy(session, profile, body.legacy)
    profile.revision += 1
    profile.updated_at = utcnow()
    await _recompute_ear_streaks(session, profile)
    await _evaluate_achievements(session, profile)
    return True, await build_snapshot(session, profile)


async def _apply_legacy(
    session: AsyncSession, profile: ProgressProfile, legacy: LegacyProgress
) -> None:
    ear = legacy.ear_training
    profile.total_xp = ear.total_xp
    profile.daily_goal = ear.daily_goal
    profile.current_ear_streak = ear.current_streak
    profile.longest_ear_streak = ear.longest_streak
    profile.last_goal_completion_day = ear.last_goal_completion_day
    profile.achievements = sorted(set(ear.achievements))
    for skill_id, value in ear.mastery.items():
        if skill_id not in ALL_SKILLS:
            continue
        session.add(
            EarSkillProgress(
                user_id=profile.user_id,
                skill_id=skill_id,
                attempts=value.attempts,
                correct=min(value.correct, value.attempts),
                mastery_score=value.score,
            )
        )
    for goal_day in set(ear.completed_goal_days):
        row = await _daily_row(session, profile.user_id, goal_day)
        row.goal_reward_awarded = True
    if ear.today is not None:
        row = await _daily_row(session, profile.user_id, ear.today.day)
        row.answered = ear.today.answered
        row.correct = min(ear.today.correct, ear.today.answered)
        row.xp_earned = ear.today.xp_earned
        row.best_combo = ear.today.best_combo
        if ear.today.challenge_kind is not None:
            row.challenge_kind = ear.today.challenge_kind
            row.challenge_progress = min(
                CHALLENGE_TARGETS[row.challenge_kind], ear.today.challenge_progress
            )
            row.challenge_completed = ear.today.challenge_completed
        if ear.today.day in set(ear.completed_goal_days):
            row.goal_reward_awarded = True

    sudoku = legacy.sudoku
    profile.legacy_sudoku_solved_count = sudoku.solved_count
    profile.legacy_sudoku_current_streak = sudoku.current_daily_streak
    profile.legacy_sudoku_longest_streak = sudoku.longest_daily_streak
    profile.legacy_sudoku_last_daily_day = sudoku.last_daily_completion_day
    profile.legacy_sudoku_completed_daily_days = [
        value.isoformat() for value in sorted(set(sudoku.completed_daily_days))
    ]
    profile.legacy_sudoku_best_unassisted_seconds = sudoku.best_unassisted_seconds
    for puzzle_id in set(sudoku.completed_puzzle_ids):
        session.add(
            SudokuCompletion(
                user_id=profile.user_id,
                puzzle_id=puzzle_id,
                mode="practice",
                difficulty="medium",
                day=None,
                elapsed_seconds=None,
                mistakes=0,
                hints_used=0,
                occurred_at=utcnow(),
                is_legacy=True,
            )
        )

    melody = legacy.melody
    profile.legacy_melody_games_played = melody.games_played
    profile.legacy_melody_high_score = melody.high_score
    profile.legacy_melody_longest_sequence = melody.longest_sequence
    profile.legacy_melody_total_correct_rounds = melody.total_correct_rounds
    profile.legacy_melody_best_scores = {
        key: max(0, value) for key, value in melody.best_scores.items()
    }
