import hashlib
import time
from dataclasses import dataclass

from redis import Redis
from redis.exceptions import RedisError

from app.config.settings import settings


class RateLimitUnavailable(RuntimeError):
    pass


@dataclass(frozen=True)
class RateLimitResult:
    allowed: bool
    remaining: int
    limit: int
    reset_at: int
    retry_after: int


_SLIDING_WINDOW_SCRIPT = """
local key = KEYS[1]
local now = tonumber(ARGV[1])
local window = tonumber(ARGV[2])
local limit = tonumber(ARGV[3])
local member = ARGV[4]
redis.call('ZREMRANGEBYSCORE', key, '-inf', now - window)
local count = redis.call('ZCARD', key)
if count >= limit then
  local oldest = redis.call('ZRANGE', key, 0, 0, 'WITHSCORES')
  local reset = math.floor(tonumber(oldest[2]) + window)
  return {0, 0, reset}
end
redis.call('ZADD', key, now, member)
redis.call('EXPIRE', key, math.ceil(window))
local oldest = redis.call('ZRANGE', key, 0, 0, 'WITHSCORES')
local reset = math.floor(tonumber(oldest[2]) + window)
return {1, limit - count - 1, reset}
"""


class RedisRateLimiter:
    def __init__(self, redis_client: Redis | None = None):
        self.redis = redis_client or Redis.from_url(
            settings.redis_url, decode_responses=True, socket_connect_timeout=2
        )

    @staticmethod
    def _digest(value: str) -> str:
        return hashlib.sha256(value.encode("utf-8")).hexdigest()

    def _check_window(self, key: str, limit: int, window: int, now: float, member: str):
        return self.redis.eval(
            _SLIDING_WINDOW_SCRIPT, 1, key, now, window, limit, member
        )

    def check(self, installation_id: str | None, ip_address: str) -> RateLimitResult:
        now = time.time()
        identity = installation_id or f"ip:{ip_address}"
        install_hash = self._digest(identity)
        ip_hash = self._digest(ip_address)
        member = f"{now:.6f}:{hashlib.sha256(f'{identity}:{time.time_ns()}'.encode()).hexdigest()[:16]}"

        try:
            burst = self._check_window(
                f"ai:burst:install:{install_hash}", settings.ai_burst_limit,
                settings.ai_burst_window_seconds, now, member,
            )
            if not int(burst[0]):
                reset = int(burst[2])
                return RateLimitResult(False, 0, settings.ai_burst_limit, reset, max(1, reset - int(now)))

            ip_burst = self._check_window(
                f"ai:burst:ip:{ip_hash}", settings.ai_burst_limit,
                settings.ai_burst_window_seconds, now, member,
            )
            if not int(ip_burst[0]):
                reset = int(ip_burst[2])
                return RateLimitResult(False, 0, settings.ai_burst_limit, reset, max(1, reset - int(now)))

            daily = self._check_window(
                f"ai:daily:{install_hash}", settings.ai_daily_limit,
                settings.ai_daily_window_seconds, now, member,
            )
        except RedisError as exc:
            raise RateLimitUnavailable("AI usage controls are temporarily unavailable") from exc

        reset = int(daily[2])
        return RateLimitResult(
            bool(int(daily[0])), int(daily[1]), settings.ai_daily_limit,
            reset, max(1, reset - int(now)) if not int(daily[0]) else 0,
        )


rate_limiter = RedisRateLimiter()
