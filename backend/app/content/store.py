"""Loads and validates the shared content (repo-level `content/`).

The server refuses to start on invalid content, so a bad edit in `content/` is caught by `make test` / CI
and never reaches the app. Versions are content hashes: nobody has to remember to bump a number.
"""

import hashlib
import json
from functools import cached_property
from pathlib import Path
from typing import Any

from pydantic import Field, ValidationError, model_validator

from app.schemas.base import CamelModel
from app.schemas.domain import EQUIPMENT_RANK, LEVEL_RANK, Equipment, ExerciseItem, Goal, Level, Pattern


class ContentError(Exception):
    """The content directory is missing, unreadable or inconsistent. `problems` are human-readable lines."""

    def __init__(self, problems: list[str]):
        super().__init__("; ".join(problems))
        self.problems = problems


# --- plan templates (content/plan_templates.json)


class Blueprint(CamelModel):
    title: str = Field(max_length=40)
    slots: list[Pattern] = Field(min_length=1)
    # The slots of a session of 90 minutes or more (see LONG_SESSION_MINUTES). Without it the normal slots are used.
    long_slots: list[Pattern] | None = None


# From this length of a session on, a blueprint's `long_slots` are used (more exercises than the normal slots hold).
LONG_SESSION_MINUTES = 90


class GoalScheme(CamelModel):
    sets: int = Field(ge=1, le=6)
    reps_min: int = Field(ge=1, le=30)
    reps_max: int = Field(ge=1, le=30)
    rest_seconds: int = Field(ge=0, le=300)
    drop_slots: list[Pattern] = Field(default_factory=list)
    equipment_preference: str = Field(pattern="^(highest|lowest)$")
    force_level: Level | None = None

    @model_validator(mode="after")
    def _reps_order(self) -> "GoalScheme":
        if self.reps_max < self.reps_min:
            raise ValueError("repsMax must be >= repsMin")
        return self


class TimedScheme(CamelModel):
    reps_min: int = Field(ge=5, le=120)
    reps_max: int = Field(ge=5, le=120)
    rest_seconds: int = Field(ge=0, le=300)


class PlanTemplates(CamelModel):
    version: int
    weekdays: dict[int, list[int]]
    sessions_by_days: dict[int, list[str]]
    blueprints: dict[str, Blueprint]
    exercises_per_session: dict[int, int]
    goals: dict[Goal, GoalScheme]
    timed_scheme: TimedScheme

    def exercises_for_minutes(self, minutes: int) -> int:
        """Largest configured duration that fits into `minutes` (the shortest one if none does)."""
        keys = sorted(self.exercises_per_session)
        fitting = [key for key in keys if key <= minutes]
        return self.exercises_per_session[fitting[-1] if fitting else keys[0]]


# --- store


def _read_json(path: Path, problems: list[str]) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        problems.append(f"{path.name}: file is missing")
    except (OSError, UnicodeDecodeError) as exc:
        problems.append(f"{path.name}: cannot be read ({type(exc).__name__})")
    except json.JSONDecodeError as exc:
        problems.append(f"{path.name}: invalid JSON (line {exc.lineno}, column {exc.colno})")
    return None


def _digest(*parts: Any) -> str:
    canonical = json.dumps(parts, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:12]


def _validation_lines(name: str, exc: ValidationError) -> list[str]:
    return [f"{name}: {'.'.join(str(p) for p in err['loc'])}: {err['msg']}" for err in exc.errors()]


