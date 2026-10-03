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


# Default models per provider. Fast model for chat and texts, the stronger one for plans.
PROVIDER_MODELS: dict[str, dict[str, str]] = {
    "gemini": {"coach": "gemini-2.5-flash", "plan": "gemini-2.5-flash", "text": "gemini-2.5-flash"},
    "anthropic": {"coach": "claude-haiku-4-5", "plan": "claude-sonnet-5-5", "text": "claude-haiku-4-5"},
}


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

    # --- AI
    # auto: the real model when a key is set (Gemini first, then Anthropic), otherwise the offline mock.
    ai_mode: Literal["auto", "mock", "anthropic", "gemini"] = "auto"
    gemini_api_key: SecretStr | None = Field(
        default=None,
        validation_alias=AliasChoices("FORMA_GEMINI_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY"),
    )
    anthropic_api_key: SecretStr | None = Field(
        default=None, validation_alias=AliasChoices("FORMA_ANTHROPIC_API_KEY", "ANTHROPIC_API_KEY")
    )
    # Empty = the default of the active provider (PROVIDER_MODELS). Set FORMA_COACH_MODEL etc. to override.
    coach_model: str = ""
    plan_model: str = ""
    text_model: str = ""
    coach_max_tokens: int = 1024
    plan_max_tokens: int = 4096
    text_max_tokens: int = 600
    ai_timeout_seconds: float = 60.0
    # Hard caps on what a user waits for before we answer from templates instead.
    plan_deadline_seconds: float = 45.0
    text_deadline_seconds: float = 15.0

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

    @field_validator("app_tokens", "cors_origins", mode="before")
    @classmethod
    def _parse_lists(cls, value: object) -> object:
        return _split_list(value)

    @model_validator(mode="after")
    def _check_consistency(self) -> "Settings":
        if self.env == "prod" and not self.app_tokens:
            raise ValueError("FORMA_APP_TOKENS is required when FORMA_ENV=prod")
        if self.ai_mode == "anthropic" and not self.has_anthropic_key:
            raise ValueError("FORMA_AI_MODE=anthropic needs ANTHROPIC_API_KEY")
        if self.ai_mode == "gemini" and not self.has_gemini_key:
            raise ValueError("FORMA_AI_MODE=gemini needs GEMINI_API_KEY")
        defaults = PROVIDER_MODELS.get(self.effective_ai_mode, PROVIDER_MODELS["anthropic"])
        self.coach_model = self.coach_model or defaults["coach"]
        self.plan_model = self.plan_model or defaults["plan"]
        self.text_model = self.text_model or defaults["text"]
        return self

    @property
    def has_gemini_key(self) -> bool:
        return bool(self.gemini_api_key and self.gemini_api_key.get_secret_value().strip())

    @property
    def has_anthropic_key(self) -> bool:
        return bool(self.anthropic_api_key and self.anthropic_api_key.get_secret_value().strip())

    @property
    def has_api_key(self) -> bool:
        return self.has_gemini_key or self.has_anthropic_key

    @property
    def effective_ai_mode(self) -> Literal["mock", "anthropic", "gemini"]:
        if self.ai_mode != "auto":
            return self.ai_mode
        if self.has_gemini_key:
            return "gemini"
        if self.has_anthropic_key:
            return "anthropic"
        return "mock"

    @property
    def auth_enabled(self) -> bool:
        return bool(self.app_tokens)
