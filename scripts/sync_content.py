"""Copies content/ into the app bundle so the app works offline and on first launch.

    python scripts/sync_content.py            copy
    python scripts/sync_content.py --check    exit 1 when the copy is stale

The destination is Packages/Core/Sources/Content/Resources/ (read by ContentRepository). SwiftPM flattens
resources, so config/*.json land next to catalog.json; the file names are unique on purpose.
"""

import filecmp
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "content"
TARGET = ROOT / "Packages/Core/Sources/Content/Resources"


def files() -> list[Path]:
    return sorted(p.relative_to(SOURCE) for p in SOURCE.rglob("*.json"))


def destination(f: Path) -> Path:
    return TARGET / f.name


def stale() -> list[Path]:
    return [f for f in files() if not destination(f).exists() or not filecmp.cmp(SOURCE / f, destination(f), shallow=False)]


if __name__ == "__main__":
    if "--check" in sys.argv:
        out_of_date = stale()
        for f in out_of_date:
            print(f"stale: {f}", file=sys.stderr)
        raise SystemExit(1 if out_of_date else 0)
    for f in files():
        TARGET.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(SOURCE / f, destination(f))
    print(f"copied {len(files())} files to {TARGET.relative_to(ROOT)}")
