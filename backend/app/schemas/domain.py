"""Domain types shared with the app. Keep them in sync with Packages/Core/Sources/Contracts/*.swift.

Changing a field here is an API change: update the Swift type, bump nothing silently, regenerate openapi.json.
"""

from typing import Literal
from uuid import UUID

from pydantic import Field, model_validator

from app.schemas.base import CamelModel, UtcDateTime

Goal = Literal["strength", "physique", "fitness", "returnToMovement"]
Level = Literal["beginner", "intermediate"]
Equipment = Literal["none", "dumbbells", "gym"]
GearItem = Literal["none", "dumbbells", "kettlebell", "gym"]
MovementTag = Literal["jumps", "deepLunges", "overheadPress", "barbellDeadlift", "deepSquats", "loadedPushups"]
Pattern = Literal["squat", "hinge", "lunge", "push", "pull", "core", "cardio"]
PlanSource = Literal["ai", "template"]
SessionStatus = Literal["planned", "done", "adapted", "skipped"]
Decision = Literal["train", "adapt", "rest"]
FactorSource = Literal["sleep", "hrv", "restingHeartRate", "checkIn", "technique"]

EQUIPMENT_RANK: dict[str, int] = {"none": 0, "dumbbells": 1, "gym": 2}
LEVEL_RANK: dict[str, int] = {"beginner": 0, "intermediate": 1}


class TempoSpec(CamelModel):
    """Seconds per phase: eccentric - pause at the bottom - concentric - pause at the top."""

    eccentric: float = Field(ge=0, le=30)
    bottom_pause: float = Field(ge=0, le=30)
    concentric: float = Field(ge=0, le=30)
    top_pause: float = Field(default=0, ge=0, le=30)


class UserProfile(CamelModel):
    """What the app may send about the user. It never contains the health history (that stays on the phone)."""

    goal: Goal
    level: Level
    days_per_week: int = Field(ge=2, le=5)
    session_minutes: int = Field(ge=15, le=120)
    equipment: Equipment
    # Free text typed by the user. Treated as data, truncated and sanitised before it reaches a prompt.
    avoid: str = Field(default="", max_length=300)
    gear: list[GearItem] = Field(default_factory=list, max_length=4)
    avoid_tags: list[MovementTag] = Field(default_factory=list, max_length=6)
    easy_start: bool = False


class ExerciseItem(CamelModel):
    id: str
    name: str
    muscle_group: str
    equipment: Equipment
    level: Level
    summary: str
    video_url: str | None = Field(default=None, alias="videoURL")
    substitute_ids: list[str] = Field(default_factory=list)
    supports_analysis: bool = False
    default_tempo: TempoSpec | None = None
    # Server-side extras (the app ignores them until it needs them):
    pattern: Pattern
    movement_tags: list[MovementTag] = Field(default_factory=list)
    # True when reps are seconds (plank, marching).
    timed: bool = False


class PlannedExercise(CamelModel):
    exercise_id: str
    sets: int = Field(ge=1, le=10)
    reps_min: int = Field(ge=1, le=200)
    reps_max: int = Field(ge=1, le=200)
    rest_seconds: int = Field(ge=0, le=600)
    tempo: TempoSpec | None = None

    @model_validator(mode="after")
    def _reps_order(self) -> "PlannedExercise":
        if self.reps_max < self.reps_min:
            raise ValueError("repsMax must be >= repsMin")
        return self


class PlannedSession(CamelModel):
    id: UUID
    weekday: int = Field(ge=1, le=7)
    title: str = Field(max_length=60)
    exercises: list[PlannedExercise]
    status: SessionStatus = "planned"
    adaptation_note: str | None = None


class TrainingPlan(CamelModel):
    created_at: UtcDateTime
    source: PlanSource
    sessions: list[PlannedSession]


class RecommendationFactor(CamelModel):
    source: FactorSource
    text: str = Field(max_length=200)
    is_negative: bool


class CareFlag(CamelModel):
    reason: str = Field(max_length=300)


class DailyRecommendation(CamelModel):
    date: UtcDateTime
    decision: Decision
    headline: str = Field(max_length=120)
    factors: list[RecommendationFactor] = Field(max_length=10)
    suggested_action: str = Field(max_length=300)
    care_flag: CareFlag | None = None
    is_simulated: bool = False
