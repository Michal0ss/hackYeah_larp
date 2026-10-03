"""Plan generation: the model proposes, the server validates, a template is the safety net.

profile -> prompt -> model (structured output) -> convert -> validate -> plan (source "ai")
                              |  any failure or timeout          |  any problem
                              +----------------> template plan (source "template") + warning
"""

import asyncio
from collections.abc import Callable
from datetime import datetime
from uuid import UUID, uuid4

from pydantic import ValidationError

from app.ai.gateway import AIGateway, AIUnavailable
from app.ai.prompts import plan_prompts
from app.config import Settings
from app.content.store import ContentStore
from app.logging_setup import get_logger
from app.schemas.api import PlanGenerateResponse
from app.schemas.base import CamelModel
from app.schemas.domain import PlannedExercise, PlannedSession, TrainingPlan, UserProfile
from app.services.plan_builder import build_template_plan, now_utc
from app.services.plan_validator import validate_plan
from app.services.safety import sanitize_free_text

log = get_logger("plans")


# What the model is asked to produce. Deliberately loose (no numeric limits): the validator, not the schema,
# decides, so a slightly-off plan is rejected with a precise reason instead of failing inside the SDK.


class DraftExercise(CamelModel):
    exercise_id: str
    sets: int
    reps_min: int
    reps_max: int
    rest_seconds: int


class DraftSession(CamelModel):
    weekday: int
    title: str
    exercises: list[DraftExercise]


class PlanDraft(CamelModel):
    sessions: list[DraftSession]


def draft_to_plan(
    draft: PlanDraft,
    content: ContentStore,
    *,
    now: datetime,
    new_id: Callable[[], UUID] = uuid4,
) -> TrainingPlan:
    """Server-owned fields (ids, dates, source, tempo) are never taken from the model."""
    sessions: list[PlannedSession] = []
    for index, session in enumerate(sorted(draft.sessions, key=lambda s: s.weekday), start=1):
        exercises = []
        for exercise in session.exercises:
            low, high = sorted((exercise.reps_min, exercise.reps_max))
            known = content.by_id.get(exercise.exercise_id)
            exercises.append(
                PlannedExercise(
                    exercise_id=exercise.exercise_id,
                    sets=exercise.sets,
                    reps_min=low,
                    reps_max=high,
                    rest_seconds=exercise.rest_seconds,
                    tempo=known.default_tempo if known else None,
                )
            )
        sessions.append(
            PlannedSession(
                id=new_id(),
                weekday=session.weekday,
                title=sanitize_free_text(session.title, 40) or f"Trening {index}",
                exercises=exercises,
            )
        )
    return TrainingPlan(created_at=now, source="ai", sessions=sessions)


async def generate_plan(
    profile: UserProfile,
    content: ContentStore,
    gateway: AIGateway,
    settings: Settings,
    *,
    now: datetime | None = None,
    new_id: Callable[[], UUID] = uuid4,
) -> PlanGenerateResponse:
    stamp = now or now_utc()

    def from_template(*warnings: str) -> PlanGenerateResponse:
        notes = list(warnings)
        if profile.avoid.strip():
            # The template cannot read free text; say so instead of pretending it was applied.
            notes.append("avoid_text_not_applied")
        return PlanGenerateResponse(
            plan=build_template_plan(profile, content, now=stamp, new_id=new_id), warnings=notes
        )

    if gateway.mode == "mock":
        return from_template("ai_mock")

    system, user = plan_prompts(profile, content)
    try:
        draft = await asyncio.wait_for(
            gateway.complete_structured(
                kind="plan",
                model=settings.plan_model,
                system=system,
                user=user,
                schema=PlanDraft,
                max_tokens=settings.plan_max_tokens,
            ),
            timeout=settings.plan_deadline_seconds,
        )
    except TimeoutError:
        log.warning("plan_fallback", extra={"reason": "deadline"})
        return from_template("ai_unavailable")
    except AIUnavailable as exc:
        log.warning("plan_fallback", extra={"reason": exc.reason})
        return from_template("ai_unavailable")

    try:
        plan = draft_to_plan(draft, content, now=stamp, new_id=new_id)
    except ValidationError:
        log.warning("plan_rejected", extra={"problems": ["invalid_values"]})
        return from_template("ai_invalid_plan")
    problems = validate_plan(plan, profile, content)
    if problems:
        log.warning("plan_rejected", extra={"problems": problems})
        return from_template("ai_invalid_plan")
    return PlanGenerateResponse(plan=plan, warnings=[])
