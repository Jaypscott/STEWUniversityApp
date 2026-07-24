import logging
import threading

from redis import Redis
from rq import Queue, Retry

from app.config.settings import settings


logger = logging.getLogger(__name__)


class BandQueue:
    def __init__(self) -> None:
        self._redis: Redis | None = None

    @property
    def redis(self) -> Redis:
        if self._redis is None:
            self._redis = Redis.from_url(settings.redis_url)
        return self._redis

    def enqueue(self, queue_name: str, function: str, *args, **kwargs) -> bool:
        if settings.band_inline_jobs:
            module_name, name = function.rsplit(".", 1)
            module = __import__(module_name, fromlist=[name])
            target = getattr(module, name)
            # Endpoint handlers already run an event loop while worker entrypoints
            # use asyncio.run(). A thread preserves the worker boundary in local mode.
            threading.Thread(
                target=target, args=args, kwargs=kwargs, daemon=True
            ).start()
            return True
        try:
            options = {}
            if queue_name in {"media", "notifications"}:
                options["retry"] = Retry(max=5, interval=[10, 30, 120, 600, 1800])
            Queue(queue_name, connection=self.redis).enqueue(
                function, *args, **kwargs, **options
            )
            return True
        except Exception:
            logger.exception("Could not enqueue Band job", extra={"job": function})
            return False


band_queue = BandQueue()
