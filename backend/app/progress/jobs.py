from __future__ import annotations

import asyncio
import logging
import uuid

from sqlalchemy import select

from app.band.apns import send_apns
from app.band.database import SessionFactory
from app.band.models import DeviceRegistration


logger = logging.getLogger(__name__)


def send_progress_invalidation_job(
    user_id: str, revision: int, origin_installation_id: str | None
) -> None:
    asyncio.run(
        _send_progress_invalidation(
            uuid.UUID(user_id),
            revision,
            uuid.UUID(origin_installation_id) if origin_installation_id else None,
        )
    )


async def _send_progress_invalidation(
    user_id: uuid.UUID,
    revision: int,
    origin_installation_id: uuid.UUID | None,
) -> None:
    async with SessionFactory() as session:
        query = select(DeviceRegistration).where(DeviceRegistration.user_id == user_id)
        if origin_installation_id is not None:
            query = query.where(
                (DeviceRegistration.installation_id.is_(None))
                | (DeviceRegistration.installation_id != origin_installation_id)
            )
        devices = list((await session.scalars(query)).all())
        retry_errors: list[str] = []
        for device in devices:
            try:
                response = await send_apns(
                    device,
                    {
                        "aps": {"content-available": 1},
                        "kind": "progress_updated",
                        "progress_revision": revision,
                    },
                    push_type="background",
                    priority=5,
                    collapse_id=f"progress-{user_id}",
                )
                if response.token_is_invalid:
                    await session.delete(device)
                elif not response.succeeded:
                    retry_errors.append(response.body or f"APNs {response.status_code}")
            except Exception as exc:
                retry_errors.append(str(exc)[:300])
        await session.commit()
        if retry_errors:
            logger.warning(
                "Progress invalidation push failed",
                extra={"user_id": str(user_id), "errors": retry_errors},
            )
            raise RuntimeError("; ".join(retry_errors[:3]))
