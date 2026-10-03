"""Exports the OpenAPI document to backend/openapi.json: the API contract the Swift client is written against.

    python scripts/export_openapi.py            write the file
    python scripts/export_openapi.py --check    fail when the file is out of date (used by CI and `make check`)

Building the app also loads and validates everything in content/, so a broken content file fails here too.
"""

import json
import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

from app.config import Settings  # noqa: E402
from app.content.store import ContentError  # noqa: E402
from app.main import create_app  # noqa: E402

TARGET = BACKEND / "openapi.json"


def render() -> str:
    # Mock mode and no tokens: the document does not depend on anyone's environment or secrets.
    app = create_app(Settings(_env_file=None, env="dev", ai_mode="mock", gemini_api_key=None, app_tokens=[]))
    return json.dumps(app.openapi(), indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def main() -> int:
    try:
        document = render()
    except ContentError as error:
        print("content/ is invalid:", file=sys.stderr)
        for problem in error.problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1
    if "--check" in sys.argv:
        if not TARGET.exists() or TARGET.read_text(encoding="utf-8") != document:
            print("backend/openapi.json is out of date. Run `make openapi` and commit the result.", file=sys.stderr)
            return 1
        print("openapi.json is up to date")
        return 0
    TARGET.write_text(document, encoding="utf-8")
    print(f"wrote {TARGET.relative_to(BACKEND.parent)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
