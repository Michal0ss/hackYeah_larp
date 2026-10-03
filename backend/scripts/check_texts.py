"""Checks the text safety rules and the recommendation text flow without a model or a key.

    python scripts/check_texts.py            run the checks (used by `make check`)
    python scripts/check_texts.py --live     also send a few scenarios to the REAL model and print the results
                                             (needs ANTHROPIC_API_KEY in the environment and costs a few cents)

The corpus is the regression suite for `app/services/safety.py`: every phrase that slipped through once goes in
BAD with the category that must catch it, every wording we want to keep goes in GOOD. Keep both lists growing.
"""

import asyncio
import json
import logging
import sys
from datetime import UTC, datetime
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

from app.ai.gateway import AIGateway, AIUnavailable, MockGateway  # noqa: E402
from app.ai.prompts import text_prompts  # noqa: E402
from app.config import Settings  # noqa: E402
from app.schemas.domain import CareFlag, DailyRecommendation, RecommendationFactor  # noqa: E402
from app.services.safety import check_generated_text  # noqa: E402
from app.services.text_service import AiText, _source_text, recommendation_text  # noqa: E402

# --- scenarios

NOW = datetime(2026, 10, 7, 8, 0, tzinfo=UTC)


def rec(decision, headline, factors, action, care=None, simulated=False) -> DailyRecommendation:
    return DailyRecommendation(
        date=NOW,
        decision=decision,
        headline=headline,
        factors=[RecommendationFactor(source=s, text=t, is_negative=n) for s, t, n in factors],
        suggested_action=action,
        care_flag=CareFlag(reason=care) if care else None,
        is_simulated=simulated,
    )


GOOD_DAY = rec(
    "train",
    "Trenuj według planu",
    [("sleep", "Sen 7 h 30 min", False), ("hrv", "HRV 46 ms, jak zwykle", False)],
    "Zrób dzisiejszą sesję tak, jak jest w planie.",
)
PROTOTYPE_DAY = rec(
    "adapt",
    "Dziś lżejszy trening",
    [
        ("sleep", "Sen 5 h 40 min", True),
        ("hrv", "HRV 38 ms, 17% poniżej twojej średniej", True),
        ("checkIn", "Stres 4/5", True),
    ],
    "Zrób o jedną serię mniej w każdym ćwiczeniu i obniż intensywność (RPE 6–7).",
)
HEAVY_DAY = rec(
    "rest",
    "Dziś regeneracja",
    [
        ("sleep", "Sen 5 h 10 min", True),
        ("hrv", "HRV 31 ms, 30% poniżej twojej średniej", True),
        ("restingHeartRate", "Tętno spoczynkowe 66 (+10)", True),
        ("checkIn", "Stres 5/5, energia 1/5", True),
    ],
    "Odpuść mocny trening. Wybierz odpoczynek albo lekką aktywność, np. spacer lub kilka minut mobilności.",
)
CARE_DAY = rec(
    "adapt",
    "Dziś trening z uwagą na technikę",
    [("technique", "Przysiad: pochylenie tułowia w 3 z 5 powtórzeń", True)],
    "Zrób o jedną serię mniej w każdym ćwiczeniu i obniż intensywność (RPE 6–7).",
    care="Ten sam sygnał („pochylenie tułowia”) pojawił się w 3 analizach z ostatnich 14 dni.",
)
SCENARIOS = {
    "dobry dzień": GOOD_DAY,
    "przykład z prototypu": PROTOTYPE_DAY,
    "ciężki dzień": HEAVY_DAY,
    "opieka": CARE_DAY,
}


CORPUS = json.loads((BACKEND / "scripts" / "text_safety_corpus.json").read_text(encoding="utf-8"))
BAD = [(item["text"], item["category"]) for item in CORPUS["bad"]]
GOOD = CORPUS["good"]
CONTRADICTIONS = [(item["decision"], item["text"]) for item in CORPUS["contradictions"]]

failures: list[str] = []


