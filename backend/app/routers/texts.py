from fastapi import APIRouter, Depends

from app.ai.gateway import AIGateway
from app.config import Settings
from app.deps import get_gateway, get_settings
from app.schemas.api import RecommendationTextRequest, RecommendationTextResponse
from app.security import rate_limited
from app.services.text_service import recommendation_text

router = APIRouter(prefix="/texts", tags=["texts"])
guard = rate_limited("texts", lambda s: s.rate_limit_texts_per_minute)


@router.post(
    "/recommendation",
    response_model=RecommendationTextResponse,
    operation_id="recommendationText",
    summary="Friendly wording for today's recommendation",
    description=(
        "The decision is made on the phone; this only rewrites the text. The result is safety-checked and falls "
        "back to a template text (`source = template`) with a warning, never an error. Warnings: "
        "`ai_unavailable`, `ai_text_rejected`, `ai_mock`."
    ),
)
async def recommendation(
    body: RecommendationTextRequest,
    gateway: AIGateway = Depends(get_gateway),
    settings: Settings = Depends(get_settings),
    _=Depends(guard),
) -> RecommendationTextResponse:
    return await recommendation_text(body.recommendation, gateway, settings)
