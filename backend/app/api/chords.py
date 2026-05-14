from fastapi import APIRouter, HTTPException

from app.models.schemas import ChordRequest, ChordResponse
from app.theory.chords import generate_chord

router = APIRouter()


@router.post("/chords", response_model=ChordResponse)
def create_chord(request: ChordRequest):
    try:
        notes = generate_chord(request.root, request.chord_type)

        return ChordResponse(
            root=request.root,
            chord_type=request.chord_type,
            notes=notes
        )

    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error))