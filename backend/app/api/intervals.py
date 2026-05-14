from fastapi import APIRouter, HTTPException

from app.models.schemas import IntervalRequest, IntervalResponse
from app.theory.intervals import calculate_interval

router = APIRouter()


@router.post("/intervals", response_model=IntervalResponse)
def get_interval(request: IntervalRequest):
    try:
        result = calculate_interval(request.note1, request.note2)
        return IntervalResponse(**result)

    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error))