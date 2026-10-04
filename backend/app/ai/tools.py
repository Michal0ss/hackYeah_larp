"""Tools the coach model may ask for.

The server owns the *definitions* (names, schemas, which need consent); the *app executes* them against
local data and sends the result back as a `tool_result` block. Health data therefore never sits on the
server: it passes through only as summaries the app chose to send, and only after consent.

To add a tool: add it to TOOLS, handle it in the app (Coaching module), document it in backend/README.md.

Tools only read, with one exception that still never writes: `propose_plan_change` makes the app show a card with a
proposed change, and the plan changes only when the user taps "Zastosuj" on it.
"""

import re
from dataclasses import dataclass
from datetime import date
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

PLAN_CHANGE_KINDS = (
    "swap_exercise",
    "lighter_session",
    "move_session",
    "skip_session",
    "add_exercise",
    "remove_exercise",
    "edit_exercise",
)
# The daily step goal the coach may set (the app clamps to the same range).
_STEP_GOAL = (2000, 30000)
# Same limits as the app (Plan.PlanLimits): a number outside them is dropped, never clamped into a different change.
_SETS = (1, 8)
_REPS = (1, 100)
_SECONDS = (5, 600)
_REST = (0, 600)

TOOLS: dict[str, CoachTool] = {
    tool.name: tool
    for tool in (
        CoachTool(
            name="get_current_plan",
            description=(
                "Returns the user's training plan for the next two weeks: today's date and each session with its "
                "date (YYYY-MM-DD), weekday, exercises, sets, reps and whether it is done. Use it to answer "
                "questions about what to train and when, and to find the date of a session before proposing a "
                "change to it."
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
            name="get_training_log",
            description=(
                "Returns what the user actually did in the last days: workouts finished from the plan (date, sets done "
                "of the planned ones), the sets they logged (exercise, reps or seconds, and the weight only when they "
                "typed one) and the sets done with the live coach (tempo and technique scores). Use it to answer how "
                "training is going and to judge whether the plan is too easy or too hard. Never state a weight that "
                "is not in the result. Numbers only, no health data."
            ),
            input_schema={
                "type": "object",
                "properties": {"days": {"type": "integer", "description": "How many days back, 1 to 30."}},
            },
        ),
        CoachTool(
            name="set_step_goal",
            description=(
                "Sets the user's daily step goal, which the app shows in its health panel next to today's steps. "
                "Use it only when the user asks for a goal or agrees to your suggestion, and choose a number they can "
                "reach: a small next step (for example 500 to 1500 more than now), never a jump. A goal is a target, "
                "not a medical recommendation, and it is never a reaction to pain or an injury. Afterwards tell the "
                "user in one sentence the number you set and why."
            ),
            input_schema={
                "type": "object",
                "properties": {
                    "steps": {"type": "integer", "description": "Daily steps, 2000 to 30000."},
                    "reason": {"type": "string", "description": "One short sentence in Polish: why this number."},
                },
                "required": ["steps"],
            },
        ),
        CoachTool(
            name="suggest_consultation",
            description=(
                "Shows the user a card under your answer with a button that finds a physiotherapist nearby. It "
                "changes nothing and it is not a diagnosis. Call it yourself, once, when a conversation with a "
                "specialist is worth considering: the user describes pain in a joint or the spine, an injury, "
                "numbness, a problem that keeps coming back, gets worse or does not go away after workouts, or "
                "asks whether they should see someone; also when what you see in their data (pain reported after "
                "workouts, the same complaint again and again) points that way. Do not call it for ordinary muscle "
                "soreness, tiredness or training questions. Afterwards write one or two sentences in your own "
                "words that a consultation is worth considering and that the card below has the search; never name "
                "a cause and never say what is wrong. For sudden, dangerous symptoms (chest pain, fainting, severe "
                "shortness of breath) do not use it: point to the emergency number 112 as the health rules say."
            ),
            input_schema={"type": "object", "properties": {}},
        ),
        CoachTool(
            name="propose_plan_change",
            description=(
                "Proposes ONE change to the user's weekly plan. It does not change the plan: the app shows the "
                "user a card, and the plan changes only if the user taps the button. Use it only when the user "
                "asks for a change or agrees to your suggestion, never as a reaction to pain or an injury. "
                "kinds: swap_exercise (replace exerciseId with replacementExerciseId in the session planned on "
                "date), lighter_session (one set less in every exercise that has more than two sets, in the "
                "session on date), move_session (move the session from date to newDate, which must be a day "
                "without a session, today or later, inside the plan), skip_session (leave the session on date "
                "out; it stays in the plan as skipped and the user can put it back), add_exercise (add "
                "exerciseId to the session on date, at the end; optionally sets, repsMin, repsMax and "
                "restSeconds, otherwise the usual numbers of that session; reps are seconds for exercises "
                "counted in time), remove_exercise (take exerciseId out of the session; it keeps at least one "
                "exercise), edit_exercise (change sets, repsMin, repsMax or restSeconds of exerciseId in the "
                "session; only the numbers you send change). ALWAYS name the session by its date "
                "(YYYY-MM-DD) taken from the plan; a weekday alone is many days in a plan of several weeks. "
                'Work out dates from today\'s date in the plan ("w piątek" = the first Friday from today, '
                '"w przyszłym tygodniu" = the following week). weekday and newWeekday (1 = Monday ... '
                "7 = Sunday) are only a fallback when you have no date: they mean the next such day within a "
                "week from today. "
                "Use exercise ids from the catalog only: an exercise that is not in the catalog cannot be added. A "
                "replacement or an added exercise must come from the list of exercises that fit this person. "
                "Afterwards tell the user in one or two sentences what you propose and why, and that they can "
                "accept it on the card; never say the plan is already changed."
            ),
            input_schema={
                "type": "object",
                "properties": {
                    "kind": {"type": "string", "enum": list(PLAN_CHANGE_KINDS)},
                    "date": {
                        "type": "string",
                        "description": "Date of the session to change, YYYY-MM-DD, from the plan. Always send it.",
                    },
                    "weekday": {
                        "type": "integer",
                        "description": "Fallback when there is no date: weekday of the session, 1 to 7.",
                    },
                    "exerciseId": {
                        "type": "string",
                        "description": (
                            "swap_exercise: the exercise to replace. add_exercise: the exercise to add. "
                            "remove_exercise / edit_exercise: the exercise in the session."
                        ),
                    },
                    "replacementExerciseId": {"type": "string", "description": "swap_exercise: the new exercise."},
                    "newDate": {"type": "string", "description": "move_session: the new day, YYYY-MM-DD."},
                    "newWeekday": {
                        "type": "integer",
                        "description": "move_session fallback when there is no newDate: the new weekday, 1 to 7.",
                    },
                    "sets": {"type": "integer", "description": "add_exercise / edit_exercise: sets, 1 to 8."},
                    "repsMin": {"type": "integer", "description": "add/edit_exercise: lowest reps (or seconds)."},
                    "repsMax": {"type": "integer", "description": "add/edit_exercise: highest reps (or seconds)."},
                    "restSeconds": {"type": "integer", "description": "add_exercise / edit_exercise: rest, 0 to 600."},
                    "reason": {"type": "string", "description": "One short sentence in Polish: why."},
                },
                "required": ["kind", "date"],
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


_DAY_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def _day(value: Any) -> str | None:
    """A real calendar day written as YYYY-MM-DD, or None."""
    if not isinstance(value, str) or not _DAY_RE.match(value):
        return None
    try:
        date.fromisoformat(value)
    except ValueError:
        return None
    return value


def _whole_number(value: Any) -> int | None:
    if isinstance(value, bool) or not isinstance(value, int | float) or int(value) != value:
        return None
    return int(value)


def _normalise_plan_change(raw: dict[str, Any], content: ContentStore, profile: UserProfile | None) -> dict[str, Any]:
    """Only valid parts survive. The app checks the proposal against the real plan and answers the model with an error
    when something is missing, so a dropped field here is never silently turned into a change."""
    cleaned: dict[str, Any] = {}
    kind = raw.get("kind")
    if kind in PLAN_CHANGE_KINDS:
        cleaned["kind"] = kind
    if (day := _day(raw.get("date"))) is not None:
        cleaned["date"] = day
    if (new_day := _day(raw.get("newDate"))) is not None and kind == "move_session":
        cleaned["newDate"] = new_day
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
    if kind in ("add_exercise", "remove_exercise", "edit_exercise"):
        exercise_id = raw.get("exerciseId")
        if isinstance(exercise_id, str) and exercise_id in content.by_id:
            # An exercise that is added must fit the person (equipment, level, movements to avoid), like a replacement.
            fits = profile is None or exercise_id in {e.id for e in allowed_for(profile, content)}
            if kind != "add_exercise" or fits:
                cleaned["exerciseId"] = exercise_id
                if kind != "remove_exercise":
                    timed = content.by_id[exercise_id].timed
                    for key, (low, high) in (
                        ("sets", _SETS),
                        ("repsMin", _SECONDS if timed else _REPS),
                        ("repsMax", _SECONDS if timed else _REPS),
                        ("restSeconds", _REST),
                    ):
                        value = _whole_number(raw.get(key))
                        if value is not None and low <= value <= high:
                            cleaned[key] = value
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
    if name == "set_step_goal":
        cleaned_goal: dict[str, Any] = {}
        steps = _whole_number(raw.get("steps"))
        if steps is not None and _STEP_GOAL[0] <= steps <= _STEP_GOAL[1]:
            cleaned_goal["steps"] = steps
        reason = raw.get("reason")
        if isinstance(reason, str):
            text = sanitize_free_text(reason, 160)
            if text and not check_generated_text(text, max_total=160):
                cleaned_goal["reason"] = text
        return cleaned_goal
    if name == "get_training_log":
        return {"days": _clamped_int(raw.get("days"), 1, 30, 14)}
    if name == "get_session_feedback":
        return {"limit": _clamped_int(raw.get("limit"), 1, 10, 3)}
    if name == "get_technique_history":
        cleaned: dict[str, Any] = {"limit": _clamped_int(raw.get("limit"), 1, 10, 5)}
        exercise_id = raw.get("exerciseId")
        if isinstance(exercise_id, str) and exercise_id in content.by_id:
            cleaned["exerciseId"] = exercise_id
        return cleaned
    return {}
