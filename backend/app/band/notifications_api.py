import uuid

from fastapi import APIRouter, Depends, Query, Response
from sqlalchemy import func, or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.band.database import get_session
from app.band.errors import BandAPIError
from app.band.models import Notification, User, UserBlock, utcnow
from app.band.schemas import NotificationResponse, Page
from app.band.security import current_user
from app.band.service import decode_cursor, encode_cursor


router = APIRouter(prefix="/v1/notifications", tags=["Band notifications"])
PAGE_SIZE = 25


@router.get("", response_model=Page[NotificationResponse])
async def list_notifications(
    cursor: str | None = Query(default=None),
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> Page[NotificationResponse]:
    offset = decode_cursor(cursor)
    blocked_actor_ids = select(UserBlock.blocked_user_id).where(
        UserBlock.blocker_user_id == user.id
    ).union(
        select(UserBlock.blocker_user_id).where(UserBlock.blocked_user_id == user.id)
    )
    notifications = list(
        (
            await session.scalars(
                select(Notification)
                .where(
                    Notification.recipient_user_id == user.id,
                    or_(
                        Notification.actor_user_id.is_(None),
                        Notification.actor_user_id.not_in(blocked_actor_ids),
                    ),
                )
                .order_by(Notification.created_at.desc())
                .offset(offset)
                .limit(PAGE_SIZE + 1)
            )
        ).all()
    )
    has_more = len(notifications) > PAGE_SIZE
    return Page(
        items=[NotificationResponse.model_validate(item) for item in notifications[:PAGE_SIZE]],
        next_cursor=encode_cursor(offset + PAGE_SIZE) if has_more else None,
    )


@router.get("/unread-count")
async def unread_count(
    user: User = Depends(current_user), session: AsyncSession = Depends(get_session)
) -> dict[str, int]:
    blocked_actor_ids = select(UserBlock.blocked_user_id).where(
        UserBlock.blocker_user_id == user.id
    ).union(
        select(UserBlock.blocker_user_id).where(UserBlock.blocked_user_id == user.id)
    )
    count = await session.scalar(
        select(func.count(Notification.id)).where(
            Notification.recipient_user_id == user.id,
            Notification.read_at.is_(None),
            or_(
                Notification.actor_user_id.is_(None),
                Notification.actor_user_id.not_in(blocked_actor_ids),
            ),
        )
    )
    return {"count": count or 0}


@router.post("/{notification_id}/read", status_code=204)
async def mark_notification_read(
    notification_id: uuid.UUID,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> Response:
    notification = await session.get(Notification, notification_id)
    if notification is None or notification.recipient_user_id != user.id:
        raise BandAPIError("notification_not_found", "This notification is unavailable.", 404)
    notification.read_at = utcnow()
    await session.commit()
    return Response(status_code=204)


@router.post("/read", status_code=204)
async def mark_all_notifications_read(
    user: User = Depends(current_user), session: AsyncSession = Depends(get_session)
) -> Response:
    await session.execute(
        update(Notification)
        .where(Notification.recipient_user_id == user.id, Notification.read_at.is_(None))
        .values(read_at=utcnow())
    )
    await session.commit()
    return Response(status_code=204)
