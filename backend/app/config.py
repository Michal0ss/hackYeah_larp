"""Settings, read from environment variables (prefix FORMA_) and an optional .env file.

Secrets (the model API key, app tokens) live only here, never in the repository.
"""

from pathlib import Path
from typing import Annotated, Literal

from pydantic import AliasChoices, Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict

# backend/app/config.py -> repository root is two levels above the `app` package.
REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONTENT_DIR = REPO_ROOT / "content"


# Default models. A model that is retired or out of quota is skipped for the next one (see app/ai/gemini.py).
# Quotas are per model, so the chain also stretches a small quota. Check what a key can use with
# `python evals/run_ai_evals.py --list-models`.
DEFAULT_MODEL = "gemini-3.5-flash"
DEFAULT_FALLBACK_MODELS = ["gemini-3-flash-preview", "gemini-3.5-flash-lite", "gemini-3.1-flash-lite"]


def _split_list(value: object) -> object:
    """Accepts "a,b c" as well as a real list."""
    if isinstance(value, str):
        return [item for item in value.replace(",", " ").split() if item]
    return value


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="FORMA_", env_file=".env", extra="ignore")

    # --- environment
    env: Literal["dev", "test", "prod"] = "dev"
    log_level: str = "INFO"

    # --- AI (Google Gemini)
    # auto: the real model when GEMINI_API_KEY is set, otherwise the offline mock (works without any key).
    ai_mode: Literal["auto", "mock", "gemini"] = "auto"
    gemini_api_key: SecretStr | None = Field(
        default=None,
        validation_alias=AliasChoices("FORMA_GEMINI_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY"),
    )
    coach_model: str = DEFAULT_MODEL
    plan_model: str = DEFAULT_MODEL
    text_model: str = DEFAULT_MODEL
    # Tried in this order when the model above is unavailable (comma-separated in FORMA_FALLBACK_MODELS).
    fallback_models: Annotated[list[str], NoDecode] = DEFAULT_FALLBACK_MODELS
    # Thinking tokens count against these limits, so they are generous.
    coach_max_tokens: int = 2048
    plan_max_tokens: int = 8192
    text_max_tokens: int = 1500
    # One request to one model. A chain of models is bounded by the deadlines below.
    ai_timeout_seconds: float = 20.0
    # Hard caps on what a user waits for before we answer from templates instead.
    plan_deadline_seconds: float = 50.0
    text_deadline_seconds: float = 20.0

    # --- access
    # Comma-separated bearer tokens the app may use. Empty = auth off (dev only; required in prod).
    app_tokens: Annotated[list[str], NoDecode] = []
    cors_origins: Annotated[list[str], NoDecode] = []

    # --- limits (per device, per minute)
    rate_limit_chat_per_minute: int = 20
    rate_limit_plans_per_minute: int = 6
    rate_limit_texts_per_minute: int = 20
    rate_limit_default_per_minute: int = 120
    max_request_bytes: int = 256 * 1024
    max_chat_messages: int = 40
    max_chat_chars: int = 40_000

    # --- content
    content_dir: Path = DEFAULT_CONTENT_DIR

    @field_validator("app_tokens", "cors_origins", "fallback_models", mode="before")
    @classmethod
    def _parse_lists(cls, value: object) -> object:
        return _split_list(value)

    @model_validator(mode="after")
    def _check_consistency(self) -> "Settings":
        if self.env == "prod" and not self.app_tokens:
            raise ValueError("FORMA_APP_TOKENS is required when FORMA_ENV=prod")
        if self.ai_mode == "gemini" and not self.has_api_key:
            raise ValueError("FORMA_AI_MODE=gemini needs GEMINI_API_KEY")
        return self

    @property
    def has_api_key(self) -> bool:
        return bool(self.gemini_api_key and self.gemini_api_key.get_secret_value().strip())

    @property
    def effective_ai_mode(self) -> Literal["mock", "gemini"]:
        if self.ai_mode == "mock":
            return "mock"
        return "gemini" if self.has_api_key else "mock"

    @property
    def auth_enabled(self) -> bool:
        return bool(self.app_tokens)
