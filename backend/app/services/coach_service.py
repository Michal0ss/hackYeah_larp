"""AI trainer chat: validates the conversation, builds the prompt and tool list, and streams the answer.

The server is stateless: the app sends the whole conversation every time and executes the tools itself.

    app -> POST messages (+ consent, context) -> server -> model
    app <- text deltas / tool_use / done      <- server <- model
    app runs the tool on local data, appends a tool_result message and posts again.
"""

import json
from collections.abc import AsyncIterator
from dataclasses import dataclass
from typing import Any

from app.ai.gateway import AIGateway, ChatEvent, Finished, TextDelta, ToolCall
from app.ai.prompts import coach_system_prompt
from app.ai.tools import TOOLS, is_health_tool, normalise_tool_input, tools_for
from app.config import Settings
from app.content.store import ContentStore
from app.errors import ApiError
from app.logging_setup import get_logger
from app.schemas.api import (
    ChatMessage,
    CoachChatRequest,
    CoachChatResponse,
    TextBlock,
    ToolUseBlock,
    ToolUseOut,
    Usage,
)
from app.schemas.domain import UserProfile
from app.services.safety import RED_FLAG_NOTICE, detect_red_flags

log = get_logger("coach")


@dataclass(frozen=True)
class Conversation:
    system: str
    messages: list[dict[str, Any]]
    tools: list[dict[str, Any]]
    red_flag: bool
    # The user's profile from the request context; tool inputs are checked against it (equipment, level, avoid tags).
    profile: UserProfile | None = None


def _invalid(message: str = "Nieprawidłowa kolejność wiadomości w rozmowie.") -> ApiError:
    return ApiError(422, "invalid_conversation", message)


def prepare_conversation(request: CoachChatRequest, content: ContentStore, settings: Settings) -> Conversation:
    messages = request.messages
    consent = request.consent
    if len(messages) > settings.max_chat_messages:
        raise ApiError(422, "chat_too_long", "Rozmowa jest za długa. Skróć historię lub zacznij nową.")
    if messages[0].role != "user" or messages[-1].role != "user":
        raise _invalid("Rozmowa musi zaczynać się i kończyć wiadomością użytkownika.")

    total_chars = 0
    prepared: list[dict[str, Any]] = []
    expected: dict[str, str] = {}  # tool_use id -> name, from the previous assistant message

    for message in messages:
        blocks = [TextBlock(text=message.content)] if isinstance(message.content, str) else message.content
        texts: list[dict[str, Any]] = []
        uses: list[dict[str, Any]] = []
        results: list[dict[str, Any]] = []
        used_here: dict[str, str] = {}
        answered: set[str] = set()

        for block in blocks:
            if isinstance(block, TextBlock):
                if block.text.strip():
                    total_chars += len(block.text)
                    texts.append({"type": "text", "text": block.text})
            elif isinstance(block, ToolUseBlock):
                if message.role != "assistant":
                    raise _invalid()
                if block.name not in TOOLS:
                    raise ApiError(422, "unknown_tool", "Rozmowa zawiera nieznane narzędzie.")
                if is_health_tool(block.name) and not consent.health:
                    raise _consent_required()
                if block.id in used_here:
                    raise _invalid()
                total_chars += len(json.dumps(block.input))
                used_here[block.id] = block.name
                uses.append({"type": "tool_use", "id": block.id, "name": block.name, "input": block.input})
            else:  # ToolResultBlock
                if message.role != "user" or block.tool_use_id not in expected:
                    raise _invalid()
                if is_health_tool(expected[block.tool_use_id]) and not consent.health:
                    raise _consent_required()
                total_chars += len(block.content)
                answered.add(block.tool_use_id)
                results.append(
                    {
                        "type": "tool_result",
                        "tool_use_id": block.tool_use_id,
                        "content": block.content,
                        "is_error": block.is_error,
                    }
                )

        if message.role == "user":
            # Every tool call of the previous turn needs its result in this message (API requirement).
            if answered != set(expected):
                raise _invalid()
            expected = {}
            parts = results + texts  # tool results must come first
        else:
            expected = used_here
            parts = texts + uses
        if not parts:
            raise _invalid("Wiadomość w rozmowie jest pusta.")
        prepared.append({"role": message.role, "content": parts})

    if total_chars > settings.max_chat_chars:
        raise ApiError(422, "chat_too_long", "Rozmowa jest za długa. Skróć historię lub zacznij nową.")

    return Conversation(
        system=coach_system_prompt(content, request.context, consent),
        messages=prepared,
        tools=tools_for(consent.health),
        red_flag=_last_user_text_has_red_flag(messages[-1]),
        profile=request.context.profile if request.context else None,
    )


def _consent_required() -> ApiError:
    return ApiError(
        422,
        "consent_required",
        "Zgoda na dane zdrowotne jest wyłączona, a rozmowa zawiera takie dane. Usuń je z rozmowy.",
    )


def _last_user_text_has_red_flag(message: ChatMessage) -> bool:
    if isinstance(message.content, str):
        return detect_red_flags(message.content)
    return any(isinstance(b, TextBlock) and detect_red_flags(b.text) for b in message.content)


async def chat_events(
    conversation: Conversation, gateway: AIGateway, settings: Settings, content: ContentStore
) -> AsyncIterator[ChatEvent]:
    """The model's answer as events. Raises AIUnavailable (possibly after some text was already yielded)."""
    if conversation.red_flag:
        yield TextDelta(RED_FLAG_NOTICE)
    offered = {tool["name"] for tool in conversation.tools}
    dropped = False
    async for event in gateway.stream_chat(
        model=settings.coach_model,
        system=conversation.system,
        messages=conversation.messages,
        tools=conversation.tools,
        max_tokens=settings.coach_max_tokens,
    ):
        if isinstance(event, ToolCall):
            if event.name not in offered:
                # The model asked for a tool we did not offer (for example a health tool without consent).
                log.warning("tool_call_dropped", extra={"tool": event.name[:64]})
                dropped = True
                continue
            yield ToolCall(
                event.id, event.name, normalise_tool_input(event.name, event.input, content, conversation.profile)
            )
        elif isinstance(event, Finished) and dropped and event.stop_reason == "tool_use":
            yield Finished("end_turn", event.input_tokens, event.output_tokens)
        else:
            yield event


async def collect_response(events: AsyncIterator[ChatEvent]) -> CoachChatResponse:
    text: list[str] = []
    tool_uses: list[ToolUseOut] = []
    stop_reason: str | None = None
    usage = Usage()
    async for event in events:
        if isinstance(event, TextDelta):
            text.append(event.text)
        elif isinstance(event, ToolCall):
            tool_uses.append(ToolUseOut(id=event.id, name=event.name, input=event.input))
        else:
            stop_reason = event.stop_reason
            usage = Usage(input_tokens=event.input_tokens, output_tokens=event.output_tokens)
    return CoachChatResponse(text="".join(text), tool_uses=tool_uses, stop_reason=stop_reason, usage=usage)
