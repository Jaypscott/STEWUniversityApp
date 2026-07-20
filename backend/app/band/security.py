from __future__ import annotations

import base64
import hashlib
import secrets
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

import httpx
import jwt
from cryptography.fernet import Fernet
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import PyJWKClient
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.band.database import get_session
from app.band.errors import BandAPIError
from app.band.models import AuthSession, User
from app.config.settings import settings


ACCESS_LIFETIME = timedelta(minutes=15)
REFRESH_LIFETIME = timedelta(days=30)
APPLE_ISSUER = "https://appleid.apple.com"
APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys"
APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token"
APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke"


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def as_utc(value: datetime) -> datetime:
    return value if value.tzinfo else value.replace(tzinfo=timezone.utc)


def hash_token(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def random_token() -> str:
    return secrets.token_urlsafe(48)


def encrypt_secret(value: str) -> str:
    configured = settings.apple_token_encryption_key.encode()
    key = configured or base64.urlsafe_b64encode(
        hashlib.sha256(settings.app_jwt_secret.encode()).digest()
    )
    return Fernet(key).encrypt(value.encode()).decode()


def decrypt_secret(value: str) -> str:
    configured = settings.apple_token_encryption_key.encode()
    key = configured or base64.urlsafe_b64encode(
        hashlib.sha256(settings.app_jwt_secret.encode()).digest()
    )
    return Fernet(key).decrypt(value.encode()).decode()


@dataclass(frozen=True)
class AppleClaims:
    subject: str
    email: str | None


@dataclass(frozen=True)
class AppleTokenExchange:
    refresh_token: str | None
    access_token: str | None


class AppleIdentityProvider:
    def __init__(self) -> None:
        self._keys = PyJWKClient(APPLE_KEYS_URL, cache_keys=True)

    def verify_identity_token(self, identity_token: str, raw_nonce: str) -> AppleClaims:
        try:
            signing_key = self._keys.get_signing_key_from_jwt(identity_token)
            claims = jwt.decode(
                identity_token,
                signing_key.key,
                algorithms=["RS256"],
                audience=settings.apple_bundle_id,
                issuer=APPLE_ISSUER,
            )
        except Exception as exc:
            raise BandAPIError(
                "invalid_apple_credential", "Apple could not verify this sign-in.", 401
            ) from exc

        expected_nonce = hashlib.sha256(raw_nonce.encode()).hexdigest()
        if not secrets.compare_digest(str(claims.get("nonce", "")), expected_nonce):
            raise BandAPIError("invalid_nonce", "The sign-in request expired. Try again.", 401)
        subject = str(claims.get("sub", ""))
        if not subject:
            raise BandAPIError("invalid_apple_credential", "Apple user ID is missing.", 401)
        return AppleClaims(subject=subject, email=claims.get("email"))

    def _client_secret(self) -> str:
        if not all(
            (settings.apple_team_id, settings.apple_key_id, settings.apple_private_key)
        ):
            raise BandAPIError(
                "apple_not_configured", "Sign in with Apple is not configured yet.", 503
            )
        issued = now_utc()
        return jwt.encode(
            {
                "iss": settings.apple_team_id,
                "iat": issued,
                "exp": issued + timedelta(minutes=5),
                "aud": APPLE_ISSUER,
                "sub": settings.apple_bundle_id,
            },
            settings.apple_private_key,
            algorithm="ES256",
            headers={"kid": settings.apple_key_id},
        )

    async def exchange_code(self, authorization_code: str) -> AppleTokenExchange:
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.post(
                APPLE_TOKEN_URL,
                data={
                    "client_id": settings.apple_bundle_id,
                    "client_secret": self._client_secret(),
                    "code": authorization_code,
                    "grant_type": "authorization_code",
                },
            )
        if response.status_code != 200:
            raise BandAPIError(
                "invalid_apple_code", "Apple could not complete this sign-in.", 401
            )
        payload = response.json()
        return AppleTokenExchange(
            refresh_token=payload.get("refresh_token"),
            access_token=payload.get("access_token"),
        )

    async def revoke(self, token: str) -> None:
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.post(
                APPLE_REVOKE_URL,
                data={
                    "client_id": settings.apple_bundle_id,
                    "client_secret": self._client_secret(),
                    "token": token,
                    "token_type_hint": "refresh_token",
                },
            )
        if response.status_code != 200:
            raise BandAPIError(
                "apple_revocation_failed",
                "Apple account access could not be revoked. Try again.",
                502,
            )


apple_identity_provider = AppleIdentityProvider()


def make_access_token(user_id: uuid.UUID, session_id: uuid.UUID) -> tuple[str, datetime]:
    expires = now_utc() + ACCESS_LIFETIME
    token = jwt.encode(
        {
            "sub": str(user_id),
            "sid": str(session_id),
            "type": "access",
            "iat": now_utc(),
            "exp": expires,
        },
        settings.app_jwt_secret,
        algorithm="HS256",
    )
    return token, expires


async def create_session_tokens(
    session: AsyncSession, user_id: uuid.UUID, family_id: uuid.UUID | None = None
) -> tuple[str, str, datetime, datetime, AuthSession]:
    raw_refresh = random_token()
    refresh_expires = now_utc() + REFRESH_LIFETIME
    record = AuthSession(
        user_id=user_id,
        family_id=family_id or uuid.uuid4(),
        refresh_token_hash=hash_token(raw_refresh),
        expires_at=refresh_expires,
    )
    session.add(record)
    await session.flush()
    access, access_expires = make_access_token(user_id, record.id)
    return access, raw_refresh, access_expires, refresh_expires, record


async def rotate_refresh_token(
    session: AsyncSession, raw_refresh: str
) -> tuple[str, str, datetime, datetime]:
    record = await session.scalar(
        select(AuthSession)
        .where(AuthSession.refresh_token_hash == hash_token(raw_refresh))
        .with_for_update()
    )
    if record is None:
        raise BandAPIError("invalid_refresh_token", "Please sign in again.", 401)
    if record.revoked_at is not None:
        await session.execute(
            update(AuthSession)
            .where(AuthSession.family_id == record.family_id)
            .values(revoked_at=now_utc())
        )
        await session.commit()
        raise BandAPIError("refresh_token_reused", "Please sign in again.", 401)
    if as_utc(record.expires_at) <= now_utc():
        raise BandAPIError("refresh_token_expired", "Please sign in again.", 401)

    access, refresh, access_exp, refresh_exp, replacement = await create_session_tokens(
        session, record.user_id, record.family_id
    )
    record.revoked_at = now_utc()
    record.replaced_by_id = replacement.id
    await session.commit()
    return access, refresh, access_exp, refresh_exp


bearer = HTTPBearer(auto_error=False)


async def current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    session: AsyncSession = Depends(get_session),
) -> User:
    if credentials is None:
        raise BandAPIError("authentication_required", "Sign in to use Band.", 401)
    try:
        claims = jwt.decode(
            credentials.credentials,
            settings.app_jwt_secret,
            algorithms=["HS256"],
            options={"require": ["exp", "sub", "sid"]},
        )
        if claims.get("type") != "access":
            raise ValueError("wrong token type")
        user_id = uuid.UUID(claims["sub"])
        session_id = uuid.UUID(claims["sid"])
    except Exception as exc:
        raise BandAPIError("invalid_access_token", "Please sign in again.", 401) from exc

    auth_session = await session.get(AuthSession, session_id)
    user = await session.get(User, user_id)
    if (
        auth_session is None
        or auth_session.revoked_at is not None
        or as_utc(auth_session.expires_at) <= now_utc()
        or user is None
        or user.deletion_requested_at is not None
    ):
        raise BandAPIError("invalid_access_token", "Please sign in again.", 401)
    if user.suspended_at is not None:
        raise BandAPIError("account_suspended", "This account is suspended.", 403)
    return user