class ContentStore:
    CONFIG_SECTIONS = ("scoring", "insights", "tempo")

    def __init__(
        self,
        exercises: list[ExerciseItem],
        templates: PlanTemplates,
        config: dict[str, dict[str, Any]],
        raw: dict[str, Any],
    ):
        self.exercises = exercises
        self.templates = templates
        self.config = config
        self._raw = raw

    @classmethod
    def load(cls, directory: Path) -> "ContentStore":
        problems: list[str] = []
        raw_catalog = _read_json(directory / "catalog.json", problems)
        raw_templates = _read_json(directory / "plan_templates.json", problems)
        config: dict[str, dict[str, Any]] = {}
        for section in cls.CONFIG_SECTIONS:
            value = _read_json(directory / "config" / f"{section}.json", problems)
            if value is not None and not isinstance(value, dict):
                problems.append(f"config/{section}.json: top level must be an object")
            elif value is not None:
                config[section] = value
        if problems:
            raise ContentError(problems)

        exercises: list[ExerciseItem] = []
        templates: PlanTemplates | None = None
        try:
            exercises = [ExerciseItem.model_validate(item) for item in raw_catalog["exercises"]]
        except (ValidationError, KeyError, TypeError) as exc:
            problems += (
                _validation_lines("catalog.json", exc)
                if isinstance(exc, ValidationError)
                else ['catalog.json: expected {"exercises": [...]}']
            )
        try:
            templates = PlanTemplates.model_validate(raw_templates)
        except ValidationError as exc:
            problems += _validation_lines("plan_templates.json", exc)
        if problems:
            raise ContentError(problems)

        assert templates is not None
        problems = cls._check_consistency(exercises, templates)
        if problems:
            raise ContentError(problems)
        return cls(exercises, templates, config, {"catalog": raw_catalog, "templates": raw_templates})

    @staticmethod
    def _check_consistency(exercises: list[ExerciseItem], templates: PlanTemplates) -> list[str]:
        problems: list[str] = []
        ids = [exercise.id for exercise in exercises]
        for duplicate in sorted({i for i in ids if ids.count(i) > 1}):
            problems.append(f"catalog.json: duplicate exercise id '{duplicate}'")
        known = set(ids)
        for exercise in exercises:
            for substitute in exercise.substitute_ids:
                if substitute not in known:
                    problems.append(f"catalog.json: '{exercise.id}' has unknown substitute '{substitute}'")
                elif substitute == exercise.id:
                    problems.append(f"catalog.json: '{exercise.id}' lists itself as a substitute")

        for days in (2, 3, 4, 5):
            weekdays = templates.weekdays.get(days)
            kinds = templates.sessions_by_days.get(days)
            if weekdays is None or kinds is None:
                problems.append(f"plan_templates.json: weekdays/sessionsByDays must define {days} days")
                continue
            if len(weekdays) != days or len(kinds) != days:
                problems.append(f"plan_templates.json: {days} days needs {days} weekdays and {days} sessions")
            if len(set(weekdays)) != len(weekdays) or any(not 1 <= day <= 7 for day in weekdays):
                problems.append(f"plan_templates.json: weekdays for {days} days must be distinct values 1-7")
            for kind in kinds:
                if kind not in templates.blueprints:
                    problems.append(f"plan_templates.json: unknown blueprint '{kind}'")
        if not templates.exercises_per_session:
            problems.append("plan_templates.json: exercisesPerSession is empty")
        for goal in ("strength", "physique", "fitness", "returnToMovement"):
            if goal not in templates.goals:
                problems.append(f"plan_templates.json: goals.{goal} is missing")

        # Every slot must be fillable for the most restricted user (beginner, no equipment), otherwise a
        # template plan could come out with holes.
        for name, blueprint in templates.blueprints.items():
            for pattern in [*blueprint.slots, *(blueprint.long_slots or [])]:
                if not any(e.pattern == pattern and e.level == "beginner" and e.equipment == "none" for e in exercises):
                    problems.append(
                        f"catalog.json: no beginner exercise without equipment for pattern '{pattern}' "
                        f"(used by blueprint '{name}')"
                    )
        return sorted(set(problems))

    # --- views

    @cached_property
    def by_id(self) -> dict[str, ExerciseItem]:
        return {exercise.id: exercise for exercise in self.exercises}

    @cached_property
    def catalog_version(self) -> str:
        return _digest(self._raw["catalog"])

    @cached_property
    def config_version(self) -> str:
        return _digest(self.config)

    @cached_property
    def content_version(self) -> str:
        return _digest(self._raw["catalog"], self._raw["templates"], self.config)

    def allowed_exercises(self, equipment: Equipment, level: Level, blocked_tags: set[str]) -> list[ExerciseItem]:
        """Catalog exercises a user can do: within their equipment and level, without avoided movements."""
        max_rank = EQUIPMENT_RANK[equipment]
        max_level = LEVEL_RANK[level]
        return [
            exercise
            for exercise in self.exercises
            if EQUIPMENT_RANK[exercise.equipment] <= max_rank
            and LEVEL_RANK[exercise.level] <= max_level
            and not (set(exercise.movement_tags) & blocked_tags)
        ]
