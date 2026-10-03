"""Checks a plan against the user's profile and the catalog.

Used on every plan the model produced: the model proposes, the server decides. Problems are short codes
(never user text), so they can be logged and returned as warnings.
"""

from app.content.store import ContentStore
from app.schemas.domain import EQUIPMENT_RANK, LEVEL_RANK, TrainingPlan, UserProfile
from app.services.plan_builder import effective_level

MAX_EXERCISES_PER_SESSION = 8
MAX_SETS = 6
MAX_REPS = 30
TIMED_REPS = (10, 120)


def validate_plan(plan: TrainingPlan, profile: UserProfile, content: ContentStore) -> list[str]:
    problems: list[str] = []
    scheme = content.templates.goals[profile.goal]
    max_level = LEVEL_RANK[effective_level(profile, scheme)]
    max_equipment = EQUIPMENT_RANK[profile.equipment]
    blocked = set(profile.avoid_tags)

    if len(plan.sessions) != profile.days_per_week:
        problems.append("wrong_session_count")
    weekdays = [session.weekday for session in plan.sessions]
    if len(set(weekdays)) != len(weekdays):
        problems.append("duplicate_weekday")

    for session in plan.sessions:
        if not 1 <= len(session.exercises) <= MAX_EXERCISES_PER_SESSION:
            problems.append("bad_exercise_count")
        ids = [exercise.exercise_id for exercise in session.exercises]
        if len(set(ids)) != len(ids):
            problems.append("repeated_exercise")
        for planned in session.exercises:
            item = content.by_id.get(planned.exercise_id)
            if item is None:
                problems.append("unknown_exercise")
                continue
            if set(item.movement_tags) & blocked:
                problems.append("avoided_movement")
            if EQUIPMENT_RANK[item.equipment] > max_equipment:
                problems.append("equipment_not_available")
            if LEVEL_RANK[item.level] > max_level:
                problems.append("level_too_high")
            if planned.sets > MAX_SETS:
                problems.append("too_many_sets")
            if item.timed:
                if not TIMED_REPS[0] <= planned.reps_min <= planned.reps_max <= TIMED_REPS[1]:
                    problems.append("bad_duration")
            elif planned.reps_max > MAX_REPS:
                problems.append("too_many_reps")
    return sorted(set(problems))
