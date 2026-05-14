import os
from dotenv import load_dotenv
from openai import OpenAI

from app.ai.prompts import SYSTEM_PROMPT

load_dotenv()

client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))


def ask_music_theory_ai(user_message: str) -> str:
    response = client.responses.create(
        model="gpt-4o-mini",
        instructions=SYSTEM_PROMPT,
        input=user_message,
    )

    return response.output_text