from fastapi import APIRouter, Depends, Request, Response

from app.content.store import ContentStore
from app.deps import get_content
from app.etag import make_etag, not_modified
from app.schemas.api import ConfigResponse
from app.security import rate_limited

router = APIRouter(tags=["content"])
guard = rate_limited("default", lambda s: s.rate_limit_default_per_minute)


@router.get(
    "/config",
    response_model=ConfigResponse,
    operation_id="getConfig",
    responses={304: {"description": "Not modified (If-None-Match matched)."}},
    summary="Remote configuration (scoring, insights, tempo)",
)
def get_config(
    request: Request,
    response: Response,
    content: ContentStore = Depends(get_content),
    _=Depends(guard),
):
    etag = make_etag(content.config_version)
    if (cached := not_modified(request, etag)) is not None:
        return cached
    response.headers["ETag"] = etag
    response.headers["Cache-Control"] = "no-cache"
    return ConfigResponse(
        version=content.config_version,
        scoring=content.config["scoring"],
        insights=content.config["insights"],
        tempo=content.config["tempo"],
    )
