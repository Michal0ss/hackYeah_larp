"""GeminiGateway against a fake client: model chain, cooldown, errors, tool translation, streaming."""

import json

import httpx
import pytest
from conftest import FALLBACKS, GOOD_PLAN, PRIMARY, Harness, api_error, call_part, response, text_response
from google.genai import types

from app.ai.gateway import AIUnavailable, Finished, TextDelta, ToolCall
from app.ai.gemini import PLACEHOLDER_SIGNATURE, _inline_refs, _thinking
from app.services.plan_service import PlanDraft

SECOND, THIRD = FALLBACKS


def structured(h: Harness):
    return h.run(
        h.gateway.complete_structured(
            kind="plan", model=PRIMARY, system="s", user="u", schema=PlanDraft, max_tokens=100
        )
    )


def collect(h: Harness, messages=None, tools=None) -> list:
    async def go():
        return [
            event
            async for event in h.gateway.stream_chat(
                model=PRIMARY,
                system="s",
                messages=messages or [{"role": "user", "content": "hej"}],
                tools=tools or [],
                max_tokens=100,
            )
        ]

    return h.run(go())


# --- one-shot answers


def test_structured_answer_is_parsed(harness):
    harness.models.script = [text_response(json.dumps(GOOD_PLAN))]
    plan = structured(harness)
    assert [s.title for s in plan.sessions] == ["Całe ciało", "Całe ciało B"]
    config = harness.models.calls[0].config
    assert config.response_mime_type == "application/json"
    assert "sessions" in config.response_json_schema["properties"]


def test_quota_error_moves_to_next_model_and_cools_the_first(harness):
    harness.models.script = [api_error(429), text_response(json.dumps(GOOD_PLAN))]
    structured(harness)
    assert harness.models_called() == [PRIMARY, SECOND]

    # The next request does not try the model that is out of quota.
    harness.models.script = [text_response(json.dumps(GOOD_PLAN))]
    structured(harness)
    assert harness.models_called() == [PRIMARY, SECOND, SECOND]

    # ...until the cooldown (5 min for 429) is over.
    harness.clock.now += 301
    harness.models.script = [text_response(json.dumps(GOOD_PLAN))]
    structured(harness)
    assert harness.models_called()[-1] == PRIMARY


def test_retired_model_stays_out_longer(harness):
    harness.models.script = [api_error(404), text_response(json.dumps(GOOD_PLAN))]
    structured(harness)
    harness.clock.now += 301  # past the 429 cooldown, but a 404 lasts an hour
    harness.models.script = [text_response(json.dumps(GOOD_PLAN))]
    structured(harness)
    assert harness.models_called() == [PRIMARY, SECOND, SECOND]
    harness.clock.now += 3600
    harness.models.script = [text_response(json.dumps(GOOD_PLAN))]
    structured(harness)
    assert harness.models_called()[-1] == PRIMARY


@pytest.mark.parametrize(
    "failure", [api_error(503), api_error(500), httpx.ReadTimeout("slow"), httpx.ConnectError("x")]
)
def test_transient_failures_move_to_next_model(harness, failure):
    harness.models.script = [failure, text_response(json.dumps(GOOD_PLAN))]
    structured(harness)
    assert harness.models_called() == [PRIMARY, SECOND]


def test_every_model_failing_raises_and_all_were_tried(harness):
    harness.models.script = [api_error(429), api_error(503), api_error(404)]
    with pytest.raises(AIUnavailable) as caught:
        structured(harness)
    assert caught.value.reason == "status_404"
    assert harness.models_called() == [PRIMARY, SECOND, THIRD]


def test_with_all_models_cooling_the_first_is_still_tried(harness):
    harness.models.script = [api_error(429), api_error(429), api_error(429)]
    with pytest.raises(AIUnavailable):
        structured(harness)
    harness.models.script = [text_response(json.dumps(GOOD_PLAN))]
    structured(harness)
    assert harness.models_called()[-1] == PRIMARY


def test_bad_request_does_not_fall_back(harness):
    harness.models.script = [api_error(400)]
    with pytest.raises(AIUnavailable) as caught:
        structured(harness)
    assert caught.value.reason == "status_400"
    assert harness.models_called() == [PRIMARY]


def test_without_fallback_models_the_error_goes_straight_up():
    h = Harness(fallbacks=[])
    h.models.script = [api_error(503)]
    with pytest.raises(AIUnavailable) as caught:
        structured(h)
    assert caught.value.reason == "status_503"


@pytest.mark.parametrize(
    ("reply", "reason"),
    [
        (text_response("x", finish=types.FinishReason.SAFETY), "blocked"),
        (text_response("{", finish=types.FinishReason.MAX_TOKENS), "max_tokens"),
        (text_response(""), "empty_output_stop"),
        (text_response("{not json"), "invalid_output"),
        (text_response('{"sessions": "no"}'), "invalid_output"),
    ],
)
def test_unusable_answers_are_reported_without_fallback(harness, reply, reason):
    harness.models.script = [reply]
    with pytest.raises(AIUnavailable) as caught:
        structured(harness)
    assert caught.value.reason == reason
    assert harness.models_called() == [PRIMARY]


def test_thoughts_are_not_part_of_the_answer(harness):
    harness.models.script = [
        response([types.Part(text="rozumuję...", thought=True), types.Part(text=json.dumps(GOOD_PLAN))])
    ]
    assert len(structured(harness).sessions) == 2


# --- configuration the gateway builds


def test_thinking_is_kept_low_per_model_family():
    assert _thinking("gemini-3.5-flash").thinking_level == types.ThinkingLevel.LOW
    assert _thinking("gemini-2.5-flash").thinking_budget == 0
    assert _thinking("gemini-flash-latest") is None


