"""Vercel entrypoint: exposes the FastAPI app as `app` (ASGI). Local check from the repo root:

    FORMA_APP_TOKENS=test-token backend/.venv/bin/python -m uvicorn api.index:app --port 8000

Settings come from the project's environment variables on Vercel (see backend/README.md, "Deploying").
"""

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))

# A deployed server is "prod": it refuses to start without FORMA_APP_TOKENS and hides the docs.
os.environ.setdefault("FORMA_ENV", "prod")
os.environ.setdefault("FORMA_CONTENT_DIR", str(ROOT / "content"))

from app.main import create_app  # noqa: E402

app = create_app()
