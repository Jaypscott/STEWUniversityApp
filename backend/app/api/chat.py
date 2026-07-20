from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Request, Response, status
from app.models.schemas import ChatRequest, ChatResponse
from app.ai.client import ask_music_theory_ai
from app.rate_limit import RateLimitUnavailable, rate_limiter

router = APIRouter()

@router.post("/chat", response_model=ChatResponse)
def chat(payload: ChatRequest, request: Request, response: Response):
    client_ip = request.client.host if request.client else "unknown"
    try:
        quota = rate_limiter.check(payload.installation_id, client_ip)
    except RateLimitUnavailable as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc

    reset_at = datetime.fromtimestamp(quota.reset_at, timezone.utc)
    response.headers["X-RateLimit-Limit"] = str(quota.limit)
    response.headers["X-RateLimit-Remaining"] = str(quota.remaining)
    response.headers["X-RateLimit-Reset"] = str(quota.reset_at)
    if not quota.allowed:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail={
                "message": "AI usage limit reached. Please try again later.",
                "remaining": quota.remaining,
                "limit": quota.limit,
                "reset_at": reset_at.isoformat(),
            },
            headers={"Retry-After": str(quota.retry_after)},
        )

    ai_response = ask_music_theory_ai(payload.message, payload.mode, payload.history)

    return ChatResponse(
        response=ai_response,
        remaining=quota.remaining,
        limit=quota.limit,
        reset_at=reset_at,
    )
