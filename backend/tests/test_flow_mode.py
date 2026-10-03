"""Questions asked in the middle of a workout: short answers, little thinking (no model, no network)."""

import pytest
from conftest import PROFILE
from pydantic import ValidationError

from app.ai.gemini import _thinking
from app.ai.prompts import describe_workout
from app.config import DEFAULT_CONTENT_DIR, Settings
from app.content.store import ContentStore
from app.schemas.api import CoachChatRequest, WorkoutContext
from app.services.coach_service import prepare_conversation


def request(screen: str | None) -> CoachChatRequest:
    context = {"profile": PROFILE, "workout": {"screen": screen} if screen else None}
    return CoachChatRequest.model_validate(
        {"messages": [{"role": "user", "content": "Ile odpoczywać?"}], "context": context, "stream": False}
    )


@pytest.mark.parametrize("screen", ["liveSet", "setSummary", "rest", "sessionFeedback"])
def test_workout_screens_are_fast(screen):
    content = ContentStore.load(DEFAULT_CONTENT_DIR)
    assert prepare_conversation(request(screen), content, Settings()).in_workout


@pytest.mark.parametrize("screen", [None, "today", "plan", "analysis"])
def test_other_screens_are_not(screen):
    content = ContentStore.load(DEFAULT_CONTENT_DIR)
    assert not prepare_conversation(request(screen), content, Settings()).in_workout


def test_fast_thinks_less_on_gemini_3_and_changes_nothing_elsewhere():
    assert str(_thinking("gemini-3.5-flash").thinking_level).endswith("LOW")
    assert str(_thinking("gemini-3.5-flash", fast=True).thinking_level).endswith("MINIMAL")
    assert _thinking("gemini-2.5-flash", fast=True).thinking_budget == 0


def test_the_workout_block_asks_for_a_short_answer_and_names_the_set():
    content = ContentStore.load(DEFAULT_CONTENT_DIR)
    text = describe_workout(
        WorkoutContext.model_validate({"screen": "rest", "exerciseId": "squat", "setIndex": 2}), content
    )
    assert "do 45 słów" in text
    assert "seria 2" in text


def test_a_typed_set_is_described_with_its_weight_and_the_planned_range():
    content = ContentStore.load(DEFAULT_CONTENT_DIR)
    workout = WorkoutContext.model_validate(
        {
            "screen": "rest",
            "exerciseId": "goblet_squat",
            "setIndex": 2,
            "loggedSet": {"setIndex": 2, "reps": 8, "weightKg": 17.5, "plannedMin": 6, "plannedMax": 8},
        }
    )
    text = describe_workout(workout, content)
    assert "8 powtórzeń" in text
    assert "ciężar 17,5 kg" in text
    assert "w planie 6-8" in text


def test_without_a_weight_the_coach_is_told_not_to_guess_one():
    content = ContentStore.load(DEFAULT_CONTENT_DIR)
    workout = WorkoutContext.model_validate(
        {"screen": "rest", "loggedSet": {"setIndex": 1, "seconds": 45}},
    )
    text = describe_workout(workout, content)
    assert "45 s" in text
    assert "bez wpisanego ciężaru" in text
    assert "nie zgaduj" in text


def test_a_weight_out_of_range_is_refused():
    with pytest.raises(ValidationError):
        WorkoutContext.model_validate({"screen": "rest", "loggedSet": {"setIndex": 1, "weightKg": 9000}})