def test_schema_refs_are_inlined_and_field_named_title_survives():
    schema = _inline_refs(PlanDraft.model_json_schema(by_alias=True))
    assert "$ref" not in json.dumps(schema) and "$defs" not in schema
    session = schema["properties"]["sessions"]["items"]
    assert set(session["properties"]) == {"weekday", "title", "exercises"}
    assert session["required"] == ["weekday", "title", "exercises"]


def test_tools_without_parameters_are_declared_without_a_schema(harness):
    tools = harness.gateway.to_tools(
        [
            {"name": "a", "description": "d", "input_schema": {"type": "object", "properties": {}}},
            {
                "name": "b",
                "description": "d",
                "input_schema": {"type": "object", "properties": {"days": {"type": "integer"}}},
            },
        ]
    )
    declared = {d.name: d for d in tools[0].function_declarations}
    assert declared["a"].parameters_json_schema is None
    assert declared["b"].parameters_json_schema["properties"]["days"] == {"type": "integer"}
    assert harness.gateway.to_tools([]) is None


# --- chat streaming


def test_stream_text_and_usage(harness):
    harness.models.script = [[text_response("Cześć, "), text_response("jak mogę pomóc?", usage=(120, 30))]]
    events = collect(harness)
    assert "".join(e.text for e in events if isinstance(e, TextDelta)) == "Cześć, jak mogę pomóc?"
    assert events[-1] == Finished("end_turn", 120, 30)
    config = harness.models.calls[0].config
    assert config.automatic_function_calling.disable is True


def test_stream_tool_call_gets_our_id_and_signature_survives_the_next_turn(harness):
    harness.models.script = [[response([call_part("get_current_plan", signature=b"SIG")])]]
    events = collect(harness)
    call = next(e for e in events if isinstance(e, ToolCall))
    assert call.id.startswith("gm_") and call.name == "get_current_plan"
    assert events[-1].stop_reason == "tool_use"

    conversation = [
        {"role": "user", "content": [{"type": "text", "text": "plan?"}]},
        {"role": "assistant", "content": [{"type": "tool_use", "id": call.id, "name": call.name, "input": {}}]},
        {
            "role": "user",
            "content": [{"type": "tool_result", "tool_use_id": call.id, "content": '{"today": "Nogi"}'}],
        },
    ]
    sent = harness.gateway.to_contents(conversation, PRIMARY)
    function_call = sent[1].parts[0]
    assert function_call.thought_signature == b"SIG" and function_call.function_call.id is None
    response_part = sent[2].parts[0].function_response
    assert response_part.name == "get_current_plan" and response_part.response == {"output": {"today": "Nogi"}}

    # Another model must not receive a signature it did not issue.
    other = harness.gateway.to_contents(conversation, SECOND)
    assert other[1].parts[0].thought_signature == PLACEHOLDER_SIGNATURE


def test_second_call_of_one_step_has_no_placeholder(harness):
    conversation = [
        {
            "role": "assistant",
            "content": [
                {"type": "tool_use", "id": "gm_1", "name": "a", "input": {}},
                {"type": "tool_use", "id": "gm_2", "name": "b", "input": {}},
            ],
        }
    ]
    parts = harness.gateway.to_contents(conversation, PRIMARY)[0].parts
    assert [p.thought_signature for p in parts] == [PLACEHOLDER_SIGNATURE, None]


def test_tool_error_result_is_marked_as_error(harness):
    conversation = [
        {"role": "assistant", "content": [{"type": "tool_use", "id": "gm_1", "name": "a", "input": {}}]},
        {
            "role": "user",
            "content": [{"type": "tool_result", "tool_use_id": "gm_1", "content": "brak danych", "is_error": True}],
        },
    ]
    result = harness.gateway.to_contents(conversation, PRIMARY)[1].parts[0].function_response
    assert result.response == {"error": "brak danych"}


def test_stream_fallback_when_the_first_model_fails_before_any_output(harness):
    harness.models.script = [api_error(503), [text_response("Dzień dobry")]]
    events = collect(harness)
    assert harness.models_called() == [PRIMARY, SECOND]
    assert events[0] == TextDelta("Dzień dobry")


def test_stream_does_not_switch_model_after_text_was_sent(harness):
    harness.models.script = [[text_response("Zaczynam"), api_error(503)]]

    async def go():
        seen = []
        try:
            async for event in harness.gateway.stream_chat(
                model=PRIMARY, system="s", messages=[{"role": "user", "content": "hej"}], tools=[], max_tokens=100
            ):
                seen.append(event)
        except AIUnavailable as exc:
            return seen, exc
        return seen, None

    seen, error = harness.run(go())
    assert seen == [TextDelta("Zaczynam")] and error.reason == "status_503"
    assert harness.models_called() == [PRIMARY]


def test_stream_blocked_and_empty_and_malformed_are_errors(harness):
    for reply, reason in [
        ([text_response("x", finish=types.FinishReason.SAFETY)], "blocked"),
        ([response([], finish=types.FinishReason.STOP)], "empty_output"),
        ([response([], finish=types.FinishReason.MALFORMED_FUNCTION_CALL)], "malformed_tool_call"),
    ]:
        harness.models.script = [reply]
        with pytest.raises(AIUnavailable) as caught:
            collect(harness)
        assert caught.value.reason == reason


def test_cut_off_tool_call_is_never_forwarded(harness):
    harness.models.script = [[response([call_part("get_current_plan")], finish=types.FinishReason.MAX_TOKENS)]]
    events = collect(harness)
    assert not any(isinstance(e, ToolCall) for e in events)
    assert events[-1].stop_reason == "max_tokens"
