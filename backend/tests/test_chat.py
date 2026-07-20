from datetime import datetime, timezone

from fastapi.testclient import TestClient

from app.main import app
from app.rate_limit import RateLimitResult


client = TestClient(app)


def test_legacy_message_body_remains_compatible(monkeypatch):
    monkeypatch.setattr(
        "app.api.chat.rate_limiter.check",
        lambda installation_id, ip: RateLimitResult(True, 19, 20, 2_000_000_000, 0),
    )
    monkeypatch.setattr("app.api.chat.ask_music_theory_ai", lambda message, mode, history: "C major")
    response = client.post("/chat", json={"message": "What is a major chord?"})
    assert response.status_code == 200
    assert response.json()["response"] == "C major"
    assert response.json()["remaining"] == 19


def test_rate_limit_returns_retry_metadata(monkeypatch):
    monkeypatch.setattr(
        "app.api.chat.rate_limiter.check",
        lambda installation_id, ip: RateLimitResult(False, 0, 20, 2_000_000_000, 120),
    )
    response = client.post(
        "/chat",
        json={"message": "Help", "mode": "songwriting", "installation_id": "1234567890abcdef"},
    )
    assert response.status_code == 429
    assert response.headers["retry-after"] == "120"
    assert response.json()["detail"]["remaining"] == 0


def test_rejects_oversized_message_before_ai_call():
    response = client.post("/chat", json={"message": "x" * 1201})
    assert response.status_code == 422
