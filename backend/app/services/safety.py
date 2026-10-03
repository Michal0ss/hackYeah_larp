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

_FORBIDDEN = [
    r"diagnoz",  # "diagnoza", "diagnozuję"; also in "nie diagnozuję", the template covers that case
    r"\bmasz\s+(zapalenie|przepuklin|dyskopati|rwe|tendinopati|zerwani|naderwani|skrecen|zwichni)",
    r"\bto\s+(jest\s+)?(zapalenie|przepuklina|dyskopatia|tendinopatia|zerwanie|naderwanie)",
    r"\b(ibuprofen|paracetamol|ketonal|diclofenac|naproksen|aspiryn|sterydy|antybiotyk)",
    r"\bprzyjmij\s+\w*\s*lek",
    r"\bleczeni\w+",
    r"\b(gwarantuj|na pewno schudniesz|na pewno wyleczy|100\s*%)",
    r"https?://|www\.",
    r"[#*`_]{2,}|^#|\*\*",
]
_FORBIDDEN_RE = re.compile("|".join(_FORBIDDEN), re.MULTILINE)


def check_generated_text(*texts: str, max_total: int = 600) -> list[str]:
    """Problems found in model-written copy (short codes). Empty list = fine to show."""
    problems: list[str] = []
    joined = " ".join(texts)
    if not texts or any(not text.strip() for text in texts):
        problems.append("empty")
    if len(joined) > max_total:
        problems.append("too_long")
    if _FORBIDDEN_RE.search(fold(joined)):
        problems.append("unsafe_phrase")
    return problems
