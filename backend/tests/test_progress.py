import asyncio
import uuid
from datetime import datetime, timezone

import pytest
from sqlalchemy import select

from app.band.database import Base, SessionFactory, engine
from app.band.models import DeviceRegistration, User, utcnow
from app.main import app
from app.progress import jobs
from app.progress.models import (
    EarDailyProgress,
    MelodyResult,
    ProgressEvent,
    ProgressProfile,
    SudokuCompletion,
)
from app.progress.schemas import (
    EarAnsweredEvent,
    EarAnsweredPayload,
    EventBatchRequest,
    LegacyEarTraining,
    LegacyMelody,
    LegacyProgress,
    LegacySudoku,
    MelodyCompletedEvent,
    MelodyCompletedPayload,
    ProgressImportRequest,
    SudokuCompletedEvent,
    SudokuCompletedPayload,
)
from app.progress.service import import_progress, process_events


def run(coroutine):
    return asyncio.run(coroutine)


async def reset_database() -> None:
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.drop_all)
        await connection.run_sync(Base.metadata.create_all)


@pytest.fixture(autouse=True)
def clean_database():
    run(reset_database())


def profile_user(name: str = "listener") -> User:
    return User(
        username=name,
        display_name=name.title(),
        age_gate_passed_at=utcnow(),
        terms_accepted_at=utcnow(),
        terms_version="test",
    )


def ear_event(
    *,
    installation_id: uuid.UUID,
    session_id: uuid.UUID,
    sequence: int,
    correct: bool,
    client_event_id: uuid.UUID | None = None,
) -> EarAnsweredEvent:
    return EarAnsweredEvent(
        type="ear_answered",
        client_event_id=client_event_id or uuid.uuid4(),
        installation_id=installation_id,
        session_id=session_id,
        sequence_number=sequence,
        occurred_at=datetime.now(timezone.utc),
        payload=EarAnsweredPayload(
            skill_id="interval.major3", mode="interval", correct=correct
        ),
    )


async def create_imported_user(session, name: str = "listener") -> User:
    user = profile_user(name)
    session.add(user)
    await session.flush()
    await import_progress(
        session,
        user,
        ProgressImportRequest(
            strategy="use_account",
            installation_id=uuid.uuid4(),
            time_zone="UTC",
        ),
    )
    await session.commit()
    return user


def test_openapi_exposes_typed_progress_contract():
    paths = app.openapi()["paths"]
    assert "/v1/progress" in paths
    assert "/v1/progress/events" in paths
    assert "/v1/progress/import" in paths
    assert "/v1/progress/preferences" in paths
    event_schema = app.openapi()["components"]["schemas"]["EventBatchRequest"]
    assert event_schema["properties"]["events"]["maxItems"] == 100


def test_ear_events_are_idempotent_and_server_derives_xp_and_mastery():
    async def scenario():
        async with SessionFactory() as session:
            user = await create_imported_user(session)
            installation = uuid.uuid4()
            workout = uuid.uuid4()
            first = ear_event(
                installation_id=installation,
                session_id=workout,
                sequence=1,
                correct=True,
            )
            second = ear_event(
                installation_id=installation,
                session_id=workout,
                sequence=2,
                correct=True,
            )
            result = await process_events(
                session, user, EventBatchRequest(events=[first, second])
            )
            await session.commit()
            assert result.response.accepted == [
                first.client_event_id,
                second.client_event_id,
            ]
            assert result.response.snapshot.account.xp >= 22
            mastery = result.response.snapshot.ear_training.mastery["interval.major3"]
            assert mastery.attempts == 2
            assert mastery.correct == 2
            assert mastery.score == pytest.approx(27.75)

            retry = await process_events(
                session, user, EventBatchRequest(events=[first, second])
            )
            assert retry.response.accepted == []
            assert retry.response.duplicate == [
                first.client_event_id,
                second.client_event_id,
            ]
            assert retry.response.snapshot.account.xp == result.response.snapshot.account.xp
            assert len((await session.scalars(select(ProgressEvent))).all()) == 2

    run(scenario())


def test_workout_combos_are_isolated_between_installations():
    async def scenario():
        async with SessionFactory() as session:
            user = await create_imported_user(session)
            events = [
                ear_event(
                    installation_id=uuid.uuid4(),
                    session_id=uuid.uuid4(),
                    sequence=1,
                    correct=True,
                ),
                ear_event(
                    installation_id=uuid.uuid4(),
                    session_id=uuid.uuid4(),
                    sequence=1,
                    correct=True,
                ),
            ]
            response = (
                await process_events(session, user, EventBatchRequest(events=events))
            ).response
            daily = response.snapshot.ear_training.today
            assert daily.answered == 2
            assert daily.correct == 2
            assert daily.best_combo == 1
            assert daily.xp_earned == 20

    run(scenario())


def test_daily_goal_reward_is_granted_only_once():
    async def scenario():
        async with SessionFactory() as session:
            user = await create_imported_user(session)
            installation = uuid.uuid4()
            workout = uuid.uuid4()
            events = [
                ear_event(
                    installation_id=installation,
                    session_id=workout,
                    sequence=index,
                    correct=True,
                )
                for index in range(1, 6)
            ]
            first = (
                await process_events(session, user, EventBatchRequest(events=events))
            ).response
            assert first.snapshot.ear_training.today.goal_completed is True
            before = first.snapshot.account.xp
            wrong = ear_event(
                installation_id=installation,
                session_id=workout,
                sequence=6,
                correct=False,
            )
            second = (
                await process_events(
                    session, user, EventBatchRequest(events=[wrong])
                )
            ).response
            assert second.snapshot.account.xp == before
            row = await session.get(
                EarDailyProgress,
                (user.id, datetime.now(timezone.utc).date()),
            )
            assert row.goal_reward_awarded is True

    run(scenario())


