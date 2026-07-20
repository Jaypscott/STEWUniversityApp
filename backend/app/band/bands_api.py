import hashlib
import re
import secrets
import uuid
from datetime import timedelta

from fastapi import APIRouter, Depends, Query, Response
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.band.content import validate_text
from app.band.database import get_session
from app.band.errors import BandAPIError
from app.band.models import (
    Asset,
    AssetKind,
    AssetStatus,
    Band,
    BandInvitation,
    BandMembership,
    BandRole,
    InvitationStatus,
    MembershipStatus,
    NotificationKind,
    PostAttachment,
    Project,
    User,
    utcnow,
)
from app.band.queue import band_queue
from app.band.schemas import (
    BandCreate,
    BandResponse,
    BandUpdate,
    InvitationPreview,
    InvitationResponse,
    MemberResponse,
    OwnershipTransfer,
    PendingInvitationResponse,
    RoleUpdate,
)
from app.band.security import current_user
from app.band.service import (
    MAX_BAND_MEMBERS,
    MAX_OWNED_BANDS,
    create_notification,
    editable_membership,
    membership_for,
    require_complete_profile,
)
from app.config.settings import settings


router = APIRouter(prefix="/v1", tags=["Bands"])
ACCENT_COLOR_PATTERN = re.compile(r"^#[0-9A-Fa-f]{6}$")


async def band_response(
    session: AsyncSession, band: Band, user_id: uuid.UUID
) -> BandResponse:
    membership = await membership_for(session, band.id, user_id)
    member_count = await session.scalar(
        select(func.count(BandMembership.id)).where(
            BandMembership.band_id == band.id,
            BandMembership.status == MembershipStatus.active,
        )
    )
    return BandResponse(
        id=band.id,
        name=band.name,
        description=band.description,
        owner_user_id=band.owner_user_id,
        image_asset_id=band.image_asset_id,
        accent_color_hex=band.accent_color_hex,
        featured_project_id=band.featured_project_id,
        used_bytes=band.used_bytes,
        reserved_bytes=band.reserved_bytes,
        archived_at=band.archived_at,
        created_at=band.created_at,
        role=membership.role,
        member_count=member_count,
    )


@router.get("/bands", response_model=list[BandResponse])
async def list_bands(
    user: User = Depends(current_user), session: AsyncSession = Depends(get_session)
) -> list[BandResponse]:
    require_complete_profile(user)
    bands = list(
        (
            await session.scalars(
                select(Band)
                .join(BandMembership, BandMembership.band_id == Band.id)
                .where(
                    BandMembership.user_id == user.id,
                    BandMembership.status == MembershipStatus.active,
                )
                .order_by(Band.archived_at.is_not(None), Band.updated_at.desc())
            )
        ).all()
    )
    return [await band_response(session, band, user.id) for band in bands]


