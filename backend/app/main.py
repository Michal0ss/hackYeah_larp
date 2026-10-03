"""Application factory.

    uvicorn app.main:create_app --factory --reload

Everything is created here and kept on `app.state`, so tests can build an app with their own settings, a fake
AI gateway and a custom content directory (see tests/conftest.py).
"""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.routing import APIRoute

from app import __version__
from app.ai.gateway import AIGateway, AnthropicGateway, MockGateway
from app.config import Settings
from app.content.store import ContentStore
from app.errors import register_exception_handlers
from app.logging_setup import configure_logging, get_logger
from app.middleware import RequestContextMiddleware
from app.routers import api_v1, system
from app.security import RateLimiter

DESCRIPTION = """
Backend of the Forma app. Stateless: no database, no stored videos, no stored health data.

* `GET /health`: liveness (no auth)
* `/v1/*`: needs `Authorization: Bearer <app token>` when `FORMA_APP_TOKENS` is set; send a stable random
  `X-Device-Id` (UUID) so rate limits are per device
* every error is `{"error": {"code", "message", "requestId"}}`
"""


def build_gateway(settings: Settings) -> AIGateway:
    if settings.effective_ai_mode == "anthropic":
        assert settings.anthropic_api_key is not None
        return AnthropicGateway(settings.anthropic_api_key.get_secret_value(), timeout=settings.ai_timeout_seconds)
    return MockGateway(delay=0.015 if settings.env == "dev" else 0.0)


def create_app(
    settings: Settings | None = None,
    gateway: AIGateway | None = None,
    content: ContentStore | None = None,
) -> FastAPI:
    settings = settings or Settings()
    log = configure_logging(settings.log_level)
    content = content or ContentStore.load(settings.content_dir)
    gateway = gateway or build_gateway(settings)

    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        log.info(
            "startup",
            extra={
                "version": __version__,
                "env": settings.env,
                "aiMode": gateway.mode,
                "auth": settings.auth_enabled,
                "contentVersion": content.content_version,
            },
        )
        yield
        await gateway.aclose()

    is_prod = settings.env == "prod"
    app = FastAPI(
        title="Forma API",
        version=__version__,
        description=DESCRIPTION,
        lifespan=lifespan,
        # No interactive docs or schema on a public server; `make openapi` exports the schema to the repo.
        docs_url=None if is_prod else "/docs",
        redoc_url=None,
        openapi_url=None if is_prod else "/openapi.json",
        generate_unique_id_function=lambda route: route.name if isinstance(route, APIRoute) else "",
    )
    app.state.settings = settings
    app.state.content = content
    app.state.gateway = gateway
    app.state.limiter = RateLimiter()

    register_exception_handlers(app)
    app.include_router(system.router)
    app.include_router(api_v1)

    if settings.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins,
            allow_methods=["GET", "POST"],
            allow_headers=["Authorization", "Content-Type", "X-Device-Id", "X-Request-Id", "If-None-Match"],
            expose_headers=["X-Request-Id", "ETag", "Retry-After"],
        )
    # Added last = outermost: the request id and the size limit apply to everything, including CORS preflights.
    app.add_middleware(RequestContextMiddleware, settings=settings)
    get_logger().debug("app created")
    return app
