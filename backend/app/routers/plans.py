from fastapi import APIRouter, Depends

from app.ai.gateway import AIGateway
from app.config import Settings
from app.content.store import ContentStore
from app.deps import get_content, get_gateway, get_settings
from app.schemas.api import PlanGenerateRequest, PlanGenerateResponse
from app.security import rate_limited
from app.services.plan_service import generate_plan

router = APIRouter(prefix="/plans", tags=["plans"])
guard = rate_limited("plans", lambda s: s.rate_limit_plans_per_minute)


@router.post(
    "/generate",
    response_model=PlanGenerateResponse,
    operation_id="generatePlan",
    summary="Generate a weekly plan for a profile",
    description=(
        "The model proposes a plan, the server validates it against the catalog and the profile. When the model is "
        "unavailable or its plan is invalid the response is a template plan (`plan.source = template`) with a "
        "warning, never an error. Warnings: `ai_unavailable`, `ai_invalid_plan`, `ai_mock`, "
        "`avoid_text_not_applied`."
    ),
)
async def generate(
    body: PlanGenerateRequest,
    content: ContentStore = Depends(get_content),
    gateway: AIGateway = Depends(get_gateway),
    settings: Settings = Depends(get_settings),
    _=Depends(guard),
) -> PlanGenerateResponse:
    return await generate_plan(body.profile, content, gateway, settings)
