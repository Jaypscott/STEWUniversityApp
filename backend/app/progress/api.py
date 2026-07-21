from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.band.database import get_session
from app.band.errors import BandAPIError
from app.band.models import User, utcnow
from app.band.queue import band_queue
from app.band.security import current_user
from app.band.service import require_complete_profile
from app.config.settings import settings
from app.progress.schemas import (
    EventBatchRequest,
    EventBatchResponse,
    ProgressImportRequest,
    ProgressImportResponse,
    ProgressPreferencesPatch,
    ProgressPreferencesResponse,
    ProgressSnapshot,
)
from app.progress.service import (
    _account_day,
    _daily_row,
    _evaluate_achievements,
    _recompute_ear_streaks,
    build_snapshot,
    get_or_create_profile,
    import_progress,
    locked_profile,
    process_events,
    validate_time_zone,
)


router = APIRouter(prefix="/v1/progress", tags=["Account progress"])


def require_progress_enabled() -> None:
    if not settings.progress_sync_enabled:
        raise BandAPIError(
            "progress_sync_disabled",
            "Account progress sync is not enabled yet.",
            503,
        )


def require_progress_user(user: User) -> None:
    require_progress_enabled()
    require_complete_profile(user)


@router.get("", response_model=ProgressSnapshot)
async def get_progress(
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> ProgressSnapshot:
    require_progress_user(user)
    profile = await get_or_create_profile(session, user.id)
    snapshot = await build_snapshot(session, profile)
    await session.commit()
    return snapshot


@router.post("/events", response_model=EventBatchResponse)
async def post_progress_events(
    body: EventBatchRequest,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> EventBatchResponse:
    require_progress_user(user)
    result = await process_events(session, user, body)
    await session.commit()
    if result.response.accepted:
        band_queue.enqueue(
            "notifications",
            "app.progress.jobs.send_progress_invalidation_job",
            str(user.id),
            result.response.snapshot.revision,
            str(result.origin_installation_id) if result.origin_installation_id else None,
        )
    return result.response


@router.post("/import", response_model=ProgressImportResponse)
async def post_progress_import(
    body: ProgressImportRequest,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> ProgressImportResponse:
    require_progress_user(user)
    try:
        applied, snapshot = await import_progress(session, user, body)
    except ValueError as exc:
        raise BandAPIError("invalid_time_zone", str(exc), field="time_zone") from exc
    await session.commit()
    if applied:
        band_queue.enqueue(
            "notifications",
            "app.progress.jobs.send_progress_invalidation_job",
            str(user.id),
            snapshot.revision,
            str(body.installation_id),
        )
    return ProgressImportResponse(applied=applied, snapshot=snapshot)


@router.patch("/preferences", response_model=ProgressPreferencesResponse)
async def patch_progress_preferences(
    body: ProgressPreferencesPatch,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> ProgressPreferencesResponse:
    require_progress_user(user)
    profile = await locked_profile(session, user.id)
    if body.time_zone is not None:
        try:
            profile.time_zone = validate_time_zone(body.time_zone)
        except ValueError as exc:
            raise BandAPIError("invalid_time_zone", str(exc), field="time_zone") from exc
    if body.daily_goal is not None:
        profile.daily_goal = body.daily_goal
        today = _account_day(utcnow(), profile.time_zone)
        daily = await _daily_row(session, user.id, today)
        if daily.answered >= profile.daily_goal and not daily.goal_reward_awarded:
            daily.goal_reward_awarded = True
            daily.xp_earned += 25
            profile.total_xp += 25
    await _recompute_ear_streaks(session, profile)
    await _evaluate_achievements(session, profile)
    profile.revision += 1
    profile.updated_at = utcnow()
    snapshot = await build_snapshot(session, profile)
    await session.commit()
    band_queue.enqueue(
        "notifications",
        "app.progress.jobs.send_progress_invalidation_job",
        str(user.id),
        snapshot.revision,
        None,
    )
    return ProgressPreferencesResponse(snapshot=snapshot)
