"""The only place that talks to a language model.

Everything else (services, routers) depends on the small `AIGateway` interface, so:
  * tests and the app run offline with `MockGateway` (no key, no network),
  * swapping the provider or model is a change in this file only,
  * errors are reduced to `AIUnavailable(reason)`, a short code that never contains user text.
"""

import asyncio
import re
import time
from collections.abc import AsyncIterator
from dataclasses import dataclass
from typing import Any, Protocol, TypeVar

import anthropic
from anthropic import AsyncAnthropic
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
    ) -> AsyncIterator[ChatEvent]: ...

    async def aclose(self) -> None: ...


# --- Anthropic


def _reason(exc: Exception) -> str:
    if isinstance(exc, anthropic.APITimeoutError):
        return "timeout"
    if isinstance(exc, anthropic.APIConnectionError):
        return "connection"
    if isinstance(exc, anthropic.APIStatusError):
        return f"status_{exc.status_code}"
    return "sdk_error"


class AnthropicGateway:
    mode = "anthropic"

    def __init__(self, api_key: str, timeout: float = 60.0, client: AsyncAnthropic | None = None):
        # max_retries: the SDK retries 429/5xx/connection errors with backoff before we give up.
        self._client = client or AsyncAnthropic(api_key=api_key, timeout=timeout, max_retries=2)

    def _log_call(self, kind: str, model: str, started: float, usage: Any) -> None:
        log.info(
            "ai_call",
            extra={
                "kind": kind,
                "model": model,
                "inputTokens": getattr(usage, "input_tokens", 0),
                "outputTokens": getattr(usage, "output_tokens", 0),
                "ms": round((time.perf_counter() - started) * 1000),
            },
        )

    def _fail(self, kind: str, model: str, exc: Exception) -> AIUnavailable:
        reason = _reason(exc)
        # Type and reason only: SDK error messages can quote parts of the request.
        log.warning("ai_error", extra={"kind": kind, "model": model, "reason": reason, "excType": type(exc).__name__})
        return AIUnavailable(reason)

    async def complete_text(self, *, kind: str, model: str, system: str, user: str, max_tokens: int) -> str:
        started = time.perf_counter()
        try:
            message = await self._client.messages.create(
                model=model,
                max_tokens=max_tokens,
                system=system,
                messages=[{"role": "user", "content": user}],
            )
        except anthropic.AnthropicError as exc:
            raise self._fail(kind, model, exc) from None
        self._log_call(kind, model, started, message.usage)
        return "".join(block.text for block in message.content if block.type == "text").strip()

    async def complete_structured(
        self, *, kind: str, model: str, system: str, user: str, schema: type[T], max_tokens: int
    ) -> T:
        started = time.perf_counter()
        try:
            message = await self._client.messages.parse(
                model=model,
                max_tokens=max_tokens,
                system=system,
                messages=[{"role": "user", "content": user}],
                output_format=schema,
            )
        except anthropic.AnthropicError as exc:
            raise self._fail(kind, model, exc) from None
        except ValueError:
            # The reply did not match the schema (the SDK validates it with pydantic).
            log.warning("ai_error", extra={"kind": kind, "model": model, "reason": "invalid_output"})
            raise AIUnavailable("invalid_output") from None
        self._log_call(kind, model, started, message.usage)
        if message.parsed_output is None:
            raise AIUnavailable(f"empty_output_{message.stop_reason}")
        return message.parsed_output

    async def stream_chat(
        self,
        *,
        model: str,
        system: str,
        messages: list[dict[str, Any]],
        tools: list[dict[str, Any]],
        max_tokens: int,
    ) -> AsyncIterator[ChatEvent]:
        started = time.perf_counter()
        try:
            async with self._client.messages.stream(
                model=model, max_tokens=max_tokens, system=system, messages=messages, tools=tools
            ) as stream:
                async for text in stream.text_stream:
                    yield TextDelta(text)
                final = await stream.get_final_message()
        except anthropic.AnthropicError as exc:
            raise self._fail("coach", model, exc) from None
        self._log_call("coach", model, started, final.usage)
        # A tool call cut off by max_tokens has incomplete input: never forward it.
        if final.stop_reason == "tool_use":
            for block in final.content:
                if block.type == "tool_use":
                    yield ToolCall(id=block.id, name=block.name, input=dict(block.input))
        yield Finished(final.stop_reason, final.usage.input_tokens, final.usage.output_tokens)

    async def aclose(self) -> None:
        await self._client.close()


# --- offline mock


class MockGateway:
    """Deterministic stand-in so the app and the tests work without a key or a network.

    Chat: replies with a canned Polish answer and, for a few keywords, asks for the matching tool first, so the
    client-side tool loop can be developed offline. Text and plan generation raise `AIUnavailable("mock")`, which
    makes the services answer from their templates.
    """

    mode = "mock"

    _TOOL_KEYWORDS: tuple[tuple[str, str], ...] = (
        (r"sen|spa[łl]|regener|zm[ęe]cz|hrv|t[ęe]tno|stres", "get_recovery_summary"),
        (r"technik|przysiad|forma|g[łl][ęe]bok", "get_technique_history"),
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
    return {"days": 7} if name == "get_recovery_summary" else {}
