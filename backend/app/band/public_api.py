from fastapi import APIRouter
from fastapi.responses import HTMLResponse, JSONResponse

from app.config.settings import settings


router = APIRouter(tags=["Band public configuration"])


@router.get("/v1/band-config")
async def band_config() -> dict:
    return {
        "terms_url": settings.terms_url,
        "privacy_url": settings.privacy_url,
        "support_url": settings.support_url,
        "safety_contact_url": settings.safety_contact_url,
        "minimum_age": 13,
        "limits": {
            "owned_bands": 3,
            "members_per_band": 20,
            "band_bytes": 2 * 1024 * 1024 * 1024,
            "audio_video_bytes": 100 * 1024 * 1024,
            "image_bytes": 20 * 1024 * 1024,
        },
    }


@router.get("/.well-known/apple-app-site-association", include_in_schema=False)
async def apple_app_site_association() -> JSONResponse:
    app_id = f"{settings.apple_team_id}.{settings.apple_bundle_id}"
    return JSONResponse(
        content={
            "applinks": {
                "details": [
                    {"appIDs": [app_id], "components": [{"/": "/band/invite/*"}]}
                ]
            }
        },
        media_type="application/json",
    )


@router.get("/band/invite/{token}", response_class=HTMLResponse, include_in_schema=False)
async def invitation_landing(token: str) -> str:
    escaped = token.replace('"', "")
    deep_link = f"stewuniversity://band/invite/{escaped}"
    return f"""<!doctype html>
<html><head><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">
<title>Join a Band</title></head>
<body style=\"font-family:-apple-system;padding:48px;max-width:560px;margin:auto\">
<h1>Join this Band in STEWUniversity</h1>
<p>Sign in to STEWUniversity to review and accept the invitation.</p>
<p><a href=\"{deep_link}\">Open STEWUniversity</a></p>
</body></html>"""
