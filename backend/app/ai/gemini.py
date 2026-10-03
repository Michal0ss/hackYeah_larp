"""Google Gemini implementation of `AIGateway`.

The rest of the backend and the app keep speaking the Anthropic-shaped protocol (`tool_use` / `tool_result`
blocks with ids). This module translates it to Gemini (`function_call` / `function_response` parts) and back,
so switching the provider changes nothing for the app.

Gemini specifics handled here:
  * Function calls may come without an id: we create one (`gm_...`) and never send it back to Gemini.
  * Thinking models attach a `thought_signature` to function calls and expect it back in the next turn. Our ids
    are limited to 100 characters, so signatures stay in a small in-memory cache keyed by the call id. When the
    cache misses (restart, another instance), the documented placeholder signature is sent instead.
  * Tools without parameters are declared without a schema (Gemini rejects an empty object schema).
  * JSON output uses `response_json_schema` with `$ref`s inlined, then pydantic validates the text.
"""

import inspect
import json
import time
import uuid
from collections import OrderedDict
from collections.abc import AsyncIterator
from typing import Any

from google import genai
from google.genai import errors as genai_errors
from google.genai import types
from pydantic import ValidationError

from app.ai.gateway import AIUnavailable, ChatEvent, Finished, T, TextDelta, ToolCall
from app.logging_setup import get_logger

log = get_logger("ai")

# Sent when we no longer have the real signature of a past function call (Gemini API docs, "thought signatures").
PLACEHOLDER_SIGNATURE = b"skip_thought_signature_validator"
SIGNATURE_CACHE_SIZE = 2000
OUR_ID_PREFIX = "gm_"

_BLOCKED = {
    types.FinishReason.SAFETY,
    types.FinishReason.PROHIBITED_CONTENT,
    types.FinishReason.BLOCKLIST,
    types.FinishReason.SPII,
    types.FinishReason.RECITATION,
}


def _reason(exc: Exception) -> str:
    if isinstance(exc, genai_errors.APIError):
        return f"status_{exc.code}"
    name = type(exc).__name__
    if "Timeout" in name:
        return "timeout"
    if any(word in name for word in ("Connect", "Network", "Transport", "Protocol")):
        return "connection"
    return "sdk_error"


def _inline_refs(schema: dict[str, Any]) -> dict[str, Any]:
    """Pydantic puts nested models in `$defs` and points at them with `$ref`; inline them for Gemini."""
    defs = schema.get("$defs", {})

    def resolve(node: Any) -> Any:
        if isinstance(node, dict):
            if "$ref" in node:
                return resolve(defs[node["$ref"].split("/")[-1]])
            resolved = {}
            for key, value in node.items():
                if key == "$defs" or (key == "title" and isinstance(value, str)):
                    continue  # metadata; a property *named* "title" is a dict and stays
                if key == "properties" and isinstance(value, dict):
                    resolved[key] = {name: resolve(prop) for name, prop in value.items()}
                else:
                    resolved[key] = resolve(value)
            return resolved
        if isinstance(node, list):
            return [resolve(item) for item in node]
        return node

    return resolve(schema)


def _thinking(model: str, *, light: bool) -> types.ThinkingConfig | None:
    """Little or no thinking where latency matters (chat, texts). Model families take different knobs."""
    if not light:
        return None
    if model.startswith("gemini-2.5-flash"):
        return types.ThinkingConfig(thinking_budget=0)
    if model.startswith("gemini-3"):
        return types.ThinkingConfig(thinking_level="low")
    return None


def _tool_result_payload(content: str, is_error: bool) -> dict[str, Any]:
    try:
        value: Any = json.loads(content)
    except ValueError:
        value = content
    return {"error": value} if is_error else {"output": value}


