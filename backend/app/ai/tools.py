"""Tools the coach model may ask for.

The server owns the *definitions* (names, schemas, which need consent); the *app executes* them against
local data and sends the result back as a `tool_result` block. Health data therefore never sits on the
server: it passes through only as summaries the app chose to send, and only after consent.

To add a tool: add it to TOOLS, handle it in the app (Coaching module), document it in backend/README.md.

Tools only read, with one exception that still never writes: `propose_plan_change` makes the app show a card with a
proposed change, and the plan changes only when the user taps "Zastosuj" on it.
"""

from dataclasses import dataclass
from typing import Any

from app.content.store import ContentStore
from app.schemas.domain import UserProfile
from app.services.plan_builder import allowed_for
from app.services.safety import check_generated_text, sanitize_free_text


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

PLAN_CHANGE_KINDS = ("swap_exercise", "lighter_session", "move_session")

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
        CoachTool(
            name="get_session_feedback",
            description=(
                "Returns the user's feedback after recent workouts: how hard it felt (RPE, 1 to 10), enjoyment, "
                "areas of discomfort with their intensity and how many of the planned sets were done. "
                "Free-text notes are never included."
            ),
            input_schema={
                "type": "object",
                "properties": {"limit": {"type": "integer", "description": "How many workouts, 1 to 10."}},
            },
            needs_health_consent=True,
        ),
        CoachTool(
            name="propose_plan_change",
            description=(
                "Proposes ONE change to the user's weekly plan. It does not change the plan: the app shows the "
                "user a card, and the plan changes only if the user taps the button. Use it only when the user "
                "asks for a change or agrees to your suggestion, never as a reaction to pain or an injury. "
                "kinds: swap_exercise (replace exerciseId with replacementExerciseId in the session planned on "
                "weekday), lighter_session (one set less in every exercise that has more than two sets, in the "
                "session on weekday), move_session (move the session from weekday to newWeekday, which must be a "
                "day without a session). weekday and newWeekday: 1 = Monday ... 7 = Sunday. Use exercise ids from "
                "the catalog; a replacement must come from the list of exercises that fit this person. "
                "Afterwards tell the user in one or two sentences what you propose and why, and that they can "
                "accept it on the card; never say the plan is already changed."
            ),
            input_schema={
                "type": "object",
                "properties": {
                    "kind": {"type": "string", "enum": list(PLAN_CHANGE_KINDS)},
                    "weekday": {"type": "integer", "description": "Weekday of the session to change, 1 to 7."},
                    "exerciseId": {"type": "string", "description": "swap_exercise: the exercise to replace."},
                    "replacementExerciseId": {"type": "string", "description": "swap_exercise: the new exercise."},
                    "newWeekday": {"type": "integer", "description": "move_session: the new weekday, 1 to 7."},
                    "reason": {"type": "string", "description": "One short sentence in Polish: why."},
                },
                "required": ["kind", "weekday"],
            },
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


def _weekday(value: Any) -> int | None:
    if isinstance(value, bool) or not isinstance(value, int | float) or int(value) != value:
        return None
    return int(value) if 1 <= int(value) <= 7 else None


def _normalise_plan_change(raw: dict[str, Any], content: ContentStore, profile: UserProfile | None) -> dict[str, Any]:
    """Only valid parts survive. The app checks the proposal against the real plan and answers the model with an error
    when something is missing, so a dropped field here is never silently turned into a change."""
    cleaned: dict[str, Any] = {}
    kind = raw.get("kind")
    if kind in PLAN_CHANGE_KINDS:
        cleaned["kind"] = kind
    if (weekday := _weekday(raw.get("weekday"))) is not None:
        cleaned["weekday"] = weekday
    if (new_weekday := _weekday(raw.get("newWeekday"))) is not None and kind == "move_session":
        cleaned["newWeekday"] = new_weekday
    if kind == "swap_exercise":
        exercise_id = raw.get("exerciseId")
        if isinstance(exercise_id, str) and exercise_id in content.by_id:
            cleaned["exerciseId"] = exercise_id
        replacement = raw.get("replacementExerciseId")
        if isinstance(replacement, str) and replacement in content.by_id and replacement != exercise_id:
            # With a profile the replacement must also fit the person (equipment, level, movements to avoid).
            if profile is None or replacement in {e.id for e in allowed_for(profile, content)}:
                cleaned["replacementExerciseId"] = replacement
    reason = raw.get("reason")
    # The reason is shown to the user as a quote, so it must pass the same checks as other generated copy (no
    # diagnoses, medicines, promises, links); a text that does not is simply left out.
    if isinstance(reason, str):
        text = sanitize_free_text(reason, 160)
        if text and not check_generated_text(text, max_total=160):
            cleaned["reason"] = text
    return cleaned


def normalise_tool_input(
    name: str, raw: dict[str, Any], content: ContentStore, profile: UserProfile | None = None
) -> dict[str, Any]:
    """Keeps only known keys with valid values, so the app never receives malformed model output."""
    if name == "propose_plan_change":
        return _normalise_plan_change(raw, content, profile)
    if name in ("get_recovery_summary", "get_checkins"):
        return {"days": _clamped_int(raw.get("days"), 1, 14, 7)}
    if name == "get_session_feedback":
        return {"limit": _clamped_int(raw.get("limit"), 1, 10, 3)}
    if name == "get_technique_history":
        cleaned: dict[str, Any] = {"limit": _clamped_int(raw.get("limit"), 1, 10, 5)}
        exercise_id = raw.get("exerciseId")
        if isinstance(exercise_id, str) and exercise_id in content.by_id:
            cleaned["exerciseId"] = exercise_id
        return cleaned
    return {}
