"""Request and response bodies of the HTTP API."""

from typing import Annotated, Any, Literal
from uuid import UUID

from pydantic import Field

from app.schemas.base import CamelModel
from app.schemas.domain import DailyRecommendation, ExerciseItem, PlanSource, SessionStatus, TrainingPlan, UserProfile

# --- errors (every non-2xx response has this shape, see app/errors.py)


class ErrorField(CamelModel):
    path: str
    message: str


class ErrorBody(CamelModel):
    code: str
    message: str
    request_id: str | None = None
    # Only for code "invalid_request": which fields are wrong. Values are never echoed back.
    fields: list[ErrorField] | None = None


class ErrorEnvelope(CamelModel):
    error: ErrorBody


# --- system


class HealthResponse(CamelModel):
    status: Literal["ok"]
    version: str
    env: str
    ai_mode: Literal["mock", "gemini"]
    content_version: str


# --- content


class CatalogResponse(CamelModel):
    version: str
    exercises: list[ExerciseItem]


class ConfigResponse(CamelModel):
    """Remote configuration. Each section is owned by one person (see content/README.md)."""

    version: str
    scoring: dict[str, Any]
    insights: dict[str, Any]
    tempo: dict[str, Any]


# --- plans


class PlanGenerateRequest(CamelModel):
    profile: UserProfile


class PlanGenerateResponse(CamelModel):
    plan: TrainingPlan
    # Short machine-readable notes, e.g. "ai_unavailable" when the template plan was used instead.
    warnings: list[str] = Field(default_factory=list)


# --- coach chat


class TextBlock(CamelModel):
    type: Literal["text"] = "text"
    text: str = Field(max_length=4000)


class ToolUseBlock(CamelModel):
    type: Literal["tool_use"] = "tool_use"
    id: str = Field(max_length=100)
    name: str = Field(max_length=64)
    input: dict[str, Any] = Field(default_factory=dict)


class ToolResultBlock(CamelModel):
    type: Literal["tool_result"] = "tool_result"
    tool_use_id: str = Field(max_length=100)
    # JSON or text produced by the app. The app builds it from local data (summaries only).
    content: str = Field(max_length=20_000)
    is_error: bool = False


ContentBlock = Annotated[TextBlock | ToolUseBlock | ToolResultBlock, Field(discriminator="type")]


class ChatMessage(CamelModel):
    role: Literal["user", "assistant"]
    content: str | list[ContentBlock]


class Consent(CamelModel):
    """The user's consent to pass health data (as summaries) to the model. Mirrors DataConsent in the app."""

    health: bool = False


WorkoutScreen = Literal["today", "plan", "liveSet", "setSummary", "rest", "sessionFeedback", "analysis"]
FindingSeverity = Literal["good", "minor", "major"]
FramingRating = Literal["good", "fair", "poor"]


class FindingDigest(CamelModel):
    """A technique or tempo finding of a set without its long description."""

    id: str = Field(max_length=60)
    title: str = Field(max_length=80)
    severity: FindingSeverity
    reps_affected: int = Field(ge=0, le=200)
    reps_total: int = Field(ge=0, le=200)


class SetDigest(CamelModel):
    """Numbers from one finished set (Swift: SetDigest). Never poses, frames or video."""

    set_index: int = Field(ge=1, le=20)
    reps: int = Field(ge=0, le=200)
    full_range_reps: int = Field(ge=0, le=200)
    technique_score: int | None = Field(default=None, ge=0, le=100)
    tempo_score: int = Field(ge=0, le=100)
    # Written like "3-1-2-0".
    target_tempo: str = Field(max_length=20)
    average_descent_seconds: float = Field(ge=0, le=60)
    average_ascent_seconds: float = Field(ge=0, le=60)
    framing: FramingRating
    findings: list[FindingDigest] = Field(default_factory=list, max_length=12)


class WorkoutContext(CamelModel):
    """Where in the workout the question was asked (Swift: WorkoutContext).

    Training data only, no health data: pain and effort reach the model only through a consent-gated tool.
    Every text in it is data, not an instruction.
    """

    screen: WorkoutScreen
    session_id: UUID | None = None
    exercise_id: str | None = Field(default=None, max_length=60)
    set_index: int | None = Field(default=None, ge=1, le=20)
    total_sets: int | None = Field(default=None, ge=1, le=20)
    last_set: SetDigest | None = None


class ExerciseDigest(CamelModel):
    """One planned exercise as the coach sees it. Only the id: the server knows the name from the catalog."""

    exercise_id: str = Field(max_length=60)
    sets: int = Field(ge=1, le=10)
    reps_min: int = Field(ge=1, le=200)
    reps_max: int = Field(ge=1, le=200)
    rest_seconds: int = Field(ge=0, le=600)
    tempo: str | None = Field(default=None, max_length=20)


class SessionDigest(CamelModel):
    """A planned session, compact. `adaptation_note` is built from health signals (sleep, HRV, ...), so the app
    sends it only with the user's consent, and sends the session as planned (not adjusted) without it."""

    weekday: int = Field(ge=1, le=7)
    title: str = Field(max_length=80)
    status: SessionStatus
    adaptation_note: str | None = Field(default=None, max_length=300)
    exercises: list[ExerciseDigest] = Field(default_factory=list, max_length=12)


class TechniqueDigest(CamelModel):
    """The latest technique analysis: numbers and findings, never poses or video."""

    exercise_id: str = Field(max_length=60)
    days_ago: int = Field(ge=0, le=3650)
    score: int = Field(ge=0, le=100)
    findings: list[FindingDigest] = Field(default_factory=list, max_length=6)
    substitute_exercise_id: str | None = Field(default=None, max_length=60)
    is_simulated: bool = False


class TrainingSnapshot(CamelModel):
    """What the coach should know without asking: the plan and the last technique result.

    Training data, not health data, so it travels without the health consent (see the notes on `SessionDigest`).
    Every text in it is data, not an instruction.
    """

    # ISO weekday of the request (1 = Monday).
    today: int = Field(ge=1, le=7)
    plan_source: PlanSource | None = None
    # Today's session, or the next planned one when `next_session_is_today` is false.
    next_session: SessionDigest | None = None
    next_session_is_today: bool = True
    week: list[SessionDigest] = Field(default_factory=list, max_length=7)
    last_technique: TechniqueDigest | None = None


class CoachContext(CamelModel):
    profile: UserProfile
    today_recommendation: DailyRecommendation | None = None
    snapshot: TrainingSnapshot | None = None
    workout: WorkoutContext | None = None


class CoachChatRequest(CamelModel):
    messages: list[ChatMessage] = Field(min_length=1)
    context: CoachContext | None = None
    consent: Consent = Field(default_factory=Consent)
    # true: Server-Sent Events. false: one JSON response (handy for curl and tests).
    stream: bool = True


class ToolUseOut(CamelModel):
    id: str
    name: str
    input: dict[str, Any]


class Usage(CamelModel):
    input_tokens: int = 0
    output_tokens: int = 0


class CoachChatResponse(CamelModel):
    text: str
    tool_uses: list[ToolUseOut] = Field(default_factory=list)
    stop_reason: str | None = None
    usage: Usage = Field(default_factory=Usage)


# --- texts


class RecommendationTextRequest(CamelModel):
    recommendation: DailyRecommendation


class RecommendationTextResponse(CamelModel):
    headline: str
    explanation: str
    source: Literal["ai", "template"]
    warnings: list[str] = Field(default_factory=list)