def test_game_results_merge_by_puzzle_and_session_without_awarding_xp():
    async def scenario():
        async with SessionFactory() as session:
            user = await create_imported_user(session)
            installation = uuid.uuid4()
            sudoku_session = uuid.uuid4()
            sudoku_events = [
                SudokuCompletedEvent(
                    type="sudoku_completed",
                    client_event_id=uuid.uuid4(),
                    installation_id=installation,
                    session_id=sudoku_session,
                    sequence_number=index,
                    occurred_at=datetime.now(timezone.utc),
                    payload=SudokuCompletedPayload(
                        puzzle_id="daily-2026-07-20",
                        mode="daily",
                        difficulty="medium",
                        day_key="2026-07-20",
                        elapsed_seconds=seconds,
                        mistakes=0,
                        hints_used=0,
                    ),
                )
                for index, seconds in ((1, 120), (2, 90))
            ]
            melody_session = uuid.uuid4()
            melody_events = [
                MelodyCompletedEvent(
                    type="melody_completed",
                    client_event_id=uuid.uuid4(),
                    installation_id=installation,
                    session_id=melody_session,
                    sequence_number=index,
                    occurred_at=datetime.now(timezone.utc),
                    payload=MelodyCompletedPayload(
                        difficulty="hard",
                        score=score,
                        completed_rounds=rounds,
                        longest_sequence=rounds,
                    ),
                )
                for index, score, rounds in ((1, 800, 8), (2, 900, 9))
            ]
            result = await process_events(
                session,
                user,
                EventBatchRequest(events=[*sudoku_events, *melody_events]),
            )
            snapshot = result.response.snapshot
            assert snapshot.account.xp == 0
            assert snapshot.games.sudoku.solved_count == 1
            assert snapshot.games.sudoku.best_unassisted_seconds == {"medium": 120}
            assert snapshot.games.melody.games_played == 1
            assert snapshot.games.melody.high_score == 800
            assert len((await session.scalars(select(SudokuCompletion))).all()) == 1
            assert len((await session.scalars(select(MelodyResult))).all()) == 1

    run(scenario())


def test_legacy_import_is_exactly_once_and_preserves_primary_device_data():
    async def scenario():
        async with SessionFactory() as session:
            user = profile_user()
            session.add(user)
            await session.flush()
            first_device = uuid.uuid4()
            body = ProgressImportRequest(
                strategy="use_device",
                installation_id=first_device,
                time_zone="America/New_York",
                legacy=LegacyProgress(
                    ear_training=LegacyEarTraining(
                        total_xp=620,
                        current_streak=3,
                        longest_streak=7,
                        daily_goal=10,
                        achievements=["firstCorrect"],
                    ),
                    sudoku=LegacySudoku(
                        solved_count=4,
                        completed_puzzle_ids=["p1", "p2", "p3", "p4"],
                        best_unassisted_seconds={"medium": 88},
                    ),
                    melody=LegacyMelody(
                        games_played=5,
                        high_score=900,
                        longest_sequence=11,
                        total_correct_rounds=40,
                        best_scores={"hard": 900},
                    ),
                ),
            )
            applied, first = await import_progress(session, user, body)
            await session.commit()
            assert applied is True
            assert first.account.xp == 620
            assert first.account.level == 3
            assert first.games.sudoku.solved_count == 4
            assert first.games.melody.games_played == 5

            applied_again, second = await import_progress(
                session,
                user,
                ProgressImportRequest(
                    strategy="use_account",
                    installation_id=uuid.uuid4(),
                    time_zone="UTC",
                ),
            )
            assert applied_again is False
            assert second.preferences.time_zone == "America/New_York"
            profile = await session.get(ProgressProfile, user.id)
            assert profile.import_source_installation_id == first_device

    run(scenario())


def test_progress_foreign_keys_delete_with_the_account():
    for table in (
        ProgressProfile.__table__,
        ProgressEvent.__table__,
        EarDailyProgress.__table__,
        SudokuCompletion.__table__,
        MelodyResult.__table__,
    ):
        user_foreign_keys = [
            foreign_key for foreign_key in table.foreign_keys if foreign_key.column.name == "id"
        ]
        assert user_foreign_keys
        assert all(key.ondelete == "CASCADE" for key in user_foreign_keys)


def test_background_push_excludes_the_originating_installation(monkeypatch):
    captured: list[uuid.UUID | None] = []

    async def fake_send(device, payload, **kwargs):
        captured.append(device.installation_id)

        class Response:
            succeeded = True
            token_is_invalid = False
            body = ""

        return Response()

    monkeypatch.setattr(jobs, "send_apns", fake_send)

    async def scenario():
        async with SessionFactory() as session:
            user = profile_user()
            origin = uuid.uuid4()
            other = uuid.uuid4()
            session.add(user)
            await session.flush()
            session.add_all(
                [
                    DeviceRegistration(
                        user_id=user.id,
                        device_token="a" * 64,
                        installation_id=origin,
                        environment="sandbox",
                        notifications_enabled=False,
                    ),
                    DeviceRegistration(
                        user_id=user.id,
                        device_token="b" * 64,
                        installation_id=other,
                        environment="sandbox",
                        notifications_enabled=False,
                    ),
                ]
            )
            await session.commit()
            user_id = user.id
        await jobs._send_progress_invalidation(user_id, 4, origin)
        assert captured == [other]

    run(scenario())
