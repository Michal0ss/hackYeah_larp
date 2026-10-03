"""SupabaseRateLimiter against a fake transport (no network), and build_limiter's choice of limiter."""

import httpx
import pytest

from app.config import Settings
from app.errors import ApiError
from app.main import build_limiter
from app.security import RateLimiter, SupabaseRateLimiter


def settings(**values) -> Settings:
    return Settings(_env_file=None, **values)


def make_limiter(handler, fallback: RateLimiter | None = None) -> SupabaseRateLimiter:
    return SupabaseRateLimiter(
        "https://x.supabase.co", "key", fallback=fallback or RateLimiter(), transport=httpx.MockTransport(handler)
    )


def allow_handler(request: httpx.Request) -> httpx.Response:
    return httpx.Response(200, json=[{"allowed": True, "retry_after": 1}])


def deny_handler(request: httpx.Request) -> httpx.Response:
    return httpx.Response(200, json=[{"allowed": False, "retry_after": 7}])


def broken_handler(request: httpx.Request) -> httpx.Response:
    return httpx.Response(500, json={"error": "nope"})


def unreachable_handler(request: httpx.Request) -> httpx.Response:
    raise httpx.ConnectError("no route to host", request=request)


# --- SupabaseRateLimiter: happy paths


def test_allowed_response_does_not_raise():
    limiter = make_limiter(allow_handler)
    limiter.check("plans", "device1", 6)  # no exception


def test_denied_response_raises_429_with_retry_after():
    limiter = make_limiter(deny_handler)
    with pytest.raises(ApiError) as excinfo:
        limiter.check("plans", "device1", 6)
    assert excinfo.value.status_code == 429
    assert excinfo.value.headers["Retry-After"] == "7"


# --- fail-open: Supabase errors fall back to the in-memory limiter instead of raising


def test_http_error_falls_back_to_memory_limiter():
    fallback = RateLimiter(window_seconds=60)
    limiter = make_limiter(broken_handler, fallback=fallback)
    limiter.check("plans", "device1", limit=1)  # first hit: fallback allows it
    with pytest.raises(ApiError) as excinfo:
        limiter.check("plans", "device1", limit=1)  # second hit: fallback's own limit kicks in
    assert excinfo.value.status_code == 429


def test_network_error_falls_back_to_memory_limiter():
    fallback = RateLimiter(window_seconds=60)
    limiter = make_limiter(unreachable_handler, fallback=fallback)
    limiter.check("plans", "device1", limit=1)
    with pytest.raises(ApiError):
        limiter.check("plans", "device1", limit=1)


def test_malformed_body_falls_back_to_memory_limiter():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"not": "a list"})

    fallback = RateLimiter(window_seconds=60)
    limiter = make_limiter(handler, fallback=fallback)
    limiter.check("plans", "device1", limit=1)
    with pytest.raises(ApiError):
        limiter.check("plans", "device1", limit=1)


# --- build_limiter: picks Supabase only when fully configured


def test_build_limiter_uses_memory_when_unconfigured():
    assert isinstance(build_limiter(settings()), RateLimiter)


def test_build_limiter_uses_memory_when_only_url_is_set():
    assert isinstance(build_limiter(settings(supabase_url="https://x.supabase.co")), RateLimiter)


def test_build_limiter_uses_supabase_when_fully_configured():
    limiter = build_limiter(settings(supabase_url="https://x.supabase.co", supabase_service_key="k"))
    assert isinstance(limiter, SupabaseRateLimiter)
    limiter.close()


def test_blank_service_key_counts_as_unconfigured():
    limiter = build_limiter(settings(supabase_url="https://x.supabase.co", supabase_service_key="   "))
    assert isinstance(limiter, RateLimiter)
