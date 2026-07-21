import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, Response
from sqlalchemy import delete, func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.band.content import validate_text
from app.band.database import get_session
from app.band.errors import BandAPIError
from app.band.models import (
    AppleIdentity,
    AuthSession,
    Band,
    DeviceRegistration,
    MembershipStatus,
    User,
    UserBlock,
    utcnow,
)
from app.band.schemas import (
    AccountDeleteRequest,
    AppleAuthRequest,
    AuthTokens,
    DeviceRequest,
    ProfileUpdate,
    RefreshRequest,
    UserResponse,
)
from app.band.security import (
    apple_identity_provider,
    create_session_tokens,
    current_user,
    decrypt_secret,
    encrypt_secret,
    hash_token,
    rotate_refresh_token,
)
from app.band.service import profile_complete, require_complete_profile
from app.config.settings import settings
from app.progress.service import get_or_create_profile


router = APIRouter(prefix="/v1", tags=["Band authentication"])


def user_response(user: User) -> UserResponse:
    return UserResponse(
        id=user.id,
        username=user.username,
        display_name=user.display_name,
        is_platform_admin=user.is_platform_admin,
        profile_complete=profile_complete(user),
        terms_url=settings.terms_url,
        privacy_url=settings.privacy_url,
        support_url=settings.support_url,
    )


@router.post("/auth/apple", response_model=AuthTokens)
async def authenticate_with_apple(
    body: AppleAuthRequest, session: AsyncSession = Depends(get_session)
) -> AuthTokens:
    claims = apple_identity_provider.verify_identity_token(body.identity_token, body.nonce)
    exchange = await apple_identity_provider.exchange_code(body.authorization_code)
    identity = await session.scalar(
        select(AppleIdentity).where(AppleIdentity.subject == claims.subject)
    )
    if identity:
        user = await session.get(User, identity.user_id)
    else:
        user = User(
            display_name=body.display_name.strip() if body.display_name else None,
            is_platform_admin=claims.subject in settings.platform_admin_apple_subjects,
        )
        session.add(user)
        await session.flush()
        identity = AppleIdentity(
            user_id=user.id,
            subject=claims.subject,
            email=claims.email,
        )
        session.add(identity)
    if user is None or user.deletion_requested_at is not None:
        raise BandAPIError("account_unavailable", "This account is unavailable.", 403)
    if user.suspended_at is not None:
        raise BandAPIError("account_suspended", "This account is suspended.", 403)
    user.is_platform_admin = claims.subject in settings.platform_admin_apple_subjects
    if exchange.refresh_token:
        identity.encrypted_refresh_token = encrypt_secret(exchange.refresh_token)
    await get_or_create_profile(session, user.id)
    access, refresh, access_exp, refresh_exp, _ = await create_session_tokens(
        session, user.id
    )
    await session.commit()
    return AuthTokens(
        access_token=access,
        refresh_token=refresh,
        access_expires_at=access_exp,
        refresh_expires_at=refresh_exp,
        profile_required=not profile_complete(user),
    )


@router.post("/auth/refresh", response_model=AuthTokens)
async def refresh_authentication(
    body: RefreshRequest, session: AsyncSession = Depends(get_session)
) -> AuthTokens:
    access, refresh, access_exp, refresh_exp = await rotate_refresh_token(
        session, body.refresh_token
    )
    return AuthTokens(
        access_token=access,
        refresh_token=refresh,
        access_expires_at=access_exp,
        refresh_expires_at=refresh_exp,
        profile_required=False,
    )


@router.post("/auth/logout", status_code=204)
async def logout(
    body: RefreshRequest, session: AsyncSession = Depends(get_session)
) -> Response:
    await session.execute(
        update(AuthSession)
        .where(AuthSession.refresh_token_hash == hash_token(body.refresh_token))
        .values(revoked_at=utcnow())
    )
    await session.commit()
    return Response(status_code=204)


@router.get("/me", response_model=UserResponse)
async def get_me(user: User = Depends(current_user)) -> UserResponse:
    return user_response(user)


