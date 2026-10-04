"""Safety rules around text that comes from or goes to the model.

Forma gives training advice, not medical advice (PROJECT.md 3.6): it points out signals and suggests a
consultation, it never diagnoses. These checks are the deterministic part of that promise; the system prompts
are the other part. Extend the pattern lists when you find a miss, and add a test next to it.
"""

import re
import unicodedata

_CONTROL = re.compile(r"[\x00-\x1f\x7f]")
_SPACES = re.compile(r"\s+")


def sanitize_free_text(text: str, max_length: int = 300) -> str:
    """Free text typed by the user, made safe to quote inside a prompt: one line, no markup characters."""
    cleaned = _CONTROL.sub(" ", text)
    cleaned = cleaned.replace("<", " ").replace(">", " ").replace("`", " ").replace("{", " ").replace("}", " ")
    return _SPACES.sub(" ", cleaned).strip()[:max_length]


def fold(text: str) -> str:
    """Lowercase and strip Polish diacritics, so "ból" and "bol" match the same pattern."""
    decomposed = unicodedata.normalize("NFKD", text.lower().replace("ł", "l"))
    return "".join(ch for ch in decomposed if not unicodedata.combining(ch))


# --- the user describes alarming symptoms

_RED_FLAGS = [
    r"\bbol\w*\s+(w\s+)?klatc",
    r"\b(ucisk|sciskanie|dlawienie)\w*\s+(w\s+)?klatc",
    r"\bdusznos",
    r"\bnie\s+moge\s+(zlapac\s+)?(oddychac|tchu|powietrza)",
    r"\b(zemdlal|omdlal|omdlen|stracil\w*\s+przytomnosc|utrat\w+\s+przytomnosci)",
    r"\bdretw\w*\s+(\w+\s+)?(reka|reki|reke|ramie|ramienia|twarz|polowa|polowy)",
    r"\bnagl\w+\s+(silny\s+)?bol\s+glowy",
    r"\bkolatani\w+\s+serca",
]
_RED_FLAG_RE = re.compile("|".join(_RED_FLAGS))

RED_FLAG_NOTICE = (
    "Opisujesz objaw, który warto sprawdzić z lekarzem. Przerwij trening i nie ćwicz na siłę. "
    "Jeśli objawy są nagłe, silne lub się nasilają (ból w klatce piersiowej, duszność, utrata przytomności), "
    "zadzwoń pod numer alarmowy 112.\n\n"
)


def detect_red_flags(text: str) -> bool:
    return bool(_RED_FLAG_RE.search(fold(text)))


# --- generated text must not read like a diagnosis, a prescription or a promise
#
# Patterns are written against `fold()`ed text (lowercase, no Polish diacritics). They are grouped by what they
# protect, so a rejection says why in the logs. When a bad text slips through, add its phrase to the matching group
# and an example to backend/scripts/check_texts.py.

