"""Tools the coach model may ask for.

The server owns the *definitions* (names, schemas, which need consent); the *app executes* them against
local data and sends the result back as a `tool_result` block. Health data therefore never sits on the
server: it passes through only as summaries the app chose to send, and only after consent.

To add a tool: add it to TOOLS, handle it in the app (Coaching module), document it in backend/README.md.
"""

from dataclasses import dataclass
from typing import Any

from app.content.store import ContentStore


@dataclass(frozen=True)
class CoachTool:
    name: str
    description: str
    input_schema: dict[str, Any]
    # Reads health data (Apple Health, check-ins, recommendations derived from them).
    needs_health_consent: bool = False

    def definition(self) -> dict[str, Any]:
        return {"name": self.name, "description": self.description, "input_schema": self.input_schema}


_NO_INPUT: dict[str, Any] = {"type": "object", "properties": {}}

TOOLS: dict[str, CoachTool] = {
    tool.name: tool
    for tool in (
        CoachTool(
            name="get_current_plan",
            description=(
                "Returns the user's current weekly training plan: each session with weekday, exercises, sets, "
                "reps and whether it is done. Use it to answer questions about what to train and when."
            ),
            input_schema=_NO_INPUT,
        ),
        CoachTool(
            name="get_technique_history",
            description=(
                "Returns the user's most recent technique analyses (from video analysed on the phone): "
                "exercise, date, overall score and the main findings. Optionally filter by exercise id."
            ),
            input_schema={
                "type": "object",
                "properties": {
                    "exerciseId": {"type": "string", "description": "Exercise id from the catalog."},
                    "limit": {"type": "integer", "description": "How many analyses, 1 to 10."},
                },
            },
        ),
        CoachTool(
            name="get_today_recommendation",
            description=(
                "Returns today's recommendation (train, adapt or rest) with the factors behind it, "
                "computed on the phone from sleep, heart rate variability, resting heart rate and the check-in."
            ),
            input_schema=_NO_INPUT,
            needs_health_consent=True,
        ),
        CoachTool(
            name="get_recovery_summary",
            description=(
                "Returns a summary of recovery over the last days: sleep duration, heart rate variability "
                "and resting heart rate compared with the user's own baseline. Summaries only, no raw samples."
            ),
            input_schema={
                "type": "object",
                "properties": {"days": {"type": "integer", "description": "Number of days, 1 to 14."}},
            },
            needs_health_consent=True,
        ),
        CoachTool(
            name="get_checkins",
            description=(
                "Returns the user's recent daily check-ins: mood, stress and energy on a 1 to 5 scale, with averages. "
                "Free-text notes are never included."
            ),
            input_schema={
                "type": "object",
                "properties": {"days": {"type": "integer", "description": "Number of days, 1 to 14."}},
            },
            needs_health_consent=True,
        ),
    )
}


def tools_for(health_consent: bool) -> list[dict[str, Any]]:
    """Definitions the model may see. Without consent the health tools are not even offered."""
    return [tool.definition() for tool in TOOLS.values() if health_consent or not tool.needs_health_consent]


def is_health_tool(name: str) -> bool:
    tool = TOOLS.get(name)
    return bool(tool and tool.needs_health_consent)


def _clamped_int(value: Any, low: int, high: int, default: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int | float):
        return default
    return max(low, min(high, int(value)))


def normalise_tool_input(name: str, raw: dict[str, Any], content: ContentStore) -> dict[str, Any]:
    """Keeps only known keys with valid values, so the app never receives malformed model output."""
    if name in ("get_recovery_summary", "get_checkins"):
        return {"days": _clamped_int(raw.get("days"), 1, 14, 7)}
    if name == "get_technique_history":
        cleaned: dict[str, Any] = {"limit": _clamped_int(raw.get("limit"), 1, 10, 5)}
        exercise_id = raw.get("exerciseId")
        if isinstance(exercise_id, str) and exercise_id in content.by_id:
            cleaned["exerciseId"] = exercise_id
        return cleaned
    return {}
