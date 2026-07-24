import os
from functools import lru_cache
from typing import Any

from app.ai.prompts import MODE_PROMPTS
from app.config.settings import settings
from app.models.schemas import ChatHistoryItem, ChatMode


@lru_cache(maxsize=1)
def _client() -> Any:
    # Importing the OpenAI SDK loads a large generated resource tree. Keep that
    # work off startup and non-AI commands such as migrations and backend tests.
    from openai import OpenAI

    return OpenAI(api_key=os.getenv("OPENAI_API_KEY"))


def ask_music_theory_ai(
    user_message: str,
    mode: ChatMode = ChatMode.general,
    history: list[ChatHistoryItem] | None = None,
) -> str:
    conversation = [
        {"role": item.role, "content": item.content}
        for item in (history or [])[-8:]
    ]
    conversation.append({"role": "user", "content": user_message})
    response = _client().responses.create(
        model="gpt-4o-mini",
        instructions=MODE_PROMPTS[mode.value],
        input=conversation,
        max_output_tokens=settings.ai_max_output_tokens,
    )

    return response.output_text
