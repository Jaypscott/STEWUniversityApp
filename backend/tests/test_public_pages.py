from fastapi.testclient import TestClient

from app.config.settings import settings
from app.main import app


client = TestClient(app)


def test_public_legal_and_support_pages_are_available():
    expected = {
        "/legal/terms": "Terms of Use",
        "/legal/privacy": "Privacy Policy",
        "/support": "stewuniversitysupport@gmail.com",
        "/safety": "Safety Center",
    }

    for path, text in expected.items():
        response = client.get(path)
        assert response.status_code == 200
        assert response.headers["content-type"].startswith("text/html")
        assert response.headers["x-content-type-options"] == "nosniff"
        assert text in response.text


def test_band_config_uses_public_production_pages():
    response = client.get("/v1/band-config")

    assert response.status_code == 200
    assert response.json() == {
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


def test_openapi_includes_public_pages():
    paths = app.openapi()["paths"]
    assert "/legal/terms" in paths
    assert "/legal/privacy" in paths
    assert "/support" in paths
    assert "/safety" in paths
