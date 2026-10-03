# content/: wspólna treść aplikacji i backendu

Jedyne źródło prawdy dla katalogu ćwiczeń, reguł układania planów i zdalnej konfiguracji. Backend (`backend/`) czyta te pliki i serwuje je aplikacji. Aplikacja trzyma wbudowaną kopię jako zapas (offline, pierwsze uruchomienie), tworzoną przez `scripts/sync_content.py`.

| Plik | Co zawiera | Właściciel |
|---|---|---|
| `catalog.json` | katalog ćwiczeń (`exercises`): `id`, nazwa, sprzęt, poziom, wzorzec ruchu (`pattern`), `movementTags`, zamienniki, domyślne tempo | Maciek |
| `plan_templates.json` | reguły szablonowego planu: dni tygodnia, plany sesji, schematy serii i powtórzeń wg celu | Maciek |
| `config/scoring.json` | progi i wagi oceny nagrania i techniki | Bartek |
| `config/insights.json` | progi silnika reguł (rekomendacja dnia, opieka) | Wiktor |
| `config/tempo.json` | progi serii na żywo (fazy ruchu, tolerancje, korekty) | Michał |

## Zasady

- Plik musi być poprawnym JSON-em i przechodzić walidację backendu (`cd backend && make test`). Backend nie startuje na błędnej treści.
- `catalog.json`: każdy `id` jest unikalny, każdy zamiennik istnieje, `pattern` jest jednym z: `squat`, `hinge`, `lunge`, `push`, `pull`, `core`, `cardio`. `movementTags` opisuje wzorce ruchu, które ćwiczenie zawiera (np. `deepLunges`). Użytkownik, który zgłosił problem z danym wzorcem, nie dostaje takich ćwiczeń.
- Zmiana wartości w `config/*.json` zmienia zachowanie aplikacji bez nowej wersji (po pobraniu konfiguracji). Zmiany progów opisuj w PR, bo wpływają na wynik i rekomendacje.
- Po zmianie uruchom `python scripts/sync_content.py` z katalogu głównego repo, żeby zaktualizować kopie w aplikacji (`Packages/Core/Sources/Content/Resources/`; `--check` tylko sprawdza, a `make check` w `backend/` to robi). Aplikacja czyta kopię przez `ContentRepository`, a przy starcie pobiera nowszą wersję z serwera.
- Teksty zdrowotne: „sygnał”, nigdy diagnoza (PROJECT.md 3.6).