class GeminiGateway:
    mode = "gemini"

    def __init__(self, api_key: str, timeout: float = 60.0, client: Any | None = None):
        retry = types.HttpRetryOptions(attempts=3, http_status_codes=[429, 500, 502, 503, 504])
        self._client = client or genai.Client(
            api_key=api_key, http_options=types.HttpOptions(timeout=int(timeout * 1000), retry_options=retry)
        )
        self._signatures: OrderedDict[str, bytes] = OrderedDict()

    # --- logging and errors (ids, counts and timing only, never content)

    def _log_call(self, kind: str, model: str, started: float, usage: Any) -> None:
        output = (getattr(usage, "candidates_token_count", 0) or 0) + (getattr(usage, "thoughts_token_count", 0) or 0)
        log.info(
            "ai_call",
            extra={
                "kind": kind,
                "model": model,
                "inputTokens": getattr(usage, "prompt_token_count", 0) or 0,
                "outputTokens": output,
                "ms": round((time.perf_counter() - started) * 1000),
            },
        )

    def _fail(self, kind: str, model: str, exc: Exception) -> AIUnavailable:
        reason = _reason(exc)
        log.warning("ai_error", extra={"kind": kind, "model": model, "reason": reason, "excType": type(exc).__name__})
        return AIUnavailable(reason)

    def _unavailable(self, kind: str, model: str, reason: str) -> AIUnavailable:
        log.warning("ai_error", extra={"kind": kind, "model": model, "reason": reason})
        return AIUnavailable(reason)

    # --- single answers

    async def _generate(self, kind: str, model: str, user: str, config: types.GenerateContentConfig) -> str:
        started = time.perf_counter()
        try:
            response = await self._client.aio.models.generate_content(
                model=model, contents=[types.Content(role="user", parts=[types.Part(text=user)])], config=config
            )
        except Exception as exc:
            raise self._fail(kind, model, exc) from None
        self._log_call(kind, model, started, response.usage_metadata)
        candidate = response.candidates[0] if response.candidates else None
        finish = candidate.finish_reason if candidate else None
        if finish in _BLOCKED or (response.prompt_feedback and response.prompt_feedback.block_reason):
            raise self._unavailable(kind, model, "blocked")
        parts = candidate.content.parts if candidate and candidate.content and candidate.content.parts else []
        text = "".join(part.text for part in parts if part.text and not part.thought).strip()
        if not text:
            raise self._unavailable(kind, model, f"empty_output_{finish.name.lower() if finish else 'none'}")
        return text

    async def complete_text(self, *, kind: str, model: str, system: str, user: str, max_tokens: int) -> str:
        config = types.GenerateContentConfig(
            system_instruction=system, max_output_tokens=max_tokens, thinking_config=_thinking(model, light=True)
        )
        return await self._generate(kind, model, user, config)

    async def complete_structured(
        self, *, kind: str, model: str, system: str, user: str, schema: type[T], max_tokens: int
    ) -> T:
        config = types.GenerateContentConfig(
            system_instruction=system,
            max_output_tokens=max_tokens,
            response_mime_type="application/json",
            response_json_schema=_inline_refs(schema.model_json_schema(by_alias=True)),
            thinking_config=_thinking(model, light=False),
        )
        text = await self._generate(kind, model, user, config)
        try:
            return schema.model_validate_json(text)
        except ValidationError:
            raise self._unavailable(kind, model, "invalid_output") from None

    # --- chat

    def _remember(self, call_id: str, signature: bytes | None) -> None:
        if not signature:
            return
        self._signatures[call_id] = signature
        self._signatures.move_to_end(call_id)
        while len(self._signatures) > SIGNATURE_CACHE_SIZE:
            self._signatures.popitem(last=False)

    def to_contents(self, messages: list[dict[str, Any]]) -> list[types.Content]:
        """Anthropic-shaped conversation (as prepared by coach_service) -> Gemini contents."""
        contents: list[types.Content] = []
        names: dict[str, str] = {}  # tool_use id -> tool name
        for message in messages:
            blocks = message["content"]
            if isinstance(blocks, str):
                blocks = [{"type": "text", "text": blocks}]
            parts: list[types.Part] = []
            first_call = True
            for block in blocks:
                kind = block.get("type")
                if kind == "text":
                    parts.append(types.Part(text=block["text"]))
                elif kind == "tool_use":
                    call_id = block["id"]
                    names[call_id] = block["name"]
                    signature = self._signatures.get(call_id)
                    if signature is None and first_call:
                        # Only the first call of a step carries a signature; reuse the placeholder for it.
                        signature = PLACEHOLDER_SIGNATURE
                    first_call = False
                    parts.append(
                        types.Part(
                            function_call=types.FunctionCall(
                                id=None if call_id.startswith(OUR_ID_PREFIX) else call_id,
                                name=block["name"],
                                args=block.get("input") or {},
                            ),
                            thought_signature=signature,
                        )
                    )
                elif kind == "tool_result":
                    call_id = block["tool_use_id"]
                    parts.append(
                        types.Part(
                            function_response=types.FunctionResponse(
                                id=None if call_id.startswith(OUR_ID_PREFIX) else call_id,
                                name=names.get(call_id, "unknown_tool"),
                                response=_tool_result_payload(block["content"], bool(block.get("is_error"))),
                            )
                        )
                    )
            contents.append(types.Content(role="model" if message["role"] == "assistant" else "user", parts=parts))
        return contents

    @staticmethod
    def to_tools(tools: list[dict[str, Any]]) -> list[types.Tool] | None:
        if not tools:
            return None
        declarations = []
        for tool in tools:
            schema = tool.get("input_schema") or {}
            declarations.append(
                types.FunctionDeclaration(
                    name=tool["name"],
                    description=tool.get("description", ""),
                    parameters_json_schema=schema if schema.get("properties") else None,
                )
            )
        return [types.Tool(function_declarations=declarations)]

    async def stream_chat(
        self,
        *,
        model: str,
        system: str,
        messages: list[dict[str, Any]],
        tools: list[dict[str, Any]],
        max_tokens: int,
    ) -> AsyncIterator[ChatEvent]:
        config = types.GenerateContentConfig(
            system_instruction=system,
            max_output_tokens=max_tokens,
            tools=self.to_tools(tools),
            automatic_function_calling=types.AutomaticFunctionCallingConfig(disable=True),
            thinking_config=_thinking(model, light=True),
        )
        started = time.perf_counter()
        calls: list[ToolCall] = []
        usage: Any = None
        finish: types.FinishReason | None = None
        blocked = False
        wrote_text = False
        try:
            stream = self._client.aio.models.generate_content_stream(
                model=model, contents=self.to_contents(messages), config=config
            )
            if inspect.isawaitable(stream):
                stream = await stream
            async for chunk in stream:
                usage = chunk.usage_metadata or usage
                if chunk.prompt_feedback and chunk.prompt_feedback.block_reason:
                    blocked = True
                candidate = chunk.candidates[0] if chunk.candidates else None
                if candidate is None:
                    continue
                finish = candidate.finish_reason or finish
                parts = candidate.content.parts if candidate.content and candidate.content.parts else []
                for part in parts:
                    if part.thought:
                        continue
                    if part.function_call:
                        call = part.function_call
                        call_id = call.id if call.id and len(call.id) <= 100 else OUR_ID_PREFIX + uuid.uuid4().hex
                        self._remember(call_id, part.thought_signature)
                        calls.append(ToolCall(id=call_id, name=call.name or "", input=dict(call.args or {})))
                    elif part.text:
                        wrote_text = True
                        yield TextDelta(part.text)
        except AIUnavailable:
            raise
        except Exception as exc:
            raise self._fail("coach", model, exc) from None

        self._log_call("coach", model, started, usage)
        if blocked or finish in _BLOCKED:
            raise self._unavailable("coach", model, "blocked")
        if finish == types.FinishReason.MALFORMED_FUNCTION_CALL:
            raise self._unavailable("coach", model, "malformed_tool_call")
        input_tokens = getattr(usage, "prompt_token_count", 0) or 0
        output_tokens = (getattr(usage, "candidates_token_count", 0) or 0) + (
            getattr(usage, "thoughts_token_count", 0) or 0
        )
        if finish == types.FinishReason.MAX_TOKENS:
            # A tool call cut off by the token limit may be incomplete: never forward it.
            yield Finished("max_tokens", input_tokens, output_tokens)
            return
        if calls:
            for call in calls:
                yield call
            yield Finished("tool_use", input_tokens, output_tokens)
            return
        if not wrote_text:
            raise self._unavailable("coach", model, "empty_output")
        yield Finished("end_turn", input_tokens, output_tokens)

    async def aclose(self) -> None:
        await self._client.aio.aclose()
