import asyncio
import uuid

from sqlalchemy import delete, or_, select

from app.band.database import SessionFactory
from app.band.models import (
    AppleIdentity,
    Asset,
    AssetStatus,
    AuthSession,
    Band,
    BandInvitation,
    BandMembership,
    Comment,
    ContentReport,
    DeviceRegistration,
    Notification,
    Post,
    SongwritingConversation,
    TrackTake,
    User,
    UserBlock,
)
from app.band.storage import storage


def delete_band_job(band_id: str) -> None:
    asyncio.run(_delete_band_media(uuid.UUID(band_id)))


async def _delete_band_media(band_id: uuid.UUID) -> None:
    async with SessionFactory() as session:
        keys = list(
            (
                await session.scalars(
                    select(Asset.storage_key).where(Asset.band_id == band_id)
                )
            ).all()
        )
    for key in keys:
        await storage.delete(key)


def delete_account_job(user_id: str) -> None:
    asyncio.run(_delete_account(uuid.UUID(user_id)))


async def _delete_account(user_id: uuid.UUID) -> None:
    async with SessionFactory() as session:
        assets = list(
            (
                await session.scalars(
                    select(Asset).where(Asset.uploaded_by_user_id == user_id)
                )
            ).all()
        )
        keys = [asset.storage_key for asset in assets]
        for asset in assets:
            band = await session.get(Band, asset.band_id, with_for_update=True)
            if band:
                if asset.status == AssetStatus.ready:
                    band.used_bytes = max(0, band.used_bytes - (asset.byte_size or 0))
                elif asset.status in {
                    AssetStatus.pending,
                    AssetStatus.uploading,
                    AssetStatus.processing,
                }:
                    band.reserved_bytes = max(
                        0, band.reserved_bytes - asset.declared_byte_size
                    )
            await session.delete(asset)
        await session.execute(delete(Comment).where(Comment.author_user_id == user_id))
        await session.execute(delete(Post).where(Post.author_user_id == user_id))
        await session.execute(
            delete(SongwritingConversation).where(
                SongwritingConversation.user_id == user_id
            )
        )
        await session.execute(delete(TrackTake).where(TrackTake.created_by_user_id == user_id))
        await session.execute(
            delete(Notification).where(
                or_(
                    Notification.recipient_user_id == user_id,
                    Notification.actor_user_id == user_id,
                )
            )
        )
        await session.execute(delete(ContentReport).where(ContentReport.reporter_user_id == user_id))
        await session.execute(delete(BandInvitation).where(BandInvitation.created_by_user_id == user_id))
        await session.execute(delete(BandMembership).where(BandMembership.user_id == user_id))
        await session.execute(delete(DeviceRegistration).where(DeviceRegistration.user_id == user_id))
        await session.execute(delete(AuthSession).where(AuthSession.user_id == user_id))
        await session.execute(delete(AppleIdentity).where(AppleIdentity.user_id == user_id))
        await session.execute(
            delete(UserBlock).where(
                or_(
                    UserBlock.blocker_user_id == user_id,
                    UserBlock.blocked_user_id == user_id,
                )
            )
        )
        user = await session.get(User, user_id)
        if user:
            # Keep a non-identifying tombstone so projects and tracks created during
            # collaboration retain referential integrity after the account is gone.
            user.username = None
            user.display_name = None
            user.age_gate_passed_at = None
            user.terms_accepted_at = None
            user.terms_version = None
            user.is_platform_admin = False
            user.suspended_at = None
        await session.commit()
    for key in keys:
        await storage.delete(key)
