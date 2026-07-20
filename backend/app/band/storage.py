import asyncio
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

from app.band.errors import BandAPIError
from app.config.settings import settings


@dataclass(frozen=True)
class StoredObject:
    byte_size: int
    content_type: str
    checksum: str | None


class R2Storage:
    def _client(self):
        if not settings.r2_configured:
            raise BandAPIError(
                "storage_not_configured", "Private media storage is not configured yet.", 503
            )
        return boto3.client(
            "s3",
            endpoint_url=settings.r2_endpoint,
            aws_access_key_id=settings.r2_access_key_id,
            aws_secret_access_key=settings.r2_secret_access_key,
            region_name="auto",
            config=Config(signature_version="s3v4"),
        )

    async def upload_url(self, key: str, content_type: str) -> tuple[str, datetime]:
        expires_at = datetime.now(timezone.utc) + timedelta(hours=1)
        try:
            url = await asyncio.to_thread(
                self._client().generate_presigned_url,
                "put_object",
                Params={
                    "Bucket": settings.r2_bucket_name,
                    "Key": key,
                    "ContentType": content_type,
                },
                ExpiresIn=3600,
            )
        except (BotoCoreError, ClientError) as exc:
            raise BandAPIError("storage_unavailable", "Media storage is unavailable.", 503) from exc
        return url, expires_at

    async def access_url(self, key: str) -> tuple[str, datetime]:
        expires_at = datetime.now(timezone.utc) + timedelta(minutes=10)
        try:
            url = await asyncio.to_thread(
                self._client().generate_presigned_url,
                "get_object",
                Params={"Bucket": settings.r2_bucket_name, "Key": key},
                ExpiresIn=600,
            )
        except (BotoCoreError, ClientError) as exc:
            raise BandAPIError("storage_unavailable", "Media storage is unavailable.", 503) from exc
        return url, expires_at

    async def head(self, key: str) -> StoredObject:
        try:
            response = await asyncio.to_thread(
                self._client().head_object,
                Bucket=settings.r2_bucket_name,
                Key=key,
            )
        except (BotoCoreError, ClientError) as exc:
            raise BandAPIError("upload_missing", "The uploaded file was not found.", 409) from exc
        return StoredObject(
            byte_size=int(response["ContentLength"]),
            content_type=response.get("ContentType", "application/octet-stream"),
            checksum=response.get("ChecksumSHA256") or response.get("ETag"),
        )

    async def delete(self, key: str) -> None:
        if not settings.r2_configured:
            return
        await asyncio.to_thread(
            self._client().delete_object,
            Bucket=settings.r2_bucket_name,
            Key=key,
        )


storage = R2Storage()
