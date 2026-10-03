# Raport: moduł AI backendu (Gemini)

Stan na 2026-10-03, gałąź `feat/maciek-backend-ai`, PR #11. Autor: Maciek (plan i trener AI).

## W skrócie

Cały moduł AI backendu działa na **Google Gemini**. Anthropic/Claude jest usunięty z kodu, zależności, konfiguracji i dokumentacji. Moduł obsługuje trzy rzeczy: **plan treningowy**, **czat trenera** (ze strumieniem i narzędziami wykonywanymi na telefonie) i **tekst rekomendacji dnia**. Gdy model zawodzi, backend nie zwraca błędu tam, gdzie da się odpowiedzieć szablonem.

Aplikacja w Swifcie nie wymaga zmian: kontrakt API, zdarzenia SSE (`delta`, `tool_use`, `done`, `error`) i format rozmowy są takie same. Jedyna zmiana w kontrakcie: `aiMode` w `/health` to `mock` albo `gemini`.

## Co działa (sprawdzone)

### Na prawdziwym Gemini (`make evals`, klucz z darmowego poziomu)

| Obszar | Wynik |
|---|---|
| Plan: 6 profili (siła/siłownia 5 dni, początkujący bez sprzętu, powrót do ruchu z ograniczeniami, wolny tekst „boli bark”, kettlebell 4 dni, Anna) | **6/6 planów przechodzi walidator**, średnio **3,4 s**, ok. 0,002 USD za plan |
| Plan: ograniczenia | tagi ruchów do pominięcia i sprzęt są respektowane; wolny tekst „boli mnie bark przy unoszeniu ręki nad głowę” → plan bez wyciskania nad głowę |
| Czat: 9 scenariuszy | **9/9**: dobór narzędzi, odpowiedzi z kontekstu, brak narzędzi zdrowotnych bez zgody, zamienniki z katalogu, analiza ostatniego przysiadu z wyników, ból kolana → konsultacja bez diagnozy, ból w klatce i duszność → przerwać trening i 112, próba wyciągnięcia promptu → odmowa, dwa narzędzia w jednej rozmowie, 4 pytania pod rząd |
| Czat: koszt | ok. 0,004 USD za rozmowę z 4 pytaniami, pojedyncza odpowiedź 1–3 s |
| Kaskada modeli | model główny i dwa zapasowe odpowiedziały 429, odpowiedź przyszła z czwartego, użytkownik nie zobaczył błędu |
| Test końcowy przez uruchomiony backend | `POST /v1/plans/generate` → plan z AI w 5,2 s (przez model zapasowy), `POST /v1/coach/chat` → strumień z poprawnym `tool_use` |

Koszty liczone przy założonych cenach 0,30/2,50 USD za 1M tokenów (wejście/wyjście): do sprawdzenia w cenniku Google.

### Testy jednostkowe (`make test`, bez sieci i bez klucza)

58 testów na fałszywym kliencie Gemini. Pokrywają: kaskadę modeli i cooldown (429: 5 min, 404: 1 h), mapowanie błędów (429, 404, 5xx, 400, timeout, połączenie), blokadę filtrów, ucięcie na limicie tokenów, pustą i niepoprawną odpowiedź, tłumaczenie `tool_use`/`tool_result` i podpisy myślenia (podpis tylko dla modelu, który go wydał), strumień (bez zmiany modelu po wysłaniu tekstu, ucięte wywołanie narzędzia nie jest przekazywane), endpointy czatu/planu/tekstu od HTTP do modelu, bramkę zgody na dane zdrowotne, czyszczenie wejścia narzędzi, plan z szablonu przy awarii, konfigurację. Sprawdziłem celowym zepsuciem, że testy wykrywają błąd cooldownu i fallbacku.

`make check` (lint, testy, walidacja treści, `openapi.json` aktualny) przechodzi.

### W symulatorze iPhone

Onboarding → „Układam plan” woła backend, plan z AI wraca i pojawia się na ekranie „Dziś” (zrobione przed ostatnimi zmianami promptów i kaskady; po nich sprawdzone curlem, patrz wyżej).

## Jak to jest zabezpieczone przed awariami

