from fastapi import APIRouter, Depends, Request, Response

from app.content.store import ContentStore
from app.deps import get_content
from app.etag import make_etag, not_modified
from app.schemas.api import CatalogResponse
from app.security import rate_limited

router = APIRouter(tags=["content"])
guard = rate_limited("default", lambda s: s.rate_limit_default_per_minute)


@router.get(
    "/catalog",
    response_model=CatalogResponse,
    operation_id="getCatalog",
    responses={304: {"description": "Not modified (If-None-Match matched)."}},
    summary="Exercise catalog",
)
def get_catalog(
    request: Request,
    response: Response,
    content: ContentStore = Depends(get_content),
    _=Depends(guard),
):
    etag = make_etag(content.catalog_version)
    if (cached := not_modified(request, etag)) is not None:
        return cached
    response.headers["ETag"] = etag
    response.headers["Cache-Control"] = "no-cache"
    return CatalogResponse(version=content.catalog_version, exercises=content.exercises)
