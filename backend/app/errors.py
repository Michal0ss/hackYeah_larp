"""One error envelope for every failure:

    {"error": {"code": "rate_limited", "message": "...", "requestId": "..."}}

`code` is stable and machine-readable (the app switches on it), `message` is for humans (Polish).
Unhandled exceptions become a 500 in RequestContextMiddleware (it knows the request id).
Validation errors list the offending fields but never echo the submitted values, because they can be
health data or chat text.
"""

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.logging_setup import get_logger, request_id_ctx

log = get_logger("errors")


class ApiError(Exception):
    def __init__(self, status_code: int, code: str, message: str, headers: dict[str, str] | None = None):
        super().__init__(code)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.headers = headers or {}


def error_payload(code: str, message: str, **extra: object) -> dict:
    return {"error": {"code": code, "message": message, "requestId": request_id_ctx.get(), **extra}}


_HTTP_CODES = {
    400: "bad_request",
    401: "unauthorized",
    403: "forbidden",
    404: "not_found",
    405: "method_not_allowed",
    413: "payload_too_large",
    429: "rate_limited",
}


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def _api_error(_: Request, exc: ApiError) -> JSONResponse:
        return JSONResponse(error_payload(exc.code, exc.message), status_code=exc.status_code, headers=exc.headers)

    @app.exception_handler(RequestValidationError)
    async def _validation_error(_: Request, exc: RequestValidationError) -> JSONResponse:
        fields = [
            {"path": ".".join(str(part) for part in err.get("loc", ())), "message": err.get("msg", "")}
            for err in exc.errors()
        ]
        return JSONResponse(
            error_payload("invalid_request", "Nieprawidłowe dane żądania.", fields=fields), status_code=422
        )

    @app.exception_handler(StarletteHTTPException)
    async def _http_error(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        code = _HTTP_CODES.get(exc.status_code, "http_error")
        message = exc.detail if isinstance(exc.detail, str) else "Błąd żądania."
        return JSONResponse(error_payload(code, message), status_code=exc.status_code, headers=exc.headers)
