from fastapi import Request
from fastapi.responses import JSONResponse


class BandAPIError(Exception):
    def __init__(
        self, code: str, message: str, status_code: int = 400, field: str | None = None
    ):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status_code = status_code
        self.field = field


async def band_error_handler(_: Request, error: BandAPIError) -> JSONResponse:
    detail: dict[str, str] = {"code": error.code, "message": error.message}
    if error.field:
        detail["field"] = error.field
    return JSONResponse(status_code=error.status_code, content={"detail": detail})
