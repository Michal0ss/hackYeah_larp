from fastapi import APIRouter

from app.routers import account, catalog, coach, config, plans, system, texts
from app.schemas.api import ErrorEnvelope

# Documented on every /v1 route so clients can generate the error type.
ERROR_RESPONSES: dict[int | str, dict] = {
    401: {"model": ErrorEnvelope, "description": "Missing or invalid app token."},
    422: {"model": ErrorEnvelope, "description": "Invalid request."},
    429: {"model": ErrorEnvelope, "description": "Rate limit exceeded (see Retry-After)."},
}

api_v1 = APIRouter(prefix="/v1", responses=ERROR_RESPONSES)
for module in (catalog, config, plans, coach, texts, account):
    api_v1.include_router(module.router)

__all__ = ["api_v1", "system"]
