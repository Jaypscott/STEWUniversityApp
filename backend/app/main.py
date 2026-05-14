from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.chat import router as chat_router
from app.api.scales import router as scales_router
from app.api.chords import router as chords_router
from app.api.intervals import router as intervals_router
from app.api.progressions import router as progressions_router


app = FastAPI(
     title="Music Theory AI",
    description="An AI-powered music theory tutor API",
    version="0.10"
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

@app.get("/")
def root():
    return {"message": "Music Theory AI API is running"}