"""The AI endpoints end to end (HTTP -> services -> GeminiGateway -> fake Gemini)."""

import json

from conftest import GOOD_PLAN, PROFILE, Harness, api_error, call_part, response, text_response
from google.genai import types

from app.services.safety import RED_FLAG_NOTICE

RECOMMENDATION = {
    "date": "2026-10-03T07:00:00Z",
    "decision": "adapt",
    "headline": "Dziś lżejszy trening nóg",
    "factors": [{"source": "sleep", "text": "Sen 5 h 40 min", "isNegative": True}],
    "suggestedAction": "3 serie zamiast 4.",
}


def chat(h: Harness, messages, *, stream=False, consent=False, context=None):
    return h.http.post(
        "/v1/coach/chat",
        json={"messages": messages, "stream": stream, "consent": {"health": consent}, "context": context},
    )


def sse_events(body: str) -> list[tuple[str, dict]]:
    events = []
    for block in body.strip().split("\n\n"):
        name, data = block.split("\n")
        events.append((name.removeprefix("event: "), json.loads(data.removeprefix("data: "))))
    return events


# --- health


def test_health_reports_gemini(harness):
    assert harness.http.get("/health").json()["aiMode"] == "gemini"


# --- chat


def test_chat_answer_json(harness):
    harness.models.script = [[text_response("Przysiad "), text_response("możesz zastąpić kielichowym.")]]
    result = chat(harness, [{"role": "user", "content": "Czym zastąpić przysiad?"}])
    assert result.status_code == 200
    assert result.json()["text"] == "Przysiad możesz zastąpić kielichowym."
    assert result.json()["stopReason"] == "end_turn"


def test_chat_stream_with_tool_call(harness):
    harness.models.script = [[response([call_part("get_current_plan", signature=b"S")])]]
    result = chat(harness, [{"role": "user", "content": "Co mam dziś?"}], stream=True)
    events = sse_events(result.text)
    assert [name for name, _ in events] == ["tool_use", "done"]
    assert events[0][1]["name"] == "get_current_plan" and events[0][1]["id"].startswith("gm_")
    assert events[1][1]["stopReason"] == "tool_use"


def test_chat_second_turn_carries_the_tool_result_to_the_model(harness):
    harness.models.script = [[response([call_part("get_current_plan", signature=b"S")])]]
    first = sse_events(chat(harness, [{"role": "user", "content": "Co mam dziś?"}], stream=True).text)
    call_id = first[0][1]["id"]

    harness.models.script = [[text_response("Dziś masz nogi.")]]
    result = chat(
        harness,
        [
            {"role": "user", "content": "Co mam dziś?"},
            {
                "role": "assistant",
                "content": [{"type": "tool_use", "id": call_id, "name": "get_current_plan", "input": {}}],
            },
            {
                "role": "user",
                "content": [{"type": "tool_result", "toolUseId": call_id, "content": '{"today": "Nogi"}'}],
            },
        ],
    )
    assert result.json()["text"] == "Dziś masz nogi."
    sent = harness.models.calls[-1].contents
    assert sent[1].parts[0].thought_signature == b"S"
    assert sent[2].parts[0].function_response.response == {"output": {"today": "Nogi"}}


def test_health_tools_are_offered_only_with_consent(harness):
    def offered(consent: bool) -> set[str]:
        harness.models.script = [[text_response("ok")]]
        chat(harness, [{"role": "user", "content": "hej"}], consent=consent)
        declarations = harness.models.calls[-1].config.tools[0].function_declarations
        return {d.name for d in declarations}

    without = offered(False)
    with_consent = offered(True)
    assert {"get_recovery_summary", "get_checkins", "get_today_recommendation"} <= with_consent
    assert not {"get_recovery_summary", "get_checkins", "get_today_recommendation"} & without
    assert {"get_current_plan", "get_technique_history"} <= without


def test_health_history_without_consent_is_rejected_before_the_model(harness):
    result = chat(
        harness,
        [
            {"role": "user", "content": "sen?"},
            {
                "role": "assistant",
                "content": [{"type": "tool_use", "id": "gm_1", "name": "get_recovery_summary", "input": {}}],
            },
            {"role": "user", "content": [{"type": "tool_result", "toolUseId": "gm_1", "content": "{}"}]},
        ],
    )
    assert result.status_code == 422 and result.json()["error"]["code"] == "consent_required"
    assert harness.models.calls == []


def test_red_flag_message_gets_the_safety_notice_first(harness):
    harness.models.script = [[text_response("Daj znać, jak się czujesz.")]]
    result = chat(harness, [{"role": "user", "content": "Mam ból w klatce piersiowej podczas treningu"}])
    assert result.json()["text"].startswith(RED_FLAG_NOTICE)


def test_chat_survives_one_model_being_down(harness):
    harness.models.script = [api_error(429), [text_response("Jestem.")]]
    result = chat(harness, [{"role": "user", "content": "hej"}])
    assert result.status_code == 200 and result.json()["text"] == "Jestem."


def test_chat_when_every_model_is_down_answers_503(harness):
    harness.models.script = [api_error(429), api_error(503), api_error(404)]
    result = chat(harness, [{"role": "user", "content": "hej"}])
    assert result.status_code == 503
    assert result.json()["error"]["code"] == "ai_unavailable"
    assert result.headers["retry-after"] == "5"