@router.patch("/me/profile", response_model=UserResponse)
async def update_profile(
    body: ProfileUpdate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> UserResponse:
    current_year = datetime.now().year
    if current_year - body.birth_year < 13:
        raise BandAPIError(
            "age_restricted", "Band is available to musicians age 13 and older.", 403
        )
    if not body.accepts_terms:
        raise BandAPIError(
            "terms_required", "Accept the Terms and Privacy Policy to use Band.", field="accepts_terms"
        )
    user.username = validate_text(body.username, field="username", maximum=30)
    user.display_name = validate_text(body.display_name, field="display_name", maximum=60)
    user.age_gate_passed_at = utcnow()
    user.terms_accepted_at = utcnow()
    user.terms_version = settings.terms_version
    try:
        await session.commit()
    except IntegrityError as exc:
        await session.rollback()
        raise BandAPIError(
            "username_unavailable", "That username is already taken.", 409, "username"
        ) from exc
    return user_response(user)


@router.put("/me/devices", status_code=204)
async def register_device(
    body: DeviceRequest,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> Response:
    require_complete_profile(user)
    registration = None
    if body.installation_id is not None:
        registration = await session.scalar(
            select(DeviceRegistration).where(
                DeviceRegistration.user_id == user.id,
                DeviceRegistration.installation_id == body.installation_id,
            )
        )
    if registration is None:
        registration = await session.scalar(
            select(DeviceRegistration).where(
                DeviceRegistration.user_id == user.id,
                DeviceRegistration.device_token == body.device_token,
            )
        )
    if registration is None:
        registration = DeviceRegistration(
            user_id=user.id,
            device_token=body.device_token,
            installation_id=body.installation_id,
            environment=body.environment,
        )
        session.add(registration)
    registration.device_token = body.device_token
    registration.installation_id = body.installation_id
    registration.environment = body.environment
    registration.notifications_enabled = body.notifications_enabled
    registration.updated_at = utcnow()
    await session.commit()
    return Response(status_code=204)


@router.delete("/me/devices/{device_token}", status_code=204)
async def unregister_device(
    device_token: str,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> Response:
    await session.execute(
        delete(DeviceRegistration).where(
            DeviceRegistration.user_id == user.id,
            DeviceRegistration.device_token == device_token,
        )
    )
    await session.commit()
    return Response(status_code=204)


@router.get("/me/blocked-users", response_model=list[UserResponse])
async def blocked_users(
    user: User = Depends(current_user), session: AsyncSession = Depends(get_session)
) -> list[UserResponse]:
    users = list(
        (
            await session.scalars(
                select(User)
                .join(UserBlock, UserBlock.blocked_user_id == User.id)
                .where(UserBlock.blocker_user_id == user.id)
            )
        ).all()
    )
    return [user_response(item) for item in users]


@router.put("/me/blocked-users/{blocked_user_id}", status_code=204)
async def block_user(
    blocked_user_id: uuid.UUID,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> Response:
    if blocked_user_id == user.id:
        raise BandAPIError("invalid_block", "You can’t block yourself.")
    if await session.get(User, blocked_user_id) is None:
        raise BandAPIError("user_not_found", "This user no longer exists.", 404)
    existing = await session.scalar(
        select(UserBlock).where(
            UserBlock.blocker_user_id == user.id,
            UserBlock.blocked_user_id == blocked_user_id,
        )
    )
    if existing is None:
        session.add(UserBlock(blocker_user_id=user.id, blocked_user_id=blocked_user_id))
        await session.commit()
    return Response(status_code=204)


@router.delete("/me/blocked-users/{blocked_user_id}", status_code=204)
async def unblock_user(
    blocked_user_id: uuid.UUID,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> Response:
    await session.execute(
        delete(UserBlock).where(
            UserBlock.blocker_user_id == user.id,
            UserBlock.blocked_user_id == blocked_user_id,
        )
    )
    await session.commit()
    return Response(status_code=204)


@router.delete("/me/account", status_code=204)
async def delete_account(
    body: AccountDeleteRequest,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> Response:
    claims = apple_identity_provider.verify_identity_token(body.identity_token, body.nonce)
    identity = await session.get(AppleIdentity, user.id)
    if identity is None or claims.subject != identity.subject:
        raise BandAPIError("reauthentication_failed", "Please sign in again.", 401)
    owned_count = await session.scalar(
        select(func.count(Band.id)).where(Band.owner_user_id == user.id)
    )
    if owned_count:
        raise BandAPIError(
            "owned_bands_require_action",
            "Transfer or delete your owned Bands before deleting your account.",
            409,
        )
    if identity.encrypted_refresh_token:
        await apple_identity_provider.revoke(
            decrypt_secret(identity.encrypted_refresh_token)
        )
    user.deletion_requested_at = utcnow()
    await session.execute(
        update(AuthSession).where(AuthSession.user_id == user.id).values(revoked_at=utcnow())
    )
    await session.execute(
        update(DeviceRegistration)
        .where(DeviceRegistration.user_id == user.id)
        .values(notifications_enabled=False)
    )
    await session.commit()
    # Media and authored content are deleted by the account deletion worker. Access
    # is revoked immediately so a delayed worker cannot leave an active account.
    from app.band.queue import band_queue

    band_queue.enqueue("media", "app.band.account_jobs.delete_account_job", str(user.id))
    return Response(status_code=204)
