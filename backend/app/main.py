from contextlib import asynccontextmanager

import asyncio

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from app.api.chat import router as chat_router
from app.api.scales import router as scales_router
from app.api.chords import router as chords_router
from app.api.intervals import router as intervals_router
from app.api.progressions import router as progressions_router
from app.band.api import router as band_router
from app.band.database import create_development_tables
from app.band.database import engine
from app.band.errors import BandAPIError, band_error_handler
from app.band.queue import band_queue
from app.public_pages import router as public_pages_router
from app.progress.api import router as progress_router
from sqlalchemy import text


@asynccontextmanager
async def lifespan(_: FastAPI):
    await create_development_tables()
    yield


app = FastAPI(
    title="Music Theory AI",
    description="An AI-powered music theory tutor API",
    version="0.12",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


app.include_router(chat_router)
app.include_router(scales_router)
app.include_router(chords_router)
app.include_router(intervals_router)
app.include_router(progressions_router)
app.include_router(band_router)
app.include_router(progress_router)
app.include_router(public_pages_router)
app.add_exception_handler(BandAPIError, band_error_handler)

@app.get("/")
def root():
    return {"message": "Music Theory AI API is running"}


@app.get("/health/live")
def live_health():
    return {"status": "ok"}


@app.get("/health/ready")
async def readiness():
    try:
        async with engine.connect() as connection:
            await connection.execute(text("SELECT 1"))
        await asyncio.to_thread(band_queue.redis.ping)
    except Exception as exc:
        raise HTTPException(status_code=503, detail="dependencies unavailable") from exc
    return {"status": "ready", "postgres": "ok", "redis": "ok"}