def test_chat_stream_reports_failures_as_an_error_event(harness):
    harness.models.script = [api_error(429), api_error(503), api_error(404)]
    events = sse_events(chat(harness, [{"role": "user", "content": "hej"}], stream=True).text)
    assert [name for name, _ in events] == ["error"]
    assert events[0][1]["code"] == "ai_unavailable"


def test_chat_blocked_answer_is_an_error_not_a_silence(harness):
    harness.models.script = [[text_response("x", finish=types.FinishReason.SAFETY)]]
    events = sse_events(chat(harness, [{"role": "user", "content": "hej"}], stream=True).text)
    assert events[-1][0] == "error"


def test_model_asking_for_a_tool_it_was_not_offered_is_ignored(harness):
    harness.models.script = [[response([call_part("get_recovery_summary")])]]
    result = chat(harness, [{"role": "user", "content": "jak spałam?"}], consent=False)
    assert result.status_code == 200 and result.json()["toolUses"] == []


def test_tool_input_is_cleaned(harness):
    harness.models.script = [[response([call_part("get_checkins", {"days": 999, "evil": "x"})])]]
    result = chat(harness, [{"role": "user", "content": "nastrój?"}], consent=True)
    assert result.json()["toolUses"][0]["input"] == {"days": 14}


# --- plans


def test_plan_from_the_model(harness):
    harness.models.script = [text_response(json.dumps(GOOD_PLAN))]
    result = harness.http.post("/v1/plans/generate", json={"profile": PROFILE}).json()
    assert result["plan"]["source"] == "ai" and result["warnings"] == []
    assert [s["weekday"] for s in result["plan"]["sessions"]] == [1, 4]


def test_plan_with_unknown_exercise_is_replaced_by_the_template(harness):
    bad = json.loads(json.dumps(GOOD_PLAN))
    bad["sessions"][0]["exercises"][0]["exerciseId"] = "does_not_exist"
    harness.models.script = [text_response(json.dumps(bad))]
    result = harness.http.post("/v1/plans/generate", json={"profile": PROFILE}).json()
    assert result["plan"]["source"] == "template" and result["warnings"] == ["ai_invalid_plan"]


def test_plan_with_equipment_the_user_lacks_is_rejected(harness):
    bad = json.loads(json.dumps(GOOD_PLAN))
    bad["sessions"][0]["exercises"][0]["exerciseId"] = "back_squat"  # gym only
    harness.models.script = [text_response(json.dumps(bad))]
    result = harness.http.post("/v1/plans/generate", json={"profile": PROFILE}).json()
    assert result["plan"]["source"] == "template" and result["warnings"] == ["ai_invalid_plan"]


def test_plan_survives_garbage_and_outages(harness):
    harness.models.script = [text_response("{not json")]
    result = harness.http.post("/v1/plans/generate", json={"profile": PROFILE}).json()
    assert result["plan"]["source"] == "template" and result["warnings"] == ["ai_unavailable"]

    harness.models.script = [api_error(429), api_error(503), api_error(404)]
    result = harness.http.post("/v1/plans/generate", json={"profile": PROFILE})
    assert result.status_code == 200
    assert result.json()["plan"]["source"] == "template" and result.json()["warnings"] == ["ai_unavailable"]


def test_template_plan_respects_the_profile_even_when_the_model_is_down(harness):
    harness.models.script = [api_error(503), api_error(503), api_error(503)]
    profile = {**PROFILE, "avoidTags": ["deepSquats", "deepLunges"], "equipment": "none"}
    plan = harness.http.post("/v1/plans/generate", json={"profile": profile}).json()["plan"]
    ids = {e["exerciseId"] for s in plan["sessions"] for e in s["exercises"]}
    assert len(plan["sessions"]) == 2 and ids
    assert not ids & {"squat", "goblet_squat", "back_squat", "lunge", "jump_squat"}


# --- recommendation text


def text_request(h: Harness):
    return h.http.post("/v1/texts/recommendation", json={"recommendation": RECOMMENDATION}).json()


def test_recommendation_text_from_the_model(harness):
    harness.models.script = [
        text_response(json.dumps({"headline": "Lżejszy dzień nóg", "explanation": "Krótszy sen. Zrób 3 serie."}))
    ]
    result = text_request(harness)
    assert result["source"] == "ai" and result["headline"] == "Lżejszy dzień nóg"


def test_unsafe_recommendation_text_is_replaced(harness):
    harness.models.script = [
        text_response(json.dumps({"headline": "Diagnoza", "explanation": "To jest zapalenie ścięgna, weź ibuprofen."}))
    ]
    result = text_request(harness)
    assert result["source"] == "template" and result["warnings"] == ["ai_text_rejected"]
    assert result["headline"] == RECOMMENDATION["headline"]


def test_recommendation_text_when_the_model_is_down(harness):
    harness.models.script = [api_error(429), api_error(503), api_error(404)]
    result = text_request(harness)
    assert result["source"] == "template" and result["warnings"] == ["ai_unavailable"]
