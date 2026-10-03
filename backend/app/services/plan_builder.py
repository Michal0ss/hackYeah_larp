"""Deterministic template plan.

It is the fallback when the model is unavailable or returns an invalid plan, and the only generator in mock
mode. All rules come from `content/plan_templates.json` (Maciek), so tuning a plan needs no code change.
"""

from collections.abc import Callable
from datetime import UTC, datetime
from uuid import UUID, uuid4

from app.content.store import ContentStore, GoalScheme
from app.schemas.domain import (
    EQUIPMENT_RANK,
    LEVEL_RANK,
    ExerciseItem,
    Level,
    PlannedExercise,
    PlannedSession,
    TrainingPlan,
    UserProfile,
)


def now_utc() -> datetime:
    return datetime.now(UTC).replace(microsecond=0)


def effective_level(profile: UserProfile, scheme: GoalScheme) -> Level:
    """The easiest of: the user's level, the level forced by the goal, and beginner for an easy start."""
    levels: list[Level] = [profile.level]
    if scheme.force_level:
        levels.append(scheme.force_level)
    if profile.easy_start:
        levels.append("beginner")
    return min(levels, key=lambda level: LEVEL_RANK[level])


def allowed_for(profile: UserProfile, content: ContentStore) -> list[ExerciseItem]:
    scheme = content.templates.goals[profile.goal]
    return content.allowed_exercises(profile.equipment, effective_level(profile, scheme), set(profile.avoid_tags))


def _pick(candidates: list[ExerciseItem], preference: str, occurrence: int, used: set[str]) -> ExerciseItem | None:
    pool = [exercise for exercise in candidates if exercise.id not in used]
    if not pool:
        return None
    ranks = [EQUIPMENT_RANK[exercise.equipment] for exercise in pool]
    target = max(ranks) if preference == "highest" else min(ranks)
    tier = [exercise for exercise, rank in zip(pool, ranks, strict=True) if rank == target]
    # Rotate inside the tier so repeated sessions of one kind (lower, lower B) are not identical.
    return tier[occurrence % len(tier)]


def build_template_plan(
    profile: UserProfile,
    content: ContentStore,
    *,
    now: datetime | None = None,
    new_id: Callable[[], UUID] = uuid4,
) -> TrainingPlan:
    templates = content.templates
    scheme = templates.goals[profile.goal]
    days = min(max(profile.days_per_week, 2), 5)
    allowed = allowed_for(profile, content)
    per_session = templates.exercises_for_minutes(profile.session_minutes)

    sessions: list[PlannedSession] = []
    seen_kinds: dict[str, int] = {}
    for weekday, kind in zip(templates.weekdays[days], templates.sessions_by_days[days], strict=True):
        occurrence = seen_kinds.get(kind, 0)
        seen_kinds[kind] = occurrence + 1
        blueprint = templates.blueprints[kind]

        slots = [slot for slot in blueprint.slots if slot not in scheme.drop_slots][:per_session]
        picked: list[ExerciseItem] = []
        used: set[str] = set()
        for slot in slots:
            exercise = _pick([e for e in allowed if e.pattern == slot], scheme.equipment_preference, occurrence, used)
            if exercise:
                picked.append(exercise)
                used.add(exercise.id)
        if not picked:
            # Everything for this session was filtered out: one gentle core exercise beats an empty day.
            fallback = _pick([e for e in allowed if e.pattern == "core"] or allowed, "lowest", 0, used)
            if fallback:
                picked.append(fallback)

        sessions.append(
            PlannedSession(
                id=new_id(),
                weekday=weekday,
                title=blueprint.title if occurrence == 0 else f"{blueprint.title} {chr(ord('A') + occurrence)}",
                exercises=[_prescribe(exercise, content, scheme, profile) for exercise in picked],
            )
        )
    return TrainingPlan(created_at=now or now_utc(), source="template", sessions=sessions)


def _prescribe(
    exercise: ExerciseItem, content: ContentStore, scheme: GoalScheme, profile: UserProfile
) -> PlannedExercise:
    if exercise.timed:
        timed = content.templates.timed_scheme
        sets, reps_min, reps_max, rest = (
            min(scheme.sets, 3),
            timed.reps_min,
            timed.reps_max,
            timed.rest_seconds,
        )
    else:
        sets, reps_min, reps_max, rest = scheme.sets, scheme.reps_min, scheme.reps_max, scheme.rest_seconds
    if profile.easy_start:
        sets = max(2, sets - 1)
    return PlannedExercise(
        exercise_id=exercise.id,
        sets=sets,
        reps_min=reps_min,
        reps_max=reps_max,
        rest_seconds=rest,
        tempo=exercise.default_tempo,
    )
