from fastapi import APIRouter, HTTPException

from app.models.schemas import ScaleRequest, ScaleResponse
from app.theory.scales import generate_scale

router = APIRouter()


@router.post("/scales", response_model=ScaleResponse)
def create_scale(request: ScaleRequest):
    try:
        notes = generate_scale(request.root, request.scale_type)

        return ScaleResponse(
            root=request.root,
            scale_type=request.scale_type,
            notes=notes
        )

    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error))