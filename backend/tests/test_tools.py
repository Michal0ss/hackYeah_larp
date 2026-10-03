"""Tool definitions and the normalising of what the model sends (no model, no network)."""

from app.ai.tools import PLAN_CHANGE_KINDS, TOOLS, normalise_tool_input, tools_for
from app.config import DEFAULT_CONTENT_DIR
from app.content.store import ContentStore


def content() -> ContentStore:
    return ContentStore.load(DEFAULT_CONTENT_DIR)


def test_skip_is_a_plan_change_kind_and_is_kept():
    assert "skip_session" in PLAN_CHANGE_KINDS
    raw = {"kind": "skip_session", "weekday": 3, "newWeekday": 5}
    kept = normalise_tool_input("propose_plan_change", raw, content())
    # newWeekday belongs to move_session only.
    assert kept == {"kind": "skip_session", "weekday": 3}


def test_an_unknown_kind_is_dropped():
    cleaned = normalise_tool_input("propose_plan_change", {"kind": "delete_everything", "weekday": 2}, content())
    assert "kind" not in cleaned


def test_training_log_needs_no_health_consent_and_clamps_days():
    assert not TOOLS["get_training_log"].needs_health_consent
    assert "get_training_log" in {tool["name"] for tool in tools_for(health_consent=False)}
    assert normalise_tool_input("get_training_log", {"days": 500}, content()) == {"days": 30}
    assert normalise_tool_input("get_training_log", {"days": 0}, content()) == {"days": 1}
    assert normalise_tool_input("get_training_log", {}, content()) == {"days": 14}
    assert normalise_tool_input("get_training_log", {"days": "x"}, content()) == {"days": 14}