def expect(ok: bool, message: str) -> None:
    if not ok:
        failures.append(message)


def check_corpus() -> None:
    for text, category in BAD:
        problems = check_generated_text(text)
        expect(f"unsafe_phrase:{category}" in problems, f"not caught as {category}: {text!r} (got {problems})")
    for text in GOOD:
        expect(not check_generated_text(text), f"false alarm on {text!r}: {check_generated_text(text)}")
    for decision, text in CONTRADICTIONS:
        expect(
            "contradicts_decision" in check_generated_text(text, decision=decision),
            f"contradiction with {decision} not caught: {text!r}",
        )
    for case in CORPUS["numbers"]:
        source, text, caught = case["source"], case["text"], case["invented"]
        flagged = "invented_number" in check_generated_text(text, source=source)
        expect(flagged == caught, f"number check wrong for {text!r} vs {source!r}: flagged={flagged}")


# --- the examples inside text_system.md must pass our own rules

PROMPT_EXAMPLES = [
    (
        PROTOTYPE_DAY,
        "Dziś lżejszy trening",
        "Krótki sen, niższe HRV i podwyższony stres to sygnał, że warto dziś odpuścić tempo. "
        "Zrób o jedną serię mniej w każdym ćwiczeniu i obniż intensywność (RPE 6–7).",
    ),
    (
        GOOD_DAY,
        "Trenuj według planu",
        "Sen i HRV wyglądają dobrze, więc nic nie stoi na przeszkodzie. Zrób dzisiejszą sesję tak, jak jest w planie.",
    ),
    (
        HEAVY_DAY,
        "Dziś regeneracja",
        "Kilka sygnałów naraz: krótki sen, niskie HRV, wyższe tętno i duży stres. "
        "Dziś lepiej odpocząć albo wybrać lekką aktywność, na przykład spacer.",
    ),
    (
        CARE_DAY,
        "Dziś trening z uwagą na technikę",
        "W przysiadzie ten sam sygnał, czyli pochylenie tułowia, wraca w 3 z 5 powtórzeń. Zrób dziś lżejszą wersję. "
        "Jeśli to się powtarza, warto rozważyć konsultację z fizjoterapeutą.",
    ),
]


def check_prompt_examples() -> None:
    prompt = (BACKEND / "app/ai/prompts/text_system.md").read_text(encoding="utf-8")
    for scenario, headline, explanation in PROMPT_EXAMPLES:
        expect(headline in prompt and explanation in prompt, f"example missing from text_system.md: {headline!r}")
        problems = check_generated_text(
            headline, explanation, source=_source_text(scenario), decision=scenario.decision
        )
        expect(not problems, f"prompt example fails our own rules: {headline!r}: {problems}")


# --- the flow: model output -> checks -> answer


class ScriptedGateway:
    """Returns what it is told to; stands in for the model."""

    mode = "anthropic"

    def __init__(self, answer: AiText | None = None, error: Exception | None = None):
        self.answer, self.error = answer, error

    async def complete_text(self, **_) -> str:
        raise AIUnavailable("not used")

    async def complete_structured(self, **_):
        if self.error:
            raise self.error
        return self.answer

    def stream_chat(self, **_):
        raise NotImplementedError

    async def aclose(self) -> None:
        return None


async def flow(gateway: AIGateway, scenario: DailyRecommendation):
    return await recommendation_text(scenario, gateway, Settings(_env_file=None, ai_mode="mock", app_tokens=[]))


