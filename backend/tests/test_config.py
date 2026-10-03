"""Settings: Gemini only, mock without a key."""

import pytest
from pydantic import ValidationError

from app.ai.gateway import MockGateway
from app.ai.gemini import GeminiGateway
from app.config import DEFAULT_FALLBACK_MODELS, DEFAULT_MODEL, Settings
from app.main import build_gateway


@pytest.fixture(autouse=True)
def no_keys_from_the_shell(monkeypatch):
    for name in ("GEMINI_API_KEY", "GOOGLE_API_KEY", "FORMA_GEMINI_API_KEY", "FORMA_AI_MODE", "FORMA_FALLBACK_MODELS"):
        monkeypatch.delenv(name, raising=False)


def settings(**values) -> Settings:
    return Settings(_env_file=None, **values)


def test_without_a_key_the_app_runs_on_the_mock():
    s = settings()
    assert s.effective_ai_mode == "mock" and isinstance(build_gateway(s), MockGateway)


def test_with_a_key_the_app_uses_gemini():
    s = settings(gemini_api_key="k")
    assert s.effective_ai_mode == "gemini"
    gateway = build_gateway(s)
    assert isinstance(gateway, GeminiGateway) and gateway.mode == "gemini"


def test_blank_key_counts_as_no_key():
    assert settings(gemini_api_key="   ").effective_ai_mode == "mock"


def test_forcing_the_mock_wins_over_a_key():
    assert settings(gemini_api_key="k", ai_mode="mock").effective_ai_mode == "mock"


def test_forcing_gemini_without_a_key_fails_at_startup():
    with pytest.raises(ValidationError):
        settings(ai_mode="gemini")


def test_other_providers_are_gone():
    with pytest.raises(ValidationError):
        settings(ai_mode="anthropic")


def test_key_is_read_from_the_environment(monkeypatch):
    monkeypatch.setenv("GEMINI_API_KEY", "from-env")
    assert settings().gemini_api_key.get_secret_value() == "from-env"


def test_models_and_fallbacks_have_defaults_and_can_be_overridden(monkeypatch):
    s = settings()
    assert (s.coach_model, s.plan_model, s.text_model) == (DEFAULT_MODEL,) * 3
    assert s.fallback_models == DEFAULT_FALLBACK_MODELS
    monkeypatch.setenv("FORMA_FALLBACK_MODELS", "a, b c")
    assert settings().fallback_models == ["a", "b", "c"]


def test_limits_leave_room_for_thinking_tokens():
    s = settings()
    assert s.coach_max_tokens >= 2048 and s.plan_max_tokens >= 8192 and s.text_max_tokens >= 1500
    assert s.ai_timeout_seconds < s.plan_deadline_seconds
