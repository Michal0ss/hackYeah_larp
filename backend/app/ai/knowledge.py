"""Knowledge base for the coach (RAG): short Polish notes in `content/knowledge/*.md`.

For every question the coach gets the few notes that fit it, so answers about technique, volume, recovery or
warm-up rest on cited sources instead of on the model's memory.

Retrieval is plain BM25 over the notes, in memory: no embeddings, no extra API call and no quota, so it works
offline and cannot fail the chat. With Polish endings a crude prefix "stem" is enough for a corpus this small.
Anything wrong with the files (missing folder, broken note) is logged and skipped: no knowledge never breaks the chat.

A note file starts with a header, then one section per fragment:

    ---
    source: where it comes from
    url: https://...
    license: licence of the source
    ---
    ## Fragment title
    - fact
"""

import math
import re
from collections import Counter
from dataclasses import dataclass
from functools import cache
from pathlib import Path

from app.logging_setup import get_logger
from app.services.safety import fold

log = get_logger("knowledge")

STOPWORDS = frozenset(
    """
    i w na z ze do od po za o u a e y oraz lub albo czy jak co to sie ze ale tez juz jest sa byc mam mamy masz ma
    moge mozna ile jaki jaka jakie ktory ktora ktore dla przy nad pod bez przez ten ta te tego tej tym nie tak
    mi mnie moj moja moje twoj twoja twoje czesto zwykle bardzo tylko jeszcze gdy kiedy wiec bo
    robic zrobic poprawnie powinienem trzeba nalezy dzis dzisiaj czym zastapic zastepowac chce mozesz pomoz
    """.split()
)

DEFAULT_TOP_K = 3
# Below this BM25 score a note is not about the question (tuned on tests/test_knowledge.py).
MIN_SCORE = 3.5
# Notes stay short; this only guards the prompt size.
MAX_CHARS_IN_PROMPT = 2400


def tokens(text: str) -> list[str]:
    """Lowercase, no diacritics, no stopwords, 4-letter prefix for longer words ("serii", "serie" -> "seri")."""
    result = []
    for word in re.findall(r"[a-z0-9]+", fold(text)):
        if len(word) < 2 or word in STOPWORDS:
            continue
        result.append(word[:4] if len(word) >= 5 else word)
    return result


@dataclass(frozen=True)
class Chunk:
    id: str
    title: str
    text: str
    source: str
    url: str
    license: str
    terms: tuple[str, ...]


@dataclass(frozen=True)
class Hit:
    chunk: Chunk
    score: float


class KnowledgeBase:
    def __init__(self, chunks: list[Chunk]):
        self.chunks = chunks
        self._tf = [Counter(chunk.terms) for chunk in chunks]
        self._lengths = [len(chunk.terms) for chunk in chunks]
        self._average = (sum(self._lengths) / len(chunks)) if chunks else 0.0
        document_frequency: Counter[str] = Counter()
        for counts in self._tf:
            document_frequency.update(counts.keys())
        total = len(chunks)
        self._idf = {
            term: math.log(1 + (total - count + 0.5) / (count + 0.5)) for term, count in document_frequency.items()
        }

    def __len__(self) -> int:
        return len(self.chunks)

    def search(self, query: str, k: int = DEFAULT_TOP_K, min_score: float = MIN_SCORE) -> list[Hit]:
        wanted = set(tokens(query))
        if not wanted or not self.chunks:
            return []
        k1, b = 1.5, 0.75
        hits = []
        for chunk, counts, length in zip(self.chunks, self._tf, self._lengths, strict=True):
            score = 0.0
            for term in wanted:
                frequency = counts.get(term, 0)
                if not frequency:
                    continue
                norm = frequency * (k1 + 1) / (frequency + k1 * (1 - b + b * length / self._average))
                score += self._idf[term] * norm
            if score >= min_score:
                hits.append(Hit(chunk, score))
        hits.sort(key=lambda hit: hit.score, reverse=True)
        return hits[:k]

    # --- loading

    @classmethod
    def load(cls, directory: Path) -> "KnowledgeBase":
        chunks: list[Chunk] = []
        if not directory.is_dir():
            log.warning("knowledge_missing")
            return cls([])
        for path in sorted(directory.glob("*.md")):
            if path.name.lower() == "readme.md":
                continue
            try:
                chunks.extend(_parse(path))
            except Exception as exc:  # one broken note must not take the others down
                log.warning("knowledge_note_skipped", extra={"file": path.name, "excType": type(exc).__name__})
        log.info("knowledge_loaded", extra={"chunks": len(chunks)})
        return cls(chunks)


def _parse(path: Path) -> list[Chunk]:
    raw = path.read_text(encoding="utf-8")
    header, _, body = raw.removeprefix("---\n").partition("\n---\n")
    meta = {}
    for line in header.splitlines():
        key, _, value = line.partition(":")
        meta[key.strip()] = value.strip()
    source, url, licence = meta.get("source", ""), meta.get("url", ""), meta.get("license", "")
    if not source:
        raise ValueError("missing source")
    chunks = []
    for section in re.split(r"^## ", body, flags=re.MULTILINE)[1:]:
        title, _, text = section.partition("\n")
        title, text = title.strip(), text.strip()
        if not title or not text:
            continue
        # The title counts twice: a note about "Przysiad" should win for a question about squats.
        terms = tuple(tokens(title) * 2 + tokens(text))
        chunks.append(Chunk(f"{path.stem}#{len(chunks) + 1}", title, text, source, url, licence, terms))
    return chunks


@cache
def load_knowledge(directory: Path) -> KnowledgeBase:
    return KnowledgeBase.load(directory)


def knowledge_block(questions: list[str], base: KnowledgeBase) -> str:
    """The prompt section for the coach: the notes that fit the last questions, with their sources. Empty if none do."""
    # The newest question counts most: the older ones only help a short follow-up like "a w jakim tempie?".
    query = " ".join(questions[-2:])
    hits = base.search(query)
    if not hits:
        return ""
    lines = [
        "",
        "## Wiedza referencyjna (notatki z otwartych źródeł, dla tego pytania)",
        "Użyj ich tylko wtedy, gdy pasują do pytania. Dane użytkownika, plan i wyniki narzędzi mają pierwszeństwo. "
        "Nie przepisuj notatek: odpowiedz własnymi słowami i wspomnij źródło krótko (np. „według zaleceń WHO”). "
        "To ogólna wiedza dla zdrowych dorosłych, nie porada medyczna.",
    ]
    used = 0
    for hit in hits:
        entry = f"### {hit.chunk.title} (źródło: {hit.chunk.source})\n{hit.chunk.text}"
        if used + len(entry) > MAX_CHARS_IN_PROMPT:
            break
        used += len(entry)
        lines.append(entry)
    return "\n".join(lines) if len(lines) > 3 else ""
