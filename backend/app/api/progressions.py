from fastapi import APIRouter, HTTPException

from app.models.schemas import ProgressionRequest, ProgressionResponse
from app.theory.progressions import generate_progression

router = APIRouter()


@router.post("/progressions", response_model=ProgressionResponse)
def create_progression(request: ProgressionRequest):
    try:
        result = generate_progression(
            request.key,
            request.scale_type,
            request.style
        )

        return ProgressionResponse(**result)

    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error))