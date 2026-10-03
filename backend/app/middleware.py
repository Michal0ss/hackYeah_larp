"""Request id, size limit, last-resort error handling and a metadata-only access log.

Pure ASGI (not BaseHTTPMiddleware), so streaming responses are passed through without buffering.
"""

import json
import re
import time
import uuid

from starlette.exceptions import HTTPException
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.config import Settings
from app.errors import error_payload
from app.logging_setup import get_logger, request_id_ctx
from app.security import identity_key, parse_device_id

log = get_logger("access")

_REQUEST_ID_RE = re.compile(r"^[A-Za-z0-9._-]{8,64}$")
TOO_LARGE = "Zbyt duże żądanie."


class RequestContextMiddleware:
    def __init__(self, app: ASGIApp, settings: Settings):
        self.app = app
        self.settings = settings

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        headers = {k.decode("latin-1").lower(): v.decode("latin-1") for k, v in scope["headers"]}
        incoming = headers.get("x-request-id", "")
        request_id = incoming if _REQUEST_ID_RE.match(incoming) else uuid.uuid4().hex
        token = request_id_ctx.set(request_id)
        started_at = time.perf_counter()
        state = {"status": 500, "started": False, "received": 0}
        limit = self.settings.max_request_bytes

        async def limited_receive() -> Message:
            message = await receive()
            if message["type"] == "http.request":
                # Counts bytes as they arrive, so chunked uploads without a Content-Length are limited too.
                state["received"] += len(message.get("body", b""))
                if state["received"] > limit:
                    raise HTTPException(413, TOO_LARGE)
            return message

        async def send_wrapper(message: Message) -> None:
            if message["type"] == "http.response.start":
                state["status"] = message["status"]
                state["started"] = True
                message = {**message, "headers": [*message.get("headers", []), (b"x-request-id", request_id.encode())]}
            await send(message)

        try:
            try:
                declared = int(headers.get("content-length", "0") or 0)
            except ValueError:
                declared = 0
            if declared > limit:
                await self._respond(send_wrapper, 413, "payload_too_large", TOO_LARGE)
            else:
                await self.app(scope, limited_receive, send_wrapper)
        except Exception as exc:
            # Type only: the text of an exception (or its traceback) can contain request data.
            log.error("unhandled_error", extra={"excType": type(exc).__name__})
            if state["started"]:
                raise  # the response is already on the wire; let the server drop the connection
            await self._respond(send_wrapper, 500, "internal_error", "Wystąpił błąd serwera.")
        finally:
            client = scope.get("client")
            device = parse_device_id(headers.get("x-device-id"))
            # Path only (no query string), status and timing: nothing from the body or the headers.
            log.info(
                "request",
                extra={
                    "method": scope["method"],
                    "path": scope["path"],
                    "status": state["status"],
                    "ms": round((time.perf_counter() - started_at) * 1000, 1),
                    "client": identity_key(device, client[0] if client else None),
                },
            )
            request_id_ctx.reset(token)

    @staticmethod
    async def _respond(send: Send, status: int, code: str, message: str) -> None:
        body = json.dumps(error_payload(code, message), ensure_ascii=False).encode()
        await send(
            {
                "type": "http.response.start",
                "status": status,
                "headers": [(b"content-type", b"application/json"), (b"content-length", str(len(body)).encode())],
            }
        )
        await send({"type": "http.response.body", "body": body})
