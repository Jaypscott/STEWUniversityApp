from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone

import httpx
import jwt

from app.band.models import DeviceRegistration
from app.config.settings import settings


@dataclass(frozen=True)
class APNsResponse:
    status_code: int
    body: str

    @property
    def succeeded(self) -> bool:
        return self.status_code == 200

    @property
    def token_is_invalid(self) -> bool:
        return self.status_code in {400, 410} and any(
            reason in self.body for reason in ("BadDeviceToken", "Unregistered")
        )


def provider_token() -> str:
    if not settings.apns_configured:
        raise RuntimeError("APNs is not configured")
    now = int(datetime.now(timezone.utc).timestamp())
    return jwt.encode(
        {"iss": settings.apple_team_id, "iat": now},
        settings.apns_private_key,
        algorithm="ES256",
        headers={"kid": settings.apns_key_id},
    )


async def send_apns(
    device: DeviceRegistration,
    payload: dict,
    *,
    push_type: str,
    priority: int,
    collapse_id: str | None = None,
) -> APNsResponse:
    host = (
        "https://api.push.apple.com"
        if device.environment == "production"
        else "https://api.sandbox.push.apple.com"
    )
    headers = {
        "authorization": f"bearer {provider_token()}",
        "apns-topic": settings.apple_bundle_id,
        "apns-push-type": push_type,
        "apns-priority": str(priority),
    }
    if collapse_id:
        headers["apns-collapse-id"] = collapse_id
    async with httpx.AsyncClient(http2=True, timeout=10) as client:
        response = await client.post(
            f"{host}/3/device/{device.device_token}", headers=headers, json=payload
        )
    return APNsResponse(response.status_code, response.text[:300])
