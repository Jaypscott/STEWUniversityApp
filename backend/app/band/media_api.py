import uuid

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.band.database import get_session
from app.band.errors import BandAPIError
from app.band.models import Asset, AssetKind, AssetStatus, Band, Project, User
from app.band.queue import band_queue
from app.band.schemas import AssetResponse, MediaAccess, UploadRequest, UploadSlot
from app.band.security import current_user
from app.band.service import MAX_BAND_BYTES, editable_membership, membership_for
from app.band.storage import storage


router = APIRouter(prefix="/v1/assets", tags=["Band media"])

IMAGE_TYPES = {"image/jpeg", "image/png", "image/heic", "image/heif"}
AUDIO_TYPES = {
    "audio/mp4",
    "audio/mpeg",
    "audio/wav",
    "audio/x-wav",
    "audio/aac",
    "audio/x-caf",
}
VIDEO_TYPES = {"video/mp4", "video/quicktime"}


def validate_upload(body: UploadRequest) -> None:
    allowed = {
        AssetKind.image: IMAGE_TYPES,
        AssetKind.audio: AUDIO_TYPES,
        AssetKind.video: VIDEO_TYPES,
    }[body.kind]
    if body.content_type.lower() not in allowed:
        raise BandAPIError("unsupported_media", "This media format is not supported.", 415)
    maximum = 20 * 1024 * 1024 if body.kind == AssetKind.image else 100 * 1024 * 1024
    if body.byte_size > maximum:
        limit = "20 MB" if body.kind == AssetKind.image else "100 MB"
        raise BandAPIError("file_too_large", f"This file must be {limit} or smaller.", 413)
    if body.kind in {AssetKind.audio, AssetKind.video} and body.project_id is None:
        raise BandAPIError(
            "project_media_required", "Audio and video must be uploaded inside a project.", 409
        )


@router.post("/uploads", response_model=UploadSlot, status_code=201)
async def create_upload(
    body: UploadRequest,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> UploadSlot:
    validate_upload(body)
    await editable_membership(session, body.band_id, user.id)
    if body.project_id:
        project = await session.get(Project, body.project_id)
        if project is None or project.band_id != body.band_id or project.archived_at:
            raise BandAPIError("project_not_found", "Choose an active project.", 404)
    band = await session.get(Band, body.band_id, with_for_update=True)
    if band is None:
        raise BandAPIError("band_not_found", "This Band no longer exists.", 404)
    if band.used_bytes + band.reserved_bytes + body.byte_size > MAX_BAND_BYTES:
        raise BandAPIError(
            "storage_quota_reached", "This Band has reached its 2 GB storage limit.", 409
        )
    asset_id = uuid.uuid4()
    key = f"bands/{body.band_id}/assets/{asset_id}/original"
    upload_url, expires_at = await storage.upload_url(key, body.content_type.lower())
    asset = Asset(
        id=asset_id,
        band_id=body.band_id,
        project_id=body.project_id,
        uploaded_by_user_id=user.id,
        kind=body.kind,
        status=AssetStatus.uploading,
        storage_key=key,
        original_filename=body.filename,
        content_type=body.content_type.lower(),
        declared_byte_size=body.byte_size,
        checksum=body.checksum,
        upload_expires_at=expires_at,
    )
    band.reserved_bytes += body.byte_size
    session.add(asset)
    await session.commit()
    return UploadSlot(
        asset=AssetResponse.model_validate(asset),
        upload_url=upload_url,
        expires_at=expires_at,
        required_headers={"Content-Type": asset.content_type},
    )


@router.post("/{asset_id}/complete", response_model=AssetResponse)
async def complete_upload(
    asset_id: uuid.UUID,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> AssetResponse:
    asset = await session.get(Asset, asset_id, with_for_update=True)
    if asset is None:
        raise BandAPIError("asset_not_found", "This upload no longer exists.", 404)
    await membership_for(session, asset.band_id, user.id)
    if asset.uploaded_by_user_id != user.id:
        raise BandAPIError("permission_denied", "Only the uploader can complete this upload.", 403)
    if asset.status == AssetStatus.ready:
        return AssetResponse.model_validate(asset)
    if asset.status == AssetStatus.processing:
        band_queue.enqueue("media", "app.band.jobs.validate_asset_job", str(asset.id))
        return AssetResponse.model_validate(asset)
    if asset.status not in {AssetStatus.pending, AssetStatus.uploading}:
        raise BandAPIError("upload_failed", "Start a new upload and try again.", 409)
    remote = await storage.head(asset.storage_key)
    if remote.byte_size != asset.declared_byte_size:
        band = await session.get(Band, asset.band_id, with_for_update=True)
        if band:
            band.reserved_bytes = max(0, band.reserved_bytes - asset.declared_byte_size)
        asset.status = AssetStatus.failed
        asset.failure_reason = "Uploaded size does not match the declared size"
        await session.commit()
        band_queue.enqueue("media", "app.band.jobs.delete_asset_job", asset.storage_key)
        raise BandAPIError("upload_size_mismatch", "The uploaded size does not match.", 409)
    asset.status = AssetStatus.processing
    await session.commit()
    band_queue.enqueue("media", "app.band.jobs.validate_asset_job", str(asset.id))
    return AssetResponse.model_validate(asset)


@router.get("/{asset_id}", response_model=AssetResponse)
async def get_asset(
    asset_id: uuid.UUID,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> AssetResponse:
    asset = await session.get(Asset, asset_id)
    if asset is None or asset.deleted_at:
        raise BandAPIError("asset_not_found", "This media is unavailable.", 404)
    await membership_for(session, asset.band_id, user.id)
    return AssetResponse.model_validate(asset)


@router.get("/{asset_id}/access", response_model=MediaAccess)
async def access_asset(
    asset_id: uuid.UUID,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> MediaAccess:
    asset = await session.get(Asset, asset_id)
    if asset is None or asset.deleted_at:
        raise BandAPIError("asset_not_found", "This media is unavailable.", 404)
    await membership_for(session, asset.band_id, user.id)
    if asset.status != AssetStatus.ready:
        raise BandAPIError("asset_not_ready", "This media is still processing.", 409)
    url, expires_at = await storage.access_url(asset.storage_key)
    return MediaAccess(url=url, expires_at=expires_at)
