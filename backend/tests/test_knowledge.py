"""Knowledge base for the coach: loading, retrieval quality, the prompt block and the chat end to end."""

from pathlib import Path

import pytest
from conftest import Harness, text_response

from app.ai import knowledge
from app.ai.knowledge import KnowledgeBase, knowledge_block, tokens

NOTES = Path(__file__).resolve().parents[2] / "content" / "knowledge"


@pytest.fixture(scope="module")
def base() -> KnowledgeBase:
    return KnowledgeBase.load(NOTES)


# --- the shipped notes


def test_notes_load_and_every_fragment_names_its_source(base):
    assert len(base) >= 30
    for chunk in base.chunks:
        assert chunk.title and chunk.text, chunk.id
        assert chunk.source and chunk.url.startswith("https://"), chunk.id
        assert chunk.license, chunk.id
        assert len(chunk.text) < 1500, f"{chunk.id} is too long for a prompt fragment"


def test_notes_do_not_diagnose_or_prescribe_treatment(base):
    banned = ("diagnoz", "ibuprofen", "paracetamol", "leczeni")
    for chunk in base.chunks:
        text = (chunk.title + " " + chunk.text).lower()
        # "nie diagnozuj" style disclaimers would be fine, but the notes should not need them
        assert not any(word in text for word in banned), chunk.id


# (question, a word that must be in the title of one of the top hits)
RELEVANT = [
    ("Ile serii tygodniowo na masę mięśniową?", "serii"),
    ("Mam zakwasy po nogach, co robić?", "zakwasy"),
    ("Jak długo trwają zakwasy?", "zakwasy"),
    ("Jak robić pompki poprawnie?", "pompka"),
    ("Czy kolana mogą wychodzić za palce w przysiadzie?", "przysiad"),
    ("Jak się rozgrzać przed treningiem?", "rozgrzewka"),
    ("Ile powtórzeń na siłę?", "siła"),
    ("Czy trzeba trenować do upadku?", "upadku"),
    ("Jak długo trzymać plank?", "plank"),
    ("Jak poprawić podciąganie?", "podciąganie"),
    ("Ile minut ruchu tygodniowo zalecają?", "ruch"),
    ("Jak ciężko mam trenować, skala wysiłku?", "wysiłku"),
    ("Czy martwy ciąg rumuński z zaokrąglonymi plecami to błąd?", "martwy"),
    ("Jakie są oznaki przetrenowania?", "przetrenowania"),
    ("Jak robić wykroki?", "wykrok"),
    ("Czy mogę ćwiczyć w ciąży?", "ciąża"),
    ("Jak wyciskać hantle nad głowę?", "wyciskanie"),
    ("Jak wiosłować z hantlą?", "wiosłowanie"),
]


@pytest.mark.parametrize(("question", "word"), RELEVANT)
def test_questions_find_the_right_note(base, question, word):
    titles = [hit.chunk.title.lower() for hit in base.search(question)]
    assert any(word in title for title in titles), f"{question!r} -> {titles}"


@pytest.mark.parametrize(
    "question",
    [
        "Co zjeść na obiad?",
        "Jaka jest stolica Francji?",
        "Hej",
        "Dzięki!",
        "",
        "   ",
        "a co dalej?",
        "Czy dziś ćwiczyć nogi?",
    ],
)
def test_unrelated_or_empty_questions_find_nothing(base, question):
    assert base.search(question) == []


def test_search_ignores_case_and_polish_diacritics_and_endings(base):
    expected = [hit.chunk.id for hit in base.search("zakwasy po treningu")]
    assert expected
    assert [hit.chunk.id for hit in base.search("ZAKWASY PO TRENINGU")] == expected
    assert tokens("serii") == tokens("serie") == tokens("serię")
    assert tokens("pompki") == tokens("pompek") == tokens("pompka")


def test_results_are_ranked_and_limited(base):
    hits = base.search("serii powtórzeń tygodniowo masa siła", k=2)
    assert len(hits) <= 2
    assert [hit.score for hit in hits] == sorted((hit.score for hit in hits), reverse=True)


# --- loading never breaks the chat


def write_note(directory: Path, name: str, body: str) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    (directory / name).write_text(body, encoding="utf-8")


GOOD = (
    "---\nsource: Test\nurl: https://example.org\nlicense: test\n---\n"
    "## Przysiad testowy\n- Plecy proste.\n- Kolana na zewnątrz.\n"
)


def test_missing_folder_means_no_knowledge(tmp_path):
    assert len(KnowledgeBase.load(tmp_path / "nope")) == 0


def test_a_broken_note_is_skipped_and_the_rest_still_load(tmp_path):
    write_note(tmp_path, "a-good.md", GOOD)
    write_note(tmp_path, "b-no-source.md", "---\nurl: x\n---\n## Coś\n- tekst\n")
    write_note(tmp_path, "c-binary.md", "\x00\x01")
    write_note(tmp_path, "README.md", "# nie notatka\n## sekcja\ntekst\n")
    loaded = KnowledgeBase.load(tmp_path)
    assert [chunk.title for chunk in loaded.chunks] == ["Przysiad testowy"]


def test_empty_sections_are_dropped(tmp_path):
    write_note(tmp_path, "a.md", GOOD + "\n## Pusta sekcja\n\n")
    assert len(KnowledgeBase.load(tmp_path)) == 1


# --- the prompt block


def test_block_has_title_text_and_source(base):
    block = knowledge_block(["Ile serii tygodniowo na masę mięśniową?"], base)
    assert "## Wiedza referencyjna" in block
    assert "12–20" in block and "źródło:" in block
    assert "nie porada medyczna" in block


def test_block_is_empty_when_nothing_fits(base):
    assert knowledge_block(["Hej"], base) == ""
    assert knowledge_block([], base) == ""


def test_block_stays_within_the_prompt_budget(base):
    block = knowledge_block(["serii powtórzeń obciążenie masa siła zakwasy plank pompki przysiad wykroki"], base)
    assert len(block) < knowledge.MAX_CHARS_IN_PROMPT + 800


def test_a_short_follow_up_uses_the_previous_question(base):
    assert knowledge_block(["a co dalej?"], base) == ""
    block = knowledge_block(["Jak robić pompki?", "a jakie są łatwiejsze?"], base)
    assert "Pompk" in block


# --- through the chat


def chat(h: Harness, text: str):
    h.models.script = [[text_response("Odpowiedź.")]]
    result = h.http.post("/v1/coach/chat", json={"stream": False, "messages": [{"role": "user", "content": text}]})
    assert result.status_code == 200
    return h.models.calls[-1].config.system_instruction


def test_the_prompt_carries_the_fitting_notes(harness):
    system = chat(harness, "Ile serii tygodniowo robić na masę mięśniową?")
    assert "Wiedza referencyjna" in system
    assert "12–20" in system


def test_the_prompt_has_no_knowledge_section_for_small_talk(harness):
    assert "Wiedza referencyjna (notatki" not in chat(harness, "Hej, jak leci?")


def test_the_chat_works_when_the_knowledge_fails(harness, monkeypatch):
    def broken(_):
        raise RuntimeError("disk gone")

    monkeypatch.setattr("app.services.coach_service.load_knowledge", broken)
    system = chat(harness, "Ile serii tygodniowo robić na masę mięśniową?")
    assert "Wiedza referencyjna (notatki" not in system
