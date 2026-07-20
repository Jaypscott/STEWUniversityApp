import uuid

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.band.content import validate_text
from app.band.database import get_session
from app.band.errors import BandAPIError
from app.band.models import (
    Asset,
    AssetStatus,
    Band,
    BandMembership,
    Comment,
    ContentReport,
    NotificationKind,
    Post,
    ReportStatus,
    User,
    MembershipStatus,
    utcnow,
)
from app.band.queue import band_queue
from app.band.schemas import ReportCreate, ReportResolve, ReportResponse
from app.band.security import current_user
from app.band.service import create_notification, membership_for


router = APIRouter(prefix="/v1", tags=["Band safety"])


async def validate_report_target(
    session: AsyncSession, body: ReportCreate
) -> uuid.UUID | None:
    if body.target_type == "user":
        target = await session.get(User, body.target_id)
        if target is None:
            return None
        active_member = await session.scalar(
            select(BandMembership.id).where(
                BandMembership.band_id == body.band_id,
                BandMembership.user_id == target.id,
                BandMembership.status == MembershipStatus.active,
            )
        )
        return target.id if active_member else None
    model = {"post": Post, "comment": Comment, "asset": Asset}[body.target_type]
    target = await session.get(model, body.target_id)
    if target is None:
        return None
    if body.target_type == "post":
        return target.author_user_id if target.band_id == body.band_id else None
    if body.target_type == "comment":
        post = await session.get(Post, target.post_id)
        return target.author_user_id if post and post.band_id == body.band_id else None
    return target.uploaded_by_user_id if target.band_id == body.band_id else None


@router.post("/reports", response_model=ReportResponse, status_code=201)
async def create_report(
    body: ReportCreate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> ReportResponse:
    await membership_for(session, body.band_id, user.id)
    target_user_id = await validate_report_target(session, body)
    if target_user_id is None:
        raise BandAPIError("report_target_not_found", "This content is unavailable.", 404)
    report = ContentReport(
        reporter_user_id=user.id,
        band_id=body.band_id,
        target_type=body.target_type,
        target_id=body.target_id,
        reason=body.reason,
        note=validate_text(body.note, field="note", maximum=1000, allow_empty=True),
    )
    session.add(report)
    await session.flush()
    admin_ids = list(
        (
            await session.scalars(select(User.id).where(User.is_platform_admin.is_(True)))
        ).all()
    )
    for admin_id in admin_ids:
        await create_notification(
            session,
            recipient_user_id=admin_id,
            band_id=body.band_id,
            actor_user_id=user.id,
            kind=NotificationKind.report_received,
            entity_type="report",
            entity_id=report.id,
            dedupe_key=f"report:{report.id}",
            send_push=True,
        )
    await session.commit()
    return ReportResponse.model_validate(report)


@router.get("/reports/mine", response_model=list[ReportResponse])
async def my_reports(
    user: User = Depends(current_user), session: AsyncSession = Depends(get_session)
) -> list[ReportResponse]:
    reports = list(
        (
            await session.scalars(
                select(ContentReport)
                .where(ContentReport.reporter_user_id == user.id)
                .order_by(ContentReport.created_at.desc())
            )
        ).all()
    )
    return [ReportResponse.model_validate(item) for item in reports]


def require_platform_admin(user: User) -> None:
    if not user.is_platform_admin:
        raise BandAPIError("permission_denied", "Platform administrator access is required.", 403)


@router.get("/admin/reports", response_model=list[ReportResponse])
async def admin_reports(
    user: User = Depends(current_user), session: AsyncSession = Depends(get_session)
) -> list[ReportResponse]:
    require_platform_admin(user)
    reports = list(
        (
            await session.scalars(
                select(ContentReport)
                .where(ContentReport.status == ReportStatus.open)
                .order_by(ContentReport.created_at)
            )
        ).all()
    )
    return [ReportResponse.model_validate(item) for item in reports]


@router.patch("/admin/reports/{report_id}", response_model=ReportResponse)
async def resolve_report(
    report_id: uuid.UUID,
    body: ReportResolve,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> ReportResponse:
    require_platform_admin(user)
    report = await session.get(ContentReport, report_id)
    if report is None:
        raise BandAPIError("report_not_found", "This report no longer exists.", 404)
    target_user_id: uuid.UUID | None = None
    if report.target_type == "user":
        target_user_id = report.target_id
    elif report.target_type == "post":
        target = await session.get(Post, report.target_id)
        if target:
            target_user_id = target.author_user_id
            if body.remove_content:
                target.deleted_at = utcnow()
                target.is_pinned = False
                target.pinned_at = None
    elif report.target_type == "comment":
        target = await session.get(Comment, report.target_id)
        if target:
            target_user_id = target.author_user_id
            if body.remove_content:
                target.deleted_at = utcnow()
    elif report.target_type == "asset":
        target = await session.get(Asset, report.target_id)
        if target:
            target_user_id = target.uploaded_by_user_id
            if body.remove_content and target.deleted_at is None:
                target.deleted_at = utcnow()
                band = await session.get(Band, target.band_id, with_for_update=True)
                if band:
                    if target.status == AssetStatus.ready:
                        band.used_bytes = max(0, band.used_bytes - (target.byte_size or 0))
                    else:
                        band.reserved_bytes = max(
                            0, band.reserved_bytes - target.declared_byte_size
                        )
                band_queue.enqueue(
                    "media", "app.band.jobs.delete_asset_job", target.storage_key
                )
    if body.suspend_user and target_user_id:
        target_user = await session.get(User, target_user_id)
        if target_user:
            target_user.suspended_at = utcnow()
    report.status = body.status
    report.resolution_note = validate_text(
        body.resolution_note,
        field="resolution_note",
        maximum=1000,
        allow_empty=True,
    )
    report.resolved_by_user_id = user.id
    report.resolved_at = utcnow()
    await session.commit()
    return ReportResponse.model_validate(report)
