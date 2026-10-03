"""Short, friendly copy for the daily recommendation.

The decision itself (train / adapt / rest) is made by the rules on the phone. The model only phrases it, and
its output is checked: if anything looks off, the app's own text is returned instead.
"""

import asyncio

from pydantic import Field

from app.ai.gateway import AIGateway, AIUnavailable
from app.ai.prompts import text_prompts
from app.config import Settings
from app.logging_setup import get_logger
from app.schemas.api import RecommendationTextResponse
from app.schemas.base import CamelModel
from app.schemas.domain import DailyRecommendation
from app.services.safety import check_generated_text, sanitize_free_text

log = get_logger("texts")


class AiText(CamelModel):
    headline: str = Field(description="Up to 80 characters, no trailing period.")
    explanation: str = Field(description="Two or three sentences, up to 350 characters.")


def template_text(rec: DailyRecommendation, *warnings: str) -> RecommendationTextResponse:
    parts = [factor.text.strip().rstrip(".") + "." for factor in rec.factors[:3] if factor.text.strip()]
    parts.append(rec.suggested_action.strip())
    if rec.care_flag:
        parts.append("Jeśli to się powtarza, warto skonsultować się z fizjoterapeutą lub lekarzem.")
    return RecommendationTextResponse(
        headline=rec.headline,
        explanation=" ".join(part for part in parts if part)[:600],
        source="template",
        warnings=list(warnings),
    )


async def recommendation_text(
    rec: DailyRecommendation, gateway: AIGateway, settings: Settings
) -> RecommendationTextResponse:
    if gateway.mode == "mock":
        return template_text(rec, "ai_mock")

    system, user = text_prompts(rec)
    try:
        generated = await asyncio.wait_for(
            gateway.complete_structured(
                kind="text",
                model=settings.text_model,
                system=system,
                user=user,
                schema=AiText,
                max_tokens=settings.text_max_tokens,
            ),
            timeout=settings.text_deadline_seconds,
        )
    except TimeoutError:
        log.warning("text_fallback", extra={"reason": "deadline"})
        return template_text(rec, "ai_unavailable")
    except AIUnavailable as exc:
        log.warning("text_fallback", extra={"reason": exc.reason})
        return template_text(rec, "ai_unavailable")

    headline = sanitize_free_text(generated.headline, 120)
    explanation = sanitize_free_text(generated.explanation, 600)
    problems = check_generated_text(headline, explanation)
    if rec.care_flag and not any(word in explanation.lower() for word in ("fizjoterap", "lekarz")):
        problems.append("missing_care_hint")
    if problems:
        log.warning("text_rejected", extra={"problems": problems})
        return template_text(rec, "ai_text_rejected")
    return RecommendationTextResponse(headline=headline, explanation=explanation, source="ai", warnings=[])
