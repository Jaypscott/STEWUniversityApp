from urllib.parse import urlparse

from app.band.errors import BandAPIError
from app.config.settings import settings


def validate_text(value: str, *, field: str, maximum: int, allow_empty: bool = False) -> str:
    normalized = value.strip()
    if not normalized and not allow_empty:
        raise BandAPIError("invalid_text", "This field can’t be empty.", field=field)
    if len(normalized) > maximum:
        raise BandAPIError(
            "text_too_long", f"Use {maximum} characters or fewer.", field=field
        )
    folded = normalized.casefold()
    if any(term in folded for term in settings.objectionable_words):
        raise BandAPIError(
            "content_not_allowed",
            "This text can’t be shared. Please revise it and try again.",
            field=field,
        )
    return normalized


def validate_external_url(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = value.strip()
    parsed = urlparse(normalized)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise BandAPIError(
            "invalid_url", "Only complete HTTP or HTTPS links can be shared.", field="external_url"
        )
    if len(normalized) > 2048:
        raise BandAPIError("invalid_url", "This link is too long.", field="external_url")
    return normalized
