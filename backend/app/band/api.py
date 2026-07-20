from fastapi import APIRouter

from app.band.auth_api import router as auth_router
from app.band.bands_api import router as bands_router
from app.band.collaboration_api import router as collaboration_router
from app.band.media_api import router as media_router
from app.band.notifications_api import router as notifications_router
from app.band.public_api import router as public_router
from app.band.safety_api import router as safety_router


router = APIRouter()
router.include_router(auth_router)
router.include_router(bands_router)
router.include_router(collaboration_router)
router.include_router(media_router)
router.include_router(notifications_router)
router.include_router(safety_router)
router.include_router(public_router)
