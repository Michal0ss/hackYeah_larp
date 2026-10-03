from fastapi import APIRouter, Depends, Request

from app import __version__
from app.config import Settings
from app.content.store import ContentStore
from app.deps import get_content, get_settings
from app.schemas.api import HealthResponse

router = APIRouter(tags=["system"])


@router.get(
    "/health",
    response_model=HealthResponse,
    operation_id="getHealth",
    summary="Liveness and basic facts (no auth)",
)
def health(
    request: Request,
    settings: Settings = Depends(get_settings),
    content: ContentStore = Depends(get_content),
) -> HealthResponse:
    return HealthResponse(
        status="ok",
        version=__version__,
        env=settings.env,
        ai_mode=request.app.state.gateway.mode,
        content_version=content.content_version,
    )