- **Kaskada modeli** (`FORMA_FALLBACK_MODELS`): przy 404, 429, 5xx, timeoucie i błędzie połączenia wchodzi następny model. Strumień czatu przełącza model tylko dopóki do aplikacji nic nie poszło.
- **Cooldown**: model po 429 lub 404 jest pomijany, żeby kolejne zapytania nie czekały na tę samą awarię.
- **Gdy nic nie działa**: plan i tekst rekomendacji → szablon z ostrzeżeniem `ai_unavailable`; czat → `503 ai_unavailable` albo zdarzenie `error` w strumieniu (aplikacja pokazuje „spróbuj ponownie”).
- **Walidacja po stronie serwera**: plan od modelu musi przejść walidator (istniejące ćwiczenia, sprzęt, poziom, tagi, limity serii i powtórzeń), inaczej dostaje szablon (`ai_invalid_plan`). Tekst rekomendacji przechodzi kontrolę zakazanych fraz.
- **Czas i limity**: 20 s na zapytanie do modelu, plan do 50 s (pod limitem 60 s funkcji na Vercelu), niski poziom myślenia i hojne limity tokenów (czat 2048, plan 8192, tekst 1500), żeby JSON nie był ucinany.
- **Bez klucza**: backend startuje w trybie atrapy, więc nikt nie czeka na klucz.
- **Logi bez treści**: tylko modele, tokeny, czas i kody błędów.

## Czego NIE sprawdzono / ograniczenia

1. **Klucz jest z darmowego poziomu Google**: 20 zapytań na dobę na model (kaskada to rozciąga do ok. 80, ale na demo nie wystarczy) oraz Google może wykorzystywać treść zapytań, a czat przesyła podsumowania zdrowotne. **Do prawdziwego użycia potrzebny klucz z projektu z włączonym rozliczeniem i limitem budżetu.** W trakcie testów limity głównych modeli się wyczerpały.
2. **Strumień SSE przez Vercel** i limit 60 s: niesprawdzone (deploy nie był robiony).
3. **Telefon fizyczny**: nie sprawdzano, tylko symulator i curl.
4. **Podpis zastępczy po zmianie modelu w trakcie rozmowy** (gdy model zmieni się między turami narzędzi): przetestowany tylko na atrapie, nie na prawdziwym API.
5. **Cache podpisów myślenia jest w pamięci procesu**: przy kilku instancjach (Vercel) część tur dostanie podpis zastępczy.
6. **Jakość odpowiedzi trenera** oceniana automatycznie i ręcznie na 9 scenariuszach; zdarzają się drobne błędy językowe modelu (np. literówka). Przed demo warto przejrzeć kilka rozmów (`make evals` z `--show`).
7. **Modele zapasowe `*-preview`** mogą zniknąć. Lista dostępnych modeli dla klucza: `evals/run_ai_evals.py --list-models`.
8. **Ceny** w raporcie są założeniem.

## Uwagi do innych modułów

- **Wiktor** (`services/safety.py`): `detect_red_flags` nie łapie „boli mnie w klatce”, „brakuje mi tchu”, „kłuje mnie w klatce” (łapie „ból w klatce”, „duszności”); wzorzec `diagnoz` odrzuca też „nie diagnozuję”.
- **Michał**: na Vercelu ustaw sekret `GEMINI_API_KEY`; w PROJECT.md zostały opisowe wzmianki o modelach Claude; `requirements.txt` dla Vercela przeliczyłem (bez `anthropic`, z `google-genai`). Na kroku 5 onboardingu tekst „Standardowe pytania przesiewowe…” nachodzi na przycisk „Dalej”.

## Jak uruchomić

```bash
cd backend && make install
make test                          # bez sieci i klucza
make dev                           # bez klucza: atrapa; z GEMINI_API_KEY (np. w backend/.env): Gemini
.venv/bin/python evals/run_ai_evals.py --list-models
.venv/bin/python evals/run_ai_evals.py --show      # prawdziwy model, wymaga klucza i limitu
```

Konfiguracja: `GEMINI_API_KEY`, `FORMA_COACH_MODEL`, `FORMA_PLAN_MODEL`, `FORMA_TEXT_MODEL` (domyślnie `gemini-3.5-flash`), `FORMA_FALLBACK_MODELS`, `FORMA_AI_MODE=mock` (wymusza atrapę). Szczegóły: [README.md](README.md).
