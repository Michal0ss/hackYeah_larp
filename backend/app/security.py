"""App authentication and rate limiting.

Auth is a shared bearer token baked into the app build (Config/Secrets.xcconfig on the Swift side). It is NOT
user authentication: it only keeps strangers from spending our model budget. Per-user accounts come later.

Rate limiting is per device (header X-Device-Id, a random UUID the app creates once) and falls back to the
client IP. It lives in memory, so it is per process: with several instances use a shared store (Redis).
"""

import hashlib
import hmac
import math
import re
import time
from collections import defaultdict, deque
from collections.abc import Callable
from dataclasses import dataclass

from fastapi import Depends, Request

from app.config import Settings
from app.errors import ApiError
from app.logging_setup import get_logger

log = get_logger("security")

DEVICE_ID_RE = re.compile(r"^[A-Za-z0-9-]{8,64}$")


@dataclass(frozen=True)
class ClientIdentity:
    device_id: str | None
    # Short hash: safe to log, used as the rate-limit key.
    key: str


def parse_device_id(value: str | None) -> str | None:
    return value if value and DEVICE_ID_RE.match(value) else None


def identity_key(device_id: str | None, client_host: str | None) -> str:
    raw = device_id or f"ip:{client_host or 'unknown'}"
    return hashlib.sha256(raw.encode()).hexdigest()[:12]


def _token_valid(candidate: str, tokens: list[str]) -> bool:
    ok = False
    for token in tokens:  # compare against all of them: constant time per token
        ok |= hmac.compare_digest(candidate.encode(), token.encode())
    return ok


def require_client(request: Request) -> ClientIdentity:
    """Dependency: checks the bearer token (when auth is on) and identifies the device."""
    settings: Settings = request.app.state.settings
    device_id = parse_device_id(request.headers.get("x-device-id"))
    client_host = request.client.host if request.client else None
    key = identity_key(device_id, client_host)

    if settings.auth_enabled:
        header = request.headers.get("authorization", "")
        scheme, _, token = header.partition(" ")
        if scheme.lower() != "bearer" or not token or not _token_valid(token.strip(), settings.app_tokens):
            log.warning("auth_failed", extra={"client": key, "path": request.url.path})
            raise ApiError(
                401,
                "unauthorized",
                "Brak lub nieprawidłowy token aplikacji.",
                headers={"WWW-Authenticate": "Bearer"},
            )
    return ClientIdentity(device_id=device_id, key=key)


class RateLimiter:
    """Sliding window: at most `limit` hits per `window` seconds for one (bucket, client) pair."""

    def __init__(self, window_seconds: float = 60.0, clock: Callable[[], float] = time.monotonic):
        self.window = window_seconds
        self.clock = clock
        self._hits: dict[tuple[str, str], deque[float]] = defaultdict(deque)

    def check(self, bucket: str, client_key: str, limit: int) -> None:
        now = self.clock()
        hits = self._hits[(bucket, client_key)]
        while hits and now - hits[0] >= self.window:
            hits.popleft()
        if len(hits) >= limit:
            retry_after = max(1, math.ceil(self.window - (now - hits[0])))
            raise ApiError(
                429,
                "rate_limited",
                "Za dużo zapytań. Spróbuj za chwilę.",
                headers={"Retry-After": str(retry_after)},
            )
        hits.append(now)
        if not hits:  # pragma: no cover - defensive
            self._hits.pop((bucket, client_key), None)


def rate_limited(bucket: str, per_minute: Callable[[Settings], int]):
    """Builds a dependency that authenticates the client and applies the limit for `bucket`."""

    def dependency(request: Request, identity: ClientIdentity = Depends(require_client)) -> ClientIdentity:
        settings: Settings = request.app.state.settings
        request.app.state.limiter.check(bucket, identity.key, per_minute(settings))
        return identity

    return dependency
