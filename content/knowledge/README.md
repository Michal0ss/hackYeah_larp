# content/knowledge: baza wiedzy trenera (RAG)

Krótkie notatki po polsku (własne streszczenia, nie kopie), z których backend dokłada do promptu trenera 1–3 pasujące fragmenty. Każdy plik ma nagłówek `source`, `url`, `license`; fragmentem jest sekcja `##`.

**Status:** wystarczające na hackathon. Przed wydaniem poza hackathon trzeba sprawdzić licencje (WHO, artykuły z PMC: część ma NC lub ND), a Wikipedię cytować zgodnie z CC BY-SA 4.0.

| Plik | Źródło | Licencja |
|---|---|---|
| `zalecenia-aktywnosci.md` | WHO 2020 guidelines on physical activity (PMC) | do sprawdzenia |
| `obciazenie-i-powtorzenia.md` | Plotkin i in. (PMC) + przegląd przeglądów o zmiennych treningu oporowego (PMC) | CC BY / CC BY-NC-ND |
| `objetosc-tygodniowa.md` | Systematic review of resistance training volumes (PMC) | do sprawdzenia |
| `regeneracja-i-zakwasy.md`, `rozgrzewka.md`, `intensywnosc-rpe.md`, `technika-*.md` | Wikipedia (hasła wskazane w nagłówkach) | CC BY-SA 4.0 |

## Zasady
- Piszemy własnymi słowami, krótko, bez diagnoz i zaleceń leczenia (PROJECT.md 3.6).
- Dodajemy tylko to, co wynika ze źródła; liczby przepisujemy dokładnie i zaznaczamy populację (np. „młodzi wytrenowani mężczyźni”).
- Nowy plik: nagłówek jak wyżej, sekcje `##` po 3–8 punktów (fragment ma się mieścić w kilkuset znakach), potem `make test` w `backend/`.
- Wyszukiwanie: `backend/app/ai/knowledge.py` (BM25 bez zewnętrznych usług, działa offline).
