"""Shared test helpers: a fake Gemini client and an app wired to it. No network, no key."""

import asyncio
from types import SimpleNamespace
from typing import Any

import pytest
from fastapi.testclient import TestClient
from google.genai import errors as genai_errors
from google.genai import types

from app.ai.gemini import GeminiGateway
from app.config import Settings
from app.main import create_app

PRIMARY = "gemini-test-primary"
FALLBACKS = ["gemini-test-second", "gemini-test-third"]


def text_response(text: str, *, finish=types.FinishReason.STOP, usage=(100, 20)) -> types.GenerateContentResponse:
    return response([types.Part(text=text)], finish=finish, usage=usage)


def response(parts: list[types.Part], *, finish=types.FinishReason.STOP, usage=(100, 20)):
    return types.GenerateContentResponse(
        candidates=[types.Candidate(content=types.Content(role="model", parts=parts), finish_reason=finish)],
        usage_metadata=types.GenerateContentResponseUsageMetadata(
            prompt_token_count=usage[0], candidates_token_count=usage[1]
        ),
    )


def call_part(name: str, args: dict[str, Any] | None = None, signature: bytes | None = None) -> types.Part:
    return types.Part(function_call=types.FunctionCall(name=name, args=args or {}), thought_signature=signature)


def api_error(code: int) -> genai_errors.APIError:
    cls = genai_errors.ClientError if code < 500 else genai_errors.ServerError
    return cls(code, {"error": {"message": "boom", "status": "TEST"}})


class FakeModels:
    """Plays back `script`, one entry per request. An entry is a response (or a list of chunks for a stream),
    or an exception instance to raise. A chunk list may end with an exception: the stream fails half way."""

    def __init__(self) -> None:
        self.script: list[Any] = []
        self.calls: list[SimpleNamespace] = []

    def _next(self, model: str, contents: Any, config: Any) -> Any:
        self.calls.append(SimpleNamespace(model=model, contents=contents, config=config))
        assert self.script, f"unexpected request to {model}"
        return self.script.pop(0)

    async def generate_content(self, *, model: str, contents: Any, config: Any) -> Any:
        item = self._next(model, contents, config)
        if isinstance(item, Exception):
            raise item
        return item

    async def generate_content_stream(self, *, model: str, contents: Any, config: Any) -> Any:
        item = self._next(model, contents, config)
        if isinstance(item, Exception):
            raise item
        chunks = item if isinstance(item, list) else [item]

        async def stream():
            for chunk in chunks:
                if isinstance(chunk, Exception):
                    raise chunk
                yield chunk

        return stream()


class FakeClock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


class Harness:
    def __init__(self, *, fallbacks: list[str] | None = None) -> None:
        self.models = FakeModels()
        self.clock = FakeClock()
        self.client = SimpleNamespace(aio=SimpleNamespace(models=self.models, aclose=self._aclose))
        self.gateway = GeminiGateway(
            "test-key",
            fallback_models=FALLBACKS if fallbacks is None else fallbacks,
            client=self.client,
            clock=self.clock,
        )
        self.settings = Settings(_env_file=None, env="dev", ai_mode="mock", app_tokens=[], gemini_api_key=None)
        self.settings.coach_model = self.settings.plan_model = self.settings.text_model = PRIMARY
        self.app = create_app(self.settings, gateway=self.gateway)
        self.http = TestClient(self.app)

    @staticmethod
    async def _aclose() -> None:
        return None

    def models_called(self) -> list[str]:
        return [call.model for call in self.models.calls]

    def run(self, coroutine: Any) -> Any:
        return asyncio.run(coroutine)


@pytest.fixture
def harness() -> Harness:
    return Harness()


PROFILE = {"goal": "fitness", "level": "beginner", "daysPerWeek": 2, "sessionMinutes": 30, "equipment": "none"}

GOOD_PLAN = {
    "sessions": [
        {
            "weekday": 1,
            "title": "Całe ciało",
            "exercises": [
                {"exerciseId": "squat", "sets": 3, "repsMin": 12, "repsMax": 15, "restSeconds": 45},
                {"exerciseId": "pushup", "sets": 3, "repsMin": 12, "repsMax": 15, "restSeconds": 45},
            ],
        },
        {
            "weekday": 4,
            "title": "Całe ciało B",
            "exercises": [
                {"exerciseId": "lunge", "sets": 3, "repsMin": 12, "repsMax": 15, "restSeconds": 45},
                {"exerciseId": "plank", "sets": 3, "repsMin": 30, "repsMax": 45, "restSeconds": 45},
            ],
        },
    ]
}
