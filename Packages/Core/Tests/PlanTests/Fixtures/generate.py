"""Regenerates template_plans.json: what the BACKEND builds from content/ for a grid of profiles.

The Swift `TemplatePlanBuilder` must build exactly the same plans offline (TemplatePlanParityTests compares them).
Run from the repository root after changing content/catalog.json or content/plan_templates.json (and sync_content):

    backend/.venv/bin/python Packages/Core/Tests/PlanTests/Fixtures/generate.py
"""

import json
import sys
from itertools import product
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(ROOT / "backend"))

from app.content.store import ContentStore  # noqa: E402
from app.schemas.domain import UserProfile  # noqa: E402
from app.services.plan_builder import build_template_plan  # noqa: E402

content = ContentStore.load(ROOT / "content")
TAG_SETS = [
    [], [], ["deepSquats"], [], ["jumps", "deepLunges"], [], ["overheadPress", "loadedPushups", "barbellDeadlift"], [],
]
MINUTES = [30, 45, 60, 75]

profiles = []
grid = product(["strength", "physique", "fitness", "returnToMovement"], ["beginner", "intermediate"], [2, 3, 4, 5],
               ["none", "dumbbells", "gym"])
for index, (goal, level, days, equipment) in enumerate(grid):
    profiles.append(
        {
            "goal": goal, "level": level, "daysPerWeek": days, "sessionMinutes": MINUTES[index % 4], "equipment": equipment,
            "avoid": "kolano" if index % 5 == 0 else "", "avoidTags": TAG_SETS[index % len(TAG_SETS)],
            "easyStart": index % 7 == 0,
        }
    )
# Edge cases: everything avoided, 15-minute sessions, 120-minute sessions.
all_tags = ["jumps", "deepLunges", "overheadPress", "barbellDeadlift", "deepSquats", "loadedPushups"]
profiles.append({"goal": "strength", "level": "intermediate", "daysPerWeek": 4, "sessionMinutes": 60, "equipment": "gym",
                 "avoid": "", "avoidTags": all_tags, "easyStart": False})
profiles.append({"goal": "fitness", "level": "beginner", "daysPerWeek": 3, "sessionMinutes": 15, "equipment": "none",
                 "avoid": "", "avoidTags": all_tags, "easyStart": True})
profiles.append({"goal": "physique", "level": "intermediate", "daysPerWeek": 5, "sessionMinutes": 120, "equipment": "gym",
                 "avoid": "", "avoidTags": [], "easyStart": False})

out = []
for raw in profiles:
    plan = build_template_plan(UserProfile.model_validate(raw), content)
    out.append(
        {
            "profile": raw,
            "sessions": [
                {
                    "weekday": s.weekday, "title": s.title,
                    "exercises": [
                        {"exerciseId": e.exercise_id, "sets": e.sets, "repsMin": e.reps_min, "repsMax": e.reps_max,
                         "restSeconds": e.rest_seconds,
                         "tempo": e.tempo.model_dump(by_alias=True) if e.tempo else None}
                        for e in s.exercises
                    ],
                }
                for s in plan.sessions
            ],
        }
    )
target = Path(__file__).with_name("template_plans.json")
target.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
print(f"{len(out)} profiles -> {target.relative_to(ROOT)} ({target.stat().st_size // 1024} KB)")
