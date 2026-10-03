"""Accessors for the objects created in `create_app` (kept on `app.state`)."""

from fastapi import Request

from app.ai.gateway import AIGateway
from app.config import Settings
from app.content.store import ContentStore


def get_settings(request: Request) -> Settings:
    return request.app.state.settings


def get_content(request: Request) -> ContentStore:
    return request.app.state.content


def get_gateway(request: Request) -> AIGateway:
    return request.app.state.gateway
