"""The coach names a session by its date: tool input, the plan in the prompt and the schema (no model, no network)."""

from app.ai.prompts import coach_system_prompt
from app.ai.tools import TOOLS, normalise_tool_input
from app.config import DEFAULT_CONTENT_DIR
from app.content.store import ContentStore
from app.schemas.api import CoachContext, Consent, SessionDigest, TrainingSnapshot
from app.schemas.domain import UserProfile


def content() -> ContentStore:
    return ContentStore.load(DEFAULT_CONTENT_DIR)


def test_a_real_date_is_kept_and_new_date_belongs_to_move_session_only():
    kept = normalise_tool_input(
        "propose_plan_change", {"kind": "move_session", "date": "2026-10-09", "newDate": "2026-10-13"}, content()
    )
    assert kept == {"kind": "move_session", "date": "2026-10-09", "newDate": "2026-10-13"}
    skipped = normalise_tool_input(
        "propose_plan_change", {"kind": "skip_session", "date": "2026-10-09", "newDate": "2026-10-13"}, content()
    )
    assert skipped == {"kind": "skip_session", "date": "2026-10-09"}


def test_a_date_that_is_not_a_real_day_is_dropped():
    for bad in ("2026-02-30", "14.10.2026", "środa", "2026-13-01", 20261014, None):
        cleaned = normalise_tool_input("propose_plan_change", {"kind": "skip_session", "date": bad}, content())
        assert "date" not in cleaned, bad


def test_the_tool_asks_for_the_date_not_the_weekday():
    schema = TOOLS["propose_plan_change"].definition()["input_schema"]
    assert "date" in schema["required"]
    assert "weekday" not in schema["required"]
    assert {"date", "newDate", "weekday", "newWeekday"} <= set(schema["properties"])


def _prompt(snapshot: TrainingSnapshot) -> str:
    profile = UserProfile(goal="fitness", level="beginner", days_per_week=3, session_minutes=45, equipment="none")
    return coach_system_prompt(content(), CoachContext(profile=profile, snapshot=snapshot), Consent())


def _session(weekday: int, date: str | None) -> SessionDigest:
    return SessionDigest(weekday=weekday, date=date, title="Nogi", status="planned", exercises=[])


def test_the_prompt_tells_todays_date_and_dates_every_session():
    snapshot = TrainingSnapshot(
        today=7,
        today_date="2026-10-04",
        next_session=_session(1, "2026-10-05"),
        next_session_is_today=False,
        week=[_session(1, "2026-10-05"), _session(3, "2026-10-07"), _session(5, "2026-10-09")],
    )
    text = _prompt(snapshot)
    assert "Dziś jest niedziela, 4 października 2026 (data 2026-10-04)" in text
    assert "najbliższa to poniedziałek 5 października 2026 (data 2026-10-05)" in text
    assert "środa 7 października 2026 (data 2026-10-07)" in text
    assert "piątek 9 października 2026 (data 2026-10-09)" in text
    # The session described as the nearest one is not listed a second time.
    assert text.count("data 2026-10-05") == 1


def test_a_plan_without_dates_reads_as_before():
    snapshot = TrainingSnapshot(today=3, next_session=_session(3, None), week=[_session(1, None), _session(3, None)])
    text = _prompt(snapshot)
    assert "Dziś jest środa." in text
    assert "Dzisiejsza sesja (środa (dzień 3))" in text
    assert "poniedziałek (dzień 1)" in text
