import json
from collections.abc import AsyncIterator
from typing import Any

from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse, StreamingResponse

from app.ai.gateway import AIGateway, AIUnavailable, ChatEvent, TextDelta, ToolCall
from app.config import Settings
from app.content.store import ContentStore
from app.deps import get_content, get_gateway, get_settings
from app.errors import ApiError
from app.logging_setup import get_logger, request_id_ctx
from app.schemas.api import CoachChatRequest, CoachChatResponse
from app.security import rate_limited
from app.services.coach_service import chat_events, collect_response, prepare_conversation

log = get_logger("coach")

router = APIRouter(prefix="/coach", tags=["coach"])
guard = rate_limited("chat", lambda s: s.rate_limit_chat_per_minute)

AI_DOWN_MESSAGE = "Trener jest chwilowo niedostępny. Spróbuj za chwilę."


def sse(event: str, data: dict[str, Any]) -> str:
    # json.dumps never emits a raw newline, so one `data:` line is always enough.
    return f"event: {event}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"


async def _stream(events: AsyncIterator[ChatEvent]) -> AsyncIterator[str]:
    try:
        async for event in events:
            if isinstance(event, TextDelta):
                yield sse("delta", {"text": event.text})
            elif isinstance(event, ToolCall):
                yield sse("tool_use", {"id": event.id, "name": event.name, "input": event.input})
            else:
                yield sse(
                    "done",
                    {
                        "stopReason": event.stop_reason,
                        "usage": {"inputTokens": event.input_tokens, "outputTokens": event.output_tokens},
                    },
                )
    except AIUnavailable:
        yield sse("error", {"code": "ai_unavailable", "message": AI_DOWN_MESSAGE, "requestId": request_id_ctx.get()})
    except Exception as exc:  # the client must always get a terminal event
        log.error("stream_error", extra={"excType": type(exc).__name__})
        yield sse(
            "error",
            {
                "code": "internal_error",
                "message": "Wystąpił błąd serwera.",
                "requestId": request_id_ctx.get(),
            },
        )


@router.post(
    "/chat",
    response_model=None,
    operation_id="coachChat",
    summary="AI trainer chat (SSE stream or one JSON response)",
    description=(
        "Stateless: send the whole conversation every time. The model may ask for a tool; the **app** runs it on "
        "local data and posts again with a `tool_result` block.\n\n"
        "`stream: true` (default) answers with `text/event-stream`:\n\n"
        '- `event: delta` `data: {"text": "..."}` a piece of the answer\n'
        '- `event: tool_use` `data: {"id", "name", "input"}` the model wants a tool (a `done` event follows)\n'
        '- `event: done` `data: {"stopReason", "usage": {"inputTokens", "outputTokens"}}` last event\n'
        '- `event: error` `data: {"code", "message", "requestId"}` terminal error after the stream started\n\n'
        "`stream: false` answers with one JSON object. Problems detected before the model is called "
        "(invalid conversation, consent, limits) are normal HTTP errors in both modes."
    ),
    responses={
        200: {
            "model": CoachChatResponse,
            "description": "JSON when `stream` is false, `text/event-stream` otherwise.",
            "content": {"text/event-stream": {"schema": {"type": "string"}}},
        },
        503: {"description": "The model is unavailable (non-streaming only; a stream sends an `error` event)."},
    },
)
async def chat(
    body: CoachChatRequest,
    content: ContentStore = Depends(get_content),
    gateway: AIGateway = Depends(get_gateway),
    settings: Settings = Depends(get_settings),
    _=Depends(guard),
):
    conversation = prepare_conversation(body, content, settings)
    events = chat_events(conversation, gateway, settings, content)

    if not body.stream:
        try:
            result = await collect_response(events)
        except AIUnavailable:
            raise ApiError(503, "ai_unavailable", AI_DOWN_MESSAGE, headers={"Retry-After": "5"}) from None
        return JSONResponse(result.model_dump(by_alias=True, mode="json"))

    return StreamingResponse(
        _stream(events),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