_FORBIDDEN: dict[str, list[str]] = {
    # naming conditions or injuries, or saying what is wrong with the user
    "diagnosis": [
        r"(?<!nie )(?<!nie jest )diagnoz",  # "to nie jest diagnoza" and "sygnal, nie diagnoza" are fine
        r"\bmasz\s+(zapalenie|przepuklin|dyskopati|rwe|tendinopati|zerwani|naderwani|skrecen|zwichni|kontuzj|uraz)",
        r"\bto\s+(jest\s+)?(zapalenie|przepuklina|dyskopatia|tendinopatia|zerwanie|naderwanie|kontuzja|uraz)",
        r"\b(przetrenowani|wypalenie|depresj|zaburzeni|stan\s+zapaln|cukrzyc|nadcisnieni|arytmi|niedoczynnos|nadczynnos)",
        r"\banemi",
        r"\b(uraz|kontuzj)",  # generated copy does not name injuries at all, even as a cause or a risk
        r"\bchorob",
        r"\bproblem\w*\s+z\s+sercem",
        r"\btwoj\w*\s+\w+\s+(jest|sa)\s+(uszkodzon|kontuzjowan|zniszczon)",
        r"uszkodz",
    ],
    # medicines, supplements, doses, treatment
    "medication": [
        r"\b(ibuprofen|paracetamol|ketonal|diclofenac|naproksen|aspiryn|sterydy|antybiotyk|opioid)",
        r"\bprzyjmij",
        r"\b(lek|leki|leku|lekiem|lekow|lekach|lekami)\b",
        r"\bleczeni",
        r"\brecept",
        r"\bsuplement",
        r"\bwitamin",
        r"\bdawk",
        r"\b\d+\s*(mg|ml|tabletk|kapsulk)",
    ],
    # promises about results
    "promise": [
        r"\b(za)?gwarantuj",
        r"\bna\s+pewno\b",
        r"\bz\s+pewnoscia\b",
        r"\b100\s*%",
        r"\bbez\s+ryzyka",
        r"\bzapobiegni",
        r"\bunikniesz\b",
        r"\bwyleczy",
        r"\bpozbedziesz\s+sie",
        r"\b(schudniesz|zbudujesz|poprawisz\s+wynik)",
    ],
    # scaring language
    "scare": [
        r"\bniebezpieczn",
        r"\bgrozi",
        r"\bzagrozen",
        r"\bpilnie\b",
        r"\bnatychmiast",
        r"\balarm",
    ],
    # bossy or forbidding, against the supportive tone
    "prohibition": [
        r"\bnie\s+wolno",
        r"\bzabron",
        r"\bzakaz",
        r"\bmusisz\b",
        r"\bkoniecznie\b",
    ],
    "link": [
        r"https?://",
        r"www\.",
        r"\b[a-z0-9-]+\.(com|pl|org|net|io|eu)\b",
        r"\S+@\S+",
    ],
    "markup": [
        r"[#*`_]{2,}",
        r"^#",
        r"\*\*",
        r"^\s*[-*\u2022]\s",
        r"\[[^\]]*\]\([^)]*\)",
    ],
    # the model talking about itself or its instructions
    "meta": [
        r"\bjako\s+(model|ai|asystent|sztuczna)",
        r"\b(system\w*\s+prompt|instrukcj\w+\s+systemow)",
    ],
}
_FORBIDDEN_RE = {category: re.compile("|".join(patterns), re.MULTILINE) for category, patterns in _FORBIDDEN.items()}

# Emoji and pictographs (the prompt asks for none).
_EMOJI_RE = re.compile("[\U0001f000-\U0001faff\u2600-\u27bf\u2b00-\u2bff\ufe0f]")

# The decision comes from the rules on the phone. Text that says the opposite is rejected.
_CONTRADICTIONS: dict[str, list[str]] = {
    "train": [r"\bodpusc", r"\brezygn", r"\bnie\s+cwicz", r"\blzejsz", r"\bskroc"],
    "adapt": [r"\btrenuj\s+wedlug\s+planu", r"\bpelny\s+trening", r"\bcwicz\s+jak\s+zwykle"],
    "rest": [r"\btrenuj\s+wedlug\s+planu", r"\bpelny\s+trening", r"\bcwicz\s+jak\s+zwykle"],
}
_CONTRADICTION_RE = {d: re.compile("|".join(p)) for d, p in _CONTRADICTIONS.items()}

_NUMBER_RE = re.compile(r"\d+(?:[.,]\d+)?")


def numbers_in(text: str) -> set[str]:
    """Numbers written in the text, `5,5` and `5.5` counted as the same."""
    return {match.replace(",", ".") for match in _NUMBER_RE.findall(text)}


_POLISH_LETTERS_RE = re.compile("[ąćęłńóśźżĄĆĘŁŃÓŚŹŻ]")


def check_generated_text(
    *texts: str,
    max_total: int = 600,
    source: str | None = None,
    decision: str | None = None,
) -> list[str]:
    """Problems found in model-written copy (short codes). Empty list = fine to show.

    `source` is everything the model was given (headline, factors, action, care reason): the text may not contain
    numbers that are not in it. `decision` ("train", "adapt", "rest") is checked for contradictions.
    """
    problems: list[str] = []
    joined = " ".join(texts)
    if not texts or any(not text.strip() for text in texts):
        problems.append("empty")
    if len(joined) > max_total:
        problems.append("too_long")
    folded = fold(joined)
    for category, pattern in _FORBIDDEN_RE.items():
        if pattern.search(folded):
            problems.append(f"unsafe_phrase:{category}")
    if _EMOJI_RE.search(joined):
        problems.append("unsafe_phrase:emoji")
    if len(joined) >= 80 and not _POLISH_LETTERS_RE.search(joined):
        problems.append("missing_diacritics")
    if source is not None and numbers_in(joined) - numbers_in(source):
        problems.append("invented_number")
    if decision in _CONTRADICTION_RE and _CONTRADICTION_RE[decision].search(folded):
        problems.append("contradicts_decision")
    return problems
