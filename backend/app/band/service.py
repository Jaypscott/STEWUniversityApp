import base64
import uuid
from datetime import datetime, timezone

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.band.errors import BandAPIError
from app.band.models import (
    Band,
    BandMembership,
    BandRole,
    DeviceRegistration,
    MembershipStatus,
    Notification,
    NotificationKind,
    PushDelivery,
    User,
    UserBlock,
)
from app.band.queue import band_queue


MAX_OWNED_BANDS = 3
MAX_BAND_MEMBERS = 20
MAX_BAND_BYTES = 2 * 1024 * 1024 * 1024


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def profile_complete(user: User) -> bool:
    return bool(
        user.username
        and user.display_name
        and user.age_gate_passed_at
        and user.terms_accepted_at
    )


def require_complete_profile(user: User) -> None:
    if not profile_complete(user):
        raise BandAPIError(
            "profile_required", "Complete your Band profile to continue.", 403
        )


async def membership_for(
    session: AsyncSession, band_id: uuid.UUID, user_id: uuid.UUID
) -> BandMembership:
    membership = await session.scalar(
        select(BandMembership).where(
            BandMembership.band_id == band_id,
            BandMembership.user_id == user_id,
            BandMembership.status == MembershipStatus.active,
        )
    )
    if membership is None:
        raise BandAPIError("band_access_denied", "You no longer have access to this Band.", 403)
    return membership


async def editable_membership(
    session: AsyncSession,
    band_id: uuid.UUID,
    user_id: uuid.UUID,
    roles: set[BandRole] | None = None,
) -> tuple[Band, BandMembership]:
    membership = await membership_for(session, band_id, user_id)
    band = await session.get(Band, band_id)
    if band is None:
        raise BandAPIError("band_not_found", "This Band no longer exists.", 404)
    if band.archived_at is not None:
        raise BandAPIError("band_archived", "Restore this Band before making changes.", 409)
    if roles is not None and membership.role not in roles:
        raise BandAPIError("permission_denied", "You don’t have permission to do that.", 403)
    return band, membership


async def blocked_between(
    session: AsyncSession, first_user_id: uuid.UUID, second_user_id: uuid.UUID
) -> bool:
    return bool(
        await session.scalar(
            select(func.count(UserBlock.id)).where(
                or_(
                    (UserBlock.blocker_user_id == first_user_id)
                    & (UserBlock.blocked_user_id == second_user_id),
                    (UserBlock.blocker_user_id == second_user_id)
                    & (UserBlock.blocked_user_id == first_user_id),
                )
            )
        )
    )


async def create_notification(
    session: AsyncSession,
    *,
    recipient_user_id: uuid.UUID,
    band_id: uuid.UUID | None,
    actor_user_id: uuid.UUID | None,
    kind: NotificationKind,
    entity_type: str | None,
    entity_id: uuid.UUID | None,
    dedupe_key: str,
    send_push: bool,
) -> Notification | None:
    if actor_user_id == recipient_user_id:
        return None
    if actor_user_id and await blocked_between(session, recipient_user_id, actor_user_id):
        return None
    existing = await session.scalar(
        select(Notification).where(
            Notification.recipient_user_id == recipient_user_id,
            Notification.dedupe_key == dedupe_key,
        )
    )
    if existing:
        return existing
    notification = Notification(
        recipient_user_id=recipient_user_id,
        band_id=band_id,
        actor_user_id=actor_user_id,
        kind=kind,
        related_entity_type=entity_type,
        related_entity_id=entity_id,
        dedupe_key=dedupe_key,
    )
    session.add(notification)
    await session.flush()
    if send_push:
        devices = list(
            (
                await session.scalars(
                    select(DeviceRegistration).where(
                        DeviceRegistration.user_id == recipient_user_id,
                        DeviceRegistration.notifications_enabled.is_(True),
                    )
                )
            ).all()
        )
        for device in devices:
            delivery = PushDelivery(
                notification_id=notification.id,
                device_registration_id=device.id,
            )
            session.add(delivery)
            await session.flush()
            band_queue.enqueue(
                "notifications", "app.band.jobs.send_push_job", str(delivery.id)
            )
    return notification


def encode_cursor(offset: int) -> str:
    return base64.urlsafe_b64encode(str(offset).encode()).decode().rstrip("=")


def decode_cursor(cursor: str | None) -> int:
    if not cursor:
        return 0
    try:
        padded = cursor + "=" * (-len(cursor) % 4)
        return max(0, int(base64.urlsafe_b64decode(padded).decode()))
    except Exception as exc:
        raise BandAPIError("invalid_cursor", "This page cursor is invalid.") from exc