@router.post("/bands", response_model=BandResponse, status_code=201)
async def create_band(
    body: BandCreate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> BandResponse:
    require_complete_profile(user)
    owned_count = await session.scalar(
        select(func.count(Band.id)).where(Band.owner_user_id == user.id)
    )
    if (owned_count or 0) >= MAX_OWNED_BANDS:
        raise BandAPIError(
            "owned_band_limit", f"You can own up to {MAX_OWNED_BANDS} Bands.", 409
        )
    band = Band(
        name=validate_text(body.name, field="name", maximum=50),
        description=validate_text(
            body.description, field="description", maximum=500, allow_empty=True
        ),
        owner_user_id=user.id,
    )
    session.add(band)
    await session.flush()
    session.add(
        BandMembership(band_id=band.id, user_id=user.id, role=BandRole.owner)
    )
    await session.commit()
    return await band_response(session, band, user.id)


@router.get("/bands/{band_id}", response_model=BandResponse)
async def get_band(
    band_id: uuid.UUID,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> BandResponse:
    band = await session.get(Band, band_id)
    if band is None:
        raise BandAPIError("band_not_found", "This Band no longer exists.", 404)
    return await band_response(session, band, user.id)


@router.patch("/bands/{band_id}", response_model=BandResponse)
async def update_band(
    band_id: uuid.UUID,
    body: BandUpdate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> BandResponse:
    band, membership = await editable_membership(
        session, band_id, user.id, {BandRole.owner, BandRole.admin}
    )
    if body.archived is not None and membership.role != BandRole.owner:
        raise BandAPIError("permission_denied", "Only the owner can archive this Band.", 403)
    if body.name is not None:
        band.name = validate_text(body.name, field="name", maximum=50)
    if body.description is not None:
        band.description = validate_text(
            body.description, field="description", maximum=500, allow_empty=True
        )
    if body.archived is not None:
        band.archived_at = utcnow() if body.archived else None
    old_logo_id = band.image_asset_id
    if "image_asset_id" in body.model_fields_set:
        if body.image_asset_id is not None:
            logo = await session.get(Asset, body.image_asset_id)
            if (
                logo is None
                or logo.band_id != band.id
                or logo.kind != AssetKind.image
                or logo.status != AssetStatus.ready
                or logo.deleted_at is not None
            ):
                raise BandAPIError(
                    "invalid_band_logo", "Choose a ready image from this Band.", 409
                )
        band.image_asset_id = body.image_asset_id
    if "accent_color_hex" in body.model_fields_set:
        if body.accent_color_hex is None:
            band.accent_color_hex = "#E6A817"
        elif not ACCENT_COLOR_PATTERN.fullmatch(body.accent_color_hex):
            raise BandAPIError(
                "invalid_accent_color",
                "Accent color must use the #RRGGBB format.",
                422,
                "accent_color_hex",
            )
        else:
            band.accent_color_hex = body.accent_color_hex.upper()
    if "featured_project_id" in body.model_fields_set:
        if body.featured_project_id is not None:
            featured = await session.get(Project, body.featured_project_id)
            if (
                featured is None
                or featured.band_id != band.id
                or featured.archived_at is not None
            ):
                raise BandAPIError(
                    "invalid_featured_project",
                    "Choose an active project from this Band.",
                    409,
                )
        band.featured_project_id = body.featured_project_id
    storage_key = None
    if old_logo_id and old_logo_id != band.image_asset_id:
        storage_key = await release_logo_if_unused(session, band, old_logo_id)
    await session.commit()
    if storage_key:
        band_queue.enqueue("media", "app.band.jobs.delete_asset_job", storage_key)
    return await band_response(session, band, user.id)


async def release_logo_if_unused(
    session: AsyncSession, band: Band, asset_id: uuid.UUID
) -> str | None:
    still_used = any(
        (
            await session.scalar(
                select(Band.id).where(Band.image_asset_id == asset_id).limit(1)
            ),
            await session.scalar(
                select(Project.id).where(Project.artwork_asset_id == asset_id).limit(1)
            ),
            await session.scalar(
                select(PostAttachment.id)
                .where(PostAttachment.asset_id == asset_id)
                .limit(1)
            ),
        )
    )
    if still_used:
        return None
    asset = await session.get(Asset, asset_id, with_for_update=True)
    if asset is None or asset.band_id != band.id or asset.deleted_at is not None:
        return None
    asset.deleted_at = utcnow()
    if asset.status == AssetStatus.ready:
        band.used_bytes = max(0, band.used_bytes - (asset.byte_size or asset.declared_byte_size))
    elif asset.status in {AssetStatus.pending, AssetStatus.uploading, AssetStatus.processing}:
        band.reserved_bytes = max(0, band.reserved_bytes - asset.declared_byte_size)
    return asset.storage_key


@router.delete("/bands/{band_id}", status_code=204)
async def delete_band(
    band_id: uuid.UUID,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> Response:
    band, membership = await editable_membership(session, band_id, user.id)
    if membership.role != BandRole.owner:
        raise BandAPIError("permission_denied", "Only the owner can delete this Band.", 403)
    storage_keys = list(
        (
            await session.scalars(
                select(Asset.storage_key).where(Asset.band_id == band.id)
            )
        ).all()
    )
    for storage_key in storage_keys:
        band_queue.enqueue("media", "app.band.jobs.delete_asset_job", storage_key)
    await session.delete(band)
    await session.commit()
    return Response(status_code=204)


@router.get("/bands/{band_id}/members", response_model=list[MemberResponse])
async def list_members(
    band_id: uuid.UUID,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> list[MemberResponse]:
    await membership_for(session, band_id, user.id)
    rows = (
        await session.execute(
            select(BandMembership, User)
            .join(User, User.id == BandMembership.user_id)
            .where(
                BandMembership.band_id == band_id,
                BandMembership.status == MembershipStatus.active,
            )
            .order_by(BandMembership.joined_at)
        )
    ).all()
    return [
        MemberResponse(
            user_id=member.user_id,
            username=member_user.username,
            display_name=member_user.display_name,
            role=member.role,
            joined_at=member.joined_at,
        )
        for member, member_user in rows
    ]


@router.patch("/bands/{band_id}/members/{member_user_id}", response_model=MemberResponse)
async def change_member_role(
    band_id: uuid.UUID,
    member_user_id: uuid.UUID,
    body: RoleUpdate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> MemberResponse:
    _, actor = await editable_membership(session, band_id, user.id, {BandRole.owner})
    target = await membership_for(session, band_id, member_user_id)
    if target.role == BandRole.owner or body.role == BandRole.owner:
        raise BandAPIError("use_ownership_transfer", "Use ownership transfer instead.", 409)
    target.role = body.role
    target_user = await session.get(User, member_user_id)
    await create_notification(
        session,
        recipient_user_id=member_user_id,
        band_id=band_id,
        actor_user_id=user.id,
        kind=NotificationKind.role_changed,
        entity_type="band",
        entity_id=band_id,
        dedupe_key=f"role:{target.id}:{target.role.value}",
        send_push=True,
    )
    await session.commit()
    return MemberResponse(
        user_id=target.user_id,
        username=target_user.username if target_user else None,
        display_name=target_user.display_name if target_user else None,
        role=target.role,
        joined_at=target.joined_at,
    )


@router.delete("/bands/{band_id}/members/{member_user_id}", status_code=204)
async def remove_member(
    band_id: uuid.UUID,
    member_user_id: uuid.UUID,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> Response:
    _, actor = await editable_membership(
        session, band_id, user.id, {BandRole.owner, BandRole.admin}
    )
    target = await membership_for(session, band_id, member_user_id)
    if target.role == BandRole.owner or (
        target.role == BandRole.admin and actor.role != BandRole.owner
    ):
        raise BandAPIError("permission_denied", "You can’t remove this member.", 403)
    target.status = MembershipStatus.removed
    target.ended_at = utcnow()
    await create_notification(
        session,
        recipient_user_id=member_user_id,
        band_id=band_id,
        actor_user_id=user.id,
        kind=NotificationKind.removed,
        entity_type="band",
        entity_id=band_id,
        dedupe_key=f"removed:{target.id}:{int(utcnow().timestamp())}",
        send_push=True,
    )
    await session.commit()
    return Response(status_code=204)


@router.post("/bands/{band_id}/leave", status_code=204)
async def leave_band(
    band_id: uuid.UUID,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> Response:
    membership = await membership_for(session, band_id, user.id)
    if membership.role == BandRole.owner:
        raise BandAPIError(
            "ownership_transfer_required", "Transfer ownership before leaving this Band.", 409
        )
    membership.status = MembershipStatus.left
    membership.ended_at = utcnow()
    await session.commit()
    return Response(status_code=204)


@router.post("/bands/{band_id}/ownership", status_code=204)
async def transfer_ownership(
    band_id: uuid.UUID,
    body: OwnershipTransfer,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> Response:
    band, owner_membership = await editable_membership(
        session, band_id, user.id, {BandRole.owner}
    )
    target = await membership_for(session, band_id, body.user_id)
    if target.user_id == user.id:
        raise BandAPIError("invalid_transfer", "Choose another active member.")
    target.role = BandRole.owner
    owner_membership.role = BandRole.admin
    band.owner_user_id = target.user_id
    await session.commit()
    return Response(status_code=204)


@router.post("/bands/{band_id}/invitations", response_model=InvitationResponse, status_code=201)
async def create_invitation(
    band_id: uuid.UUID,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> InvitationResponse:
    await editable_membership(session, band_id, user.id, {BandRole.owner, BandRole.admin})
    raw_token = secrets.token_urlsafe(32)
    invitation = BandInvitation(
        band_id=band_id,
        created_by_user_id=user.id,
        token_hash=hashlib.sha256(raw_token.encode()).hexdigest(),
        expires_at=utcnow() + timedelta(days=7),
    )
    session.add(invitation)
    await session.commit()
    return InvitationResponse(
        id=invitation.id,
        band_id=band_id,
        url=f"{settings.public_base_url}/band/invite/{raw_token}",
        expires_at=invitation.expires_at,
        status=invitation.status.value,
    )


@router.get(
    "/bands/{band_id}/invitations", response_model=list[PendingInvitationResponse]
)
async def list_invitations(
    band_id: uuid.UUID,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> list[PendingInvitationResponse]:
    await editable_membership(session, band_id, user.id, {BandRole.owner, BandRole.admin})
    invitations = list(
        (
            await session.scalars(
                select(BandInvitation)
                .where(
                    BandInvitation.band_id == band_id,
                    BandInvitation.status == InvitationStatus.pending,
                )
                .order_by(BandInvitation.created_at.desc())
            )
        ).all()
    )
    return [PendingInvitationResponse.model_validate(item) for item in invitations]


async def invitation_for_token(
    session: AsyncSession, token: str, *, lock: bool = False
) -> BandInvitation:
    query = select(BandInvitation).where(
        BandInvitation.token_hash == hashlib.sha256(token.encode()).hexdigest()
    )
    if lock:
        query = query.with_for_update()
    invitation = await session.scalar(query)
    if invitation is None:
        raise BandAPIError("invitation_not_found", "This invitation is invalid.", 404)
    expires_at = invitation.expires_at
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=utcnow().tzinfo)
    if invitation.status != InvitationStatus.pending or expires_at <= utcnow():
        raise BandAPIError("invitation_expired", "This invitation is no longer available.", 410)
    return invitation


@router.get("/invitations/{token}", response_model=InvitationPreview)
async def preview_invitation(
    token: str, session: AsyncSession = Depends(get_session)
) -> InvitationPreview:
    invitation = await invitation_for_token(session, token)
    band = await session.get(Band, invitation.band_id)
    inviter = await session.get(User, invitation.created_by_user_id)
    if band is None or inviter is None:
        raise BandAPIError("invitation_not_found", "This invitation is invalid.", 404)
    return InvitationPreview(
        band_id=band.id,
        band_name=band.name,
        inviter_display_name=inviter.display_name or "A band member",
        expires_at=invitation.expires_at,
    )


@router.post("/invitations/{token}/accept", response_model=BandResponse)
async def accept_invitation(
    token: str,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> BandResponse:
    require_complete_profile(user)
    invitation = await invitation_for_token(session, token, lock=True)
    band = await session.get(Band, invitation.band_id, with_for_update=True)
    if band is None or band.archived_at is not None:
        raise BandAPIError("band_unavailable", "This Band is not accepting members.", 409)
    member_count = await session.scalar(
        select(func.count(BandMembership.id)).where(
            BandMembership.band_id == band.id,
            BandMembership.status == MembershipStatus.active,
        )
    )
    if (member_count or 0) >= MAX_BAND_MEMBERS:
        raise BandAPIError("member_limit", "This Band has reached its member limit.", 409)
    membership = await session.scalar(
        select(BandMembership).where(
            BandMembership.band_id == band.id, BandMembership.user_id == user.id
        )
    )
    if membership is None:
        membership = BandMembership(
            band_id=band.id, user_id=user.id, role=BandRole.member
        )
        session.add(membership)
    else:
        membership.status = MembershipStatus.active
        membership.role = BandRole.member
        membership.ended_at = None
    invitation.status = InvitationStatus.accepted
    invitation.accepted_by_user_id = user.id
    invitation.accepted_at = utcnow()
    await session.commit()
    return await band_response(session, band, user.id)


@router.delete("/bands/{band_id}/invitations/{invitation_id}", status_code=204)
async def revoke_invitation(
    band_id: uuid.UUID,
    invitation_id: uuid.UUID,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> Response:
    await editable_membership(session, band_id, user.id, {BandRole.owner, BandRole.admin})
    invitation = await session.get(BandInvitation, invitation_id)
    if invitation is None or invitation.band_id != band_id:
        raise BandAPIError("invitation_not_found", "This invitation no longer exists.", 404)
    invitation.status = InvitationStatus.revoked
    await session.commit()
    return Response(status_code=204)
