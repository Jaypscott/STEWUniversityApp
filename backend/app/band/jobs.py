from __future__ import annotations

import asyncio
import io
import json
import subprocess
import uuid
from datetime import datetime, timezone

import httpx
from PIL import Image
from pillow_heif import register_heif_opener
from sqlalchemy import select

from app.band.apns import send_apns
from app.band.database import SessionFactory
from app.band.models import (
    AppleIdentity,
    Asset,
    AssetStatus,
    Band,
    DeviceRegistration,
    Notification,
    PushDelivery,
    User,
)
from app.band.queue import band_queue
from app.band.storage import storage


def validate_asset_job(asset_id: str) -> None:
    asyncio.run(_validate_asset(uuid.UUID(asset_id)))


async def _validate_asset(asset_id: uuid.UUID) -> None:
    async with SessionFactory() as session:
        asset = await session.get(Asset, asset_id)
        if asset is None or asset.status != AssetStatus.processing:
            return
        band = await session.get(Band, asset.band_id, with_for_update=True)
        if band is None:
            return
        try:
            remote = await storage.head(asset.storage_key)
            if remote.byte_size != asset.declared_byte_size:
                raise ValueError("Uploaded size does not match the reserved size")
            if remote.content_type != asset.content_type:
                raise ValueError("Uploaded media type does not match")
            duration, codec = await _probe_media(asset)
            asset.byte_size = remote.byte_size
            asset.checksum = remote.checksum or asset.checksum
            asset.duration_milliseconds = duration
            asset.codec = codec
            asset.status = AssetStatus.ready
            band.reserved_bytes = max(0, band.reserved_bytes - asset.declared_byte_size)
            band.used_bytes += remote.byte_size
        except Exception as exc:
            asset.status = AssetStatus.failed
            asset.failure_reason = str(exc)[:300]
            band.reserved_bytes = max(0, band.reserved_bytes - asset.declared_byte_size)
            await storage.delete(asset.storage_key)
        await session.commit()


async def _probe_media(asset: Asset) -> tuple[int | None, str | None]:
    if asset.kind.value == "image":
        url, _ = await storage.access_url(asset.storage_key)
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.get(url)
            response.raise_for_status()
        register_heif_opener()
        with Image.open(io.BytesIO(response.content)) as image:
            image.verify()
            detected = (image.format or "").upper()
        expected = {
            "image/jpeg": {"JPEG"},
            "image/png": {"PNG"},
            "image/heic": {"HEIF", "HEIC"},
            "image/heif": {"HEIF", "HEIC"},
        }[asset.content_type]
        if detected not in expected:
            raise ValueError("Uploaded image format does not match")
        return None, detected.lower()
    url, _ = await storage.access_url(asset.storage_key)

    def run() -> tuple[int | None, str | None]:
        try:
            process = subprocess.run(
                [
                    "ffprobe",
                    "-v",
                    "error",
                    "-show_entries",
                    "format=duration:stream=codec_name",
                    "-of",
                    "json",
                    url,
                ],
                capture_output=True,
                text=True,
                timeout=30,
                check=True,
            )
            payload = json.loads(process.stdout)
            duration = float(payload.get("format", {}).get("duration", 0))
            streams = payload.get("streams", [])
            codec = streams[0].get("codec_name") if streams else None
            allowed = (
                {"h264", "hevc"}
                if asset.kind.value == "video"
                else {"aac", "mp3", "pcm_s16le", "pcm_s24le", "pcm_f32le", "alac"}
            )
            if codec not in allowed:
                raise ValueError("Uploaded media codec is not supported on iOS")
            return int(duration * 1000), codec
        except FileNotFoundError as exc:
            raise RuntimeError("ffprobe is required for media validation") from exc

    return await asyncio.to_thread(run)


def delete_asset_job(storage_key: str) -> None:
    asyncio.run(storage.delete(storage_key))


def send_push_job(delivery_id: str) -> None:
    asyncio.run(_send_push(uuid.UUID(delivery_id)))


async def _send_push(delivery_id: uuid.UUID) -> None:
    async with SessionFactory() as session:
        delivery = await session.get(PushDelivery, delivery_id)
        if delivery is None or delivery.delivered_at is not None:
            return
        notification = await session.get(Notification, delivery.notification_id)
        device = await session.get(DeviceRegistration, delivery.device_registration_id)
        if notification is None or device is None or not device.notifications_enabled:
            return
        delivery.attempt_count += 1
        retry_error: str | None = None
        try:
            response = await send_apns(
                device,
                {
                    "aps": {
                        "alert": {
                            "title": "Band",
                            "body": "You have new Band activity.",
                        },
                        "sound": "default",
                    },
                    "notification_id": str(notification.id),
                    "entity_type": notification.related_entity_type,
                    "entity_id": str(notification.related_entity_id)
                    if notification.related_entity_id
                    else None,
                },
                push_type="alert",
                priority=10,
            )
            if response.succeeded:
                delivery.delivered_at = datetime.now(timezone.utc)
            elif response.token_is_invalid:
                device.notifications_enabled = False
                delivery.last_error = response.body
            else:
                delivery.last_error = response.body
                retry_error = delivery.last_error
        except Exception as exc:
            delivery.last_error = str(exc)[:300]
            retry_error = delivery.last_error
        await session.commit()
        if retry_error:
            raise RuntimeError(retry_error)


def cleanup_expired_uploads_job() -> None:
    asyncio.run(_maintenance_cleanup())


async def _maintenance_cleanup() -> None:
    await _cleanup_expired_uploads()
    from app.band.account_jobs import _delete_account

    async with SessionFactory() as session:
        pending_account_ids = list(
            (
                await session.scalars(
                    select(User.id)
                    .join(AppleIdentity, AppleIdentity.user_id == User.id)
                    .where(User.deletion_requested_at.is_not(None))
                )
            ).all()
        )
        processing_asset_ids = list(
            (
                await session.scalars(
                    select(Asset.id).where(Asset.status == AssetStatus.processing)
                )
            ).all()
        )
    for user_id in pending_account_ids:
        await _delete_account(user_id)
    for asset_id in processing_asset_ids:
        band_queue.enqueue("media", "app.band.jobs.validate_asset_job", str(asset_id))


async def _cleanup_expired_uploads() -> None:
    async with SessionFactory() as session:
        assets = list(
            (
                await session.scalars(
                    select(Asset).where(
                        Asset.status.in_([AssetStatus.pending, AssetStatus.uploading]),
                        Asset.upload_expires_at < datetime.now(timezone.utc),
                    )
                )
            ).all()
        )
        for asset in assets:
            band = await session.get(Band, asset.band_id, with_for_update=True)
            if band:
                band.reserved_bytes = max(0, band.reserved_bytes - asset.declared_byte_size)
            asset.status = AssetStatus.failed
            asset.failure_reason = "Upload expired"
            await storage.delete(asset.storage_key)
        await session.commit()
