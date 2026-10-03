"""The interface to the language model, and the offline stand-in.

Everything else (services, routers) depends on the small `AIGateway` interface, so:
  * tests and the app run offline with `MockGateway` (no key, no network),
  * the real model is `GeminiGateway` (app/ai/gemini.py),
  * errors are reduced to `AIUnavailable(reason)`, a short code that never contains user text.
"""

import asyncio
import re
from collections.abc import AsyncIterator
from dataclasses import dataclass
from typing import Any, Protocol, TypeVar

from pydantic import BaseModel

from app.logging_setup import get_logger

log = get_logger("ai")

T = TypeVar("T", bound=BaseModel)


class AIUnavailable(Exception):
    """The model could not be used. `reason` is a short code such as "timeout" or "status_529"."""

    def __init__(self, reason: str):
        super().__init__(reason)
        self.reason = reason


# --- chat events (what a streamed answer is made of)


@dataclass(frozen=True)
class TextDelta:
    text: str


@dataclass(frozen=True)
class ToolCall:
    id: str
    name: str
    input: dict[str, Any]


@dataclass(frozen=True)
class Finished:
    stop_reason: str | None
    input_tokens: int = 0
    output_tokens: int = 0


ChatEvent = TextDelta | ToolCall | Finished


class AIGateway(Protocol):
    mode: str

    async def complete_text(self, *, kind: str, model: str, system: str, user: str, max_tokens: int) -> str: ...

    async def complete_structured(
        self, *, kind: str, model: str, system: str, user: str, schema: type[T], max_tokens: int
    ) -> T: ...

    def stream_chat(
        self,
        *,
        model: str,
        system: str,
        messages: list[dict[str, Any]],
        tools: list[dict[str, Any]],
        max_tokens: int,
        fast: bool = False,
    ) -> AsyncIterator[ChatEvent]: ...

    async def aclose(self) -> None: ...


# --- offline mock


class MockGateway:
    """Deterministic stand-in so the app and the tests work without a key or a network.

    Chat: replies with a canned Polish answer and, for a few keywords, asks for the matching tool first, so the
    client-side tool loop can be developed offline. Text and plan generation raise `AIUnavailable("mock")`, which
    makes the services answer from their templates.
    """

    mode = "mock"

    _TOOL_KEYWORDS: tuple[tuple[str, str], ...] = (
        (
            r"zamie[ńn]|zast[ąa]p|przenie[śs]|pomi[ńn]\w* (sesj|trening)|l[żz]ejsz\w+ (sesj|trening)",
            "propose_plan_change",
        ),
        (r"po trening\w*|rpe|dyskomfort|boli|b[óo]l", "get_session_feedback"),
        (r"sen|spa[łl]|regener|zm[ęe]cz|hrv|t[ęe]tno|stres", "get_recovery_summary"),
        (r"technik|przysiad|forma|g[łl][ęe]bok", "get_technique_history"),
        (r"zrobi[łl]\w*|historia trening\w*|ile (serii|powt)", "get_training_log"),
        (r"plan|trening|dzi[śs]|tydzie[ńn]", "get_current_plan"),
    )

    def __init__(self, delay: float = 0.0):
        self._delay = delay
        self._calls = 0

    async def complete_text(self, *, kind: str, model: str, system: str, user: str, max_tokens: int) -> str:
        raise AIUnavailable("mock")

    async def complete_structured(
        self, *, kind: str, model: str, system: str, user: str, schema: type[T], max_tokens: int
    ) -> T:
        raise AIUnavailable("mock")

    async def stream_chat(
        self,
        *,
        model: str,
        system: str,
        messages: list[dict[str, Any]],
        tools: list[dict[str, Any]],
        max_tokens: int,
        fast: bool = False,
    ) -> AsyncIterator[ChatEvent]:
        self._calls += 1
        last = messages[-1]["content"]
        available = {tool["name"] for tool in tools}
        results = (
            [block for block in last if isinstance(block, dict) and block.get("type") == "tool_result"]
            if isinstance(last, list)
            else []
        )
        asked = (
            last
            if isinstance(last, str)
            else " ".join(b.get("text", "") for b in last if isinstance(b, dict) and b.get("type") == "text")
        ).lower()

        if results:
            reply = (
                "To tryb testowy serwera (bez prawdziwego modelu). Dane z telefonu dotarły, "
                f"liczba wyników: {len(results)}. W wersji z modelem odpowiem na ich podstawie."
            )
        else:
            wanted = next((tool for pattern, tool in self._TOOL_KEYWORDS if re.search(pattern, asked)), None)
            if wanted and wanted in available:
                yield ToolCall(id=f"toolu_mock_{self._calls}", name=wanted, input=_mock_tool_input(wanted))
                yield Finished("tool_use", 10, 5)
                return
            if wanted and wanted not in available:
                reply = (
                    "To tryb testowy serwera. Nie mam dostępu do danych zdrowotnych, bo zgoda jest wyłączona. "
                    "Możesz ją włączyć w ustawieniach aplikacji."
                )
            else:
                reply = "To tryb testowy serwera (bez prawdziwego modelu). Zapytaj o plan, sen albo technikę."

        for chunk in re.findall(r"\S+\s*", reply):
            if self._delay:
                await asyncio.sleep(self._delay)
            yield TextDelta(chunk)
        yield Finished("end_turn", 10, len(reply) // 4)

    async def aclose(self) -> None:
        return None


def _mock_tool_input(name: str) -> dict[str, Any]:
    if name == "propose_plan_change":
        # Fits the sample plan in the app: Monday's session has a squat.
        return {
            "kind": "swap_exercise",
            "weekday": 1,
            "exerciseId": "squat",
            "replacementExerciseId": "box_squat",
            "reason": "Łatwiejszy wariant, gdy chcesz zacząć spokojniej.",
        }
    if name == "get_recovery_summary":
        return {"days": 7}
    return {"limit": 3} if name == "get_session_feedback" else {}
