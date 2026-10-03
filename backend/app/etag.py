"""ETag helpers for the content endpoints (the app revalidates cheaply and gets 304 when nothing changed)."""

from fastapi import Request, Response


def make_etag(version: str) -> str:
    return f'"{version}"'


def not_modified(request: Request, etag: str) -> Response | None:
    """A 304 response when the client already has this version, otherwise None."""
    header = request.headers.get("if-none-match", "")
    candidates = {part.strip().removeprefix("W/") for part in header.split(",")}
    if etag in candidates or "*" in candidates:
        return Response(status_code=304, headers={"ETag": etag, "Cache-Control": "no-cache"})
    return None
