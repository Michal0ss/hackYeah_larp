"""Request and response bodies of the HTTP API."""

from typing import Annotated, Any, Literal

from pydantic import Field

from app.schemas.base import CamelModel
from app.schemas.domain import DailyRecommendation, ExerciseItem, TrainingPlan, UserProfile

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
    ai_mode: Literal["mock", "anthropic", "gemini"]
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


class CoachContext(CamelModel):
    profile: UserProfile
    today_recommendation: DailyRecommendation | None = None


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