def check_flow() -> None:
    settings_ok = (
        "Krótki sen, niższe HRV i podwyższony stres to sygnał, że warto dziś zwolnić. "
        "Zrób o jedną serię mniej (RPE 6–7)."
    )
    cases = [
        ("accepted", AiText(headline="Dziś lżejszy trening", explanation=settings_ok), PROTOTYPE_DAY, "ai", []),
        (
            "unsafe phrase",
            AiText(headline="Dziś lżejszy trening", explanation="Masz zapalenie ścięgna. Weź ibuprofen."),
            PROTOTYPE_DAY,
            "template",
            ["ai_text_rejected"],
        ),
        (
            "invented number",
            AiText(headline="Dziś lżejszy trening", explanation="Spałeś tylko 3 h, więc zwolnij."),
            PROTOTYPE_DAY,
            "template",
            ["ai_text_rejected"],
        ),
        (
            "contradicts the decision",
            AiText(headline="Trenuj według planu", explanation="Sen 5 h 40 min nie przeszkadza, trenuj według planu."),
            PROTOTYPE_DAY,
            "template",
            ["ai_text_rejected"],
        ),
        (
            "care hint missing",
            AiText(
                headline="Dziś lżejszy trening",
                explanation="Pochylenie tułowia wraca w 3 z 5 powtórzeń. Zrób dziś lżejszą wersję.",
            ),
            CARE_DAY,
            "template",
            ["ai_text_rejected"],
        ),
        (
            "care hint present",
            AiText(
                headline="Trening z uwagą na technikę",
                explanation=(
                    "Pochylenie tułowia wraca w 3 z 5 powtórzeń. Zrób dziś lżejszą wersję. "
                    "Warto rozważyć konsultację z fizjoterapeutą."
                ),
            ),
            CARE_DAY,
            "ai",
            [],
        ),
    ]
    for name, answer, scenario, source, warnings in cases:
        result = asyncio.run(flow(ScriptedGateway(answer), scenario))
        expect(result.source == source, f"flow {name}: source {result.source}, wanted {source}")
        expect(result.warnings == warnings, f"flow {name}: warnings {result.warnings}, wanted {warnings}")
        if source == "template":
            expect(result.headline == scenario.headline, f"flow {name}: template must keep the engine headline")

    unavailable = asyncio.run(flow(ScriptedGateway(error=AIUnavailable("status_529")), PROTOTYPE_DAY))
    expect(unavailable.source == "template" and unavailable.warnings == ["ai_unavailable"], "flow: model down")
    mock = asyncio.run(flow(MockGateway(), PROTOTYPE_DAY))
    expect(mock.source == "template" and mock.warnings == ["ai_mock"], "flow: mock mode")


# --- optional: the real model


def live() -> int:
    import os

    from app.ai.gateway import AnthropicGateway

    if not os.environ.get("ANTHROPIC_API_KEY") and not os.environ.get("FORMA_ANTHROPIC_API_KEY"):
        print("--live needs ANTHROPIC_API_KEY in the environment.", file=sys.stderr)
        return 2
    settings = Settings(_env_file=None, ai_mode="anthropic", app_tokens=[])
    gateway = AnthropicGateway(settings)

    async def run() -> int:
        bad = 0
        for name, scenario in SCENARIOS.items():
            system, user = text_prompts(scenario)
            print(f"\n=== {name} ({scenario.decision})")
            try:
                result = await recommendation_text(scenario, gateway, settings)
            except Exception as error:  # noqa: BLE001
                print("  error:", type(error).__name__)
                bad += 1
                continue
            print(f"  source:      {result.source}   warnings: {result.warnings}")
            print(f"  headline:    {result.headline}")
            print(f"  explanation: {result.explanation}")
            if result.source != "ai":
                bad += 1
        await gateway.aclose()
        return bad

    bad = asyncio.run(run())
    print(f"\n{len(SCENARIOS) - bad}/{len(SCENARIOS)} scenarios came back from the model and passed the checks.")
    return 1 if bad else 0


def main() -> int:
    logging.disable(logging.CRITICAL)  # the services log every rejection; the checks report them themselves
    check_corpus()
    check_prompt_examples()
    check_flow()
    if failures:
        print(f"{len(failures)} text check(s) failed:", file=sys.stderr)
        for failure in failures:
            print("  -", failure, file=sys.stderr)
        return 1
    print(f"text checks ok ({len(BAD)} bad, {len(GOOD)} good, {len(CONTRADICTIONS)} contradictions, flow)")
    if "--live" in sys.argv:
        return live()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
