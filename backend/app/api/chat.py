from fastapi import APIRouter
from app.models.schemas import ChatRequest, ChatResponse
from app.ai.client import ask_music_theory_ai

router = APIRouter()

@router.post("/chat", response_model=ChatResponse)
def chat(request: ChatRequest):
    ai_response = ask_music_theory_ai(request.message)

    return ChatResponse(response=ai_response)