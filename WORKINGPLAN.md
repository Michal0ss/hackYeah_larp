# Plan pracy zespołu: HackYeah, kategoria „Sport & Healthcare”

> Wersja robocza, 2026-10-03. Ten plik mówi, **kto co robi, na jakiej gałęzi i w jakiej kolejności**. Opis produktu i zasady są w [PROJECT.md](PROJECT.md) (numery sekcji w nawiasach), reguły pracy w repo w [CLAUDE.md](CLAUDE.md). Prototyp wyglądu: [Forma — prototyp iOS](https://claude.ai/artifact/STg7G33PFgjptESaMzF8Jk).
>
> Termin oddania: **4 października, 23:00**. Zmiany po terminie są nielegalne.

## 1. Cel i zakres w trzech zdaniach

Budujemy aplikację na iPhone'a (SwiftUI): trener, plan treningowy i doradca w jednym. Ocenia technikę przysiadu (z filmu i na żywo z trenerem tempa w słuchawkach), łączy ją z regeneracją z Apple Health i samopoczuciem w rekomendację dnia, ma plan od AI i czat z trenerem AI. **Jeden wspólny backend** (FastAPI, folder `backend/`) trzyma klucz do modelu i robi całą pracę z modelem (plan, czat, teksty), a telefon robi resztę: analizę wideo, tempo na żywo, reguły, dane zdrowotne (PROJECT.md, 8.1 i 8.3). Szkielet backendu jest w `main` i działa od razu bez klucza (tryb offline z atrapą modelu).

## 2. Zespół

| | Rola | Imię | GitHub* | iPhone / iOS | Xcode |
|---|---|---|---|---|---|
| **1** | Lead, UI, integracja, seria na żywo | Michał | Michal0ss | iPhone, iOS 26.5.2 | 27 |
| **2** | Analiza ruchu | Bartek | gryniu | [uzupełnić] | [uzupełnić] |
| **3** | Dane i reguły | Wiktor | wiktor6741 | [uzupełnić] | [uzupełnić] |
| **4** | Plan i trener AI | Maciek | maciej-janusz | [uzupełnić] | [uzupełnić] |

\* Zakładam, że loginy współpracowników w repo odpowiadają osobom w tej kolejności. Do potwierdzenia.

Projekt Xcode jest generowany przez XcodeGen z `project.yml`, więc wersja Xcode (26 lub 27) nie ma znaczenia przy zakładaniu projektu.

## 3. Jak pracujemy: niezależnie i asynchronicznie

Każda osoba ma własną sesję Claude'a w tym repo (Claude czyta [CLAUDE.md](CLAUDE.md) automatycznie). Zasady:

1. **Każde zadanie to osobna gałąź** `feat/<imię>-<temat>` (listy poniżej) i osobny, mały PR do `main`. Nikt nie pushuje na `main`.
2. **Nikt na nikogo nie czeka.** Zależności są interfejsami w `Contracts/Services.swift` z danymi przykładowymi (`SampleServices`, profil „Anna”). Własną implementację podpinasz w jednej linii `App/Services/AppServices.swift`, kiedy jest gotowa.
3. **Każdy ma własne foldery** (mapa w CLAUDE.md). Wspólne pliki (`Contracts`, `AppServices.swift`) zmieniamy tylko addytywnie i małymi PR-ami.
4. **PR zawiera:** działający kawałek, testy logiki (`swift test`), przechodzący build aplikacji, opis jak sprawdzić i co zostało do sprawdzenia na prawdziwym iPhonie, aktualizację wiersza w tabeli „Status” (sekcja 9).
5. **Scalanie:** squash do `main` po szybkim przeglądzie przez drugą osobę. Potem wszyscy robią `git pull --rebase origin main`.
6. **Kolejność w ramach osoby** poniżej jest sugestią. Zadania są tak pocięte, żeby dało się je robić równolegle i scalać w dowolnej kolejności.

### Interfejsy między osobami (kto dostarcza, kto używa)

| Interfejs (w `Contracts`) | Implementuje | Używają |
|---|---|---|
| `ExerciseCatalogProviding` | Maciek | wszyscy |
| `PlanProviding` | Maciek | Michał (Dziś), Wiktor (korekta sesji), Maciek (czat) |
| `RecoveryProviding`, `CheckInProviding` | Wiktor | Michał (Dziś, Postępy), Maciek (narzędzia czatu), Wiktor (silnik reguł) |
| `RecommendationProviding` | Wiktor | Michał (Dziś), Maciek (kontekst czatu) |
| `HealthAuthorizing` | Wiktor (w `HealthKitService`) | Michał (krok Apple Health w onboardingu) |
| `PlanGenerating` | Maciek (`PlanGenerator`) | Michał (krok „Układam plan” w onboardingu) |
| `TechniqueHistoryProviding` | Michał (zapis wyników), wyniki dostarcza Bartek i seria na żywo | Maciek (narzędzia czatu), Wiktor (reguły), Michał (Postępy) |
| `TechniqueAssessing` (w `LiveSet`) | `BasicSquatAssessor` (Michał), pełny scorer Bartka może go zastąpić | seria na żywo |

### Co gdzie żyje: telefon, backend, treść

| Warstwa | Co tu jest | Czego tu nie ma |
|---|---|---|
| **Telefon** (`App/`, `Packages/Core`) | interfejs, kamera i Vision, analiza techniki, tempo i głos serii na żywo, silnik reguł rekomendacji, HealthKit, check-in, plan i profil, **historia zdrowia**, historia rozmów, wykonywanie narzędzi czatu na lokalnych danych | klucza do modelu, wywołań modelu |
| **Backend** (`backend/`, FastAPI) | klucz do modelu, bramka do Claude, generowanie planu (model → walidacja → szablon zapasowy), czat trenera (strumień SSE, definicje narzędzi, bramka zgody), teksty rekomendacji z kontrolą bezpieczeństwa, serwowanie treści, token aplikacji, limity zapytań | wideo i obrazów, bazy danych, kont, surowych danych zdrowotnych (wyniki narzędzi to podsumowania, tylko po zgodzie), logów z treścią |
| **Treść** (`content/`) | katalog ćwiczeń, reguły szablonów planów, progi (`scoring`, `insights`, `tempo`): jedno źródło prawdy, backend je serwuje (`/v1/catalog`, `/v1/config`), aplikacja ma wbudowaną kopię (`scripts/sync_content.py`) | kodu |

**Co wychodzi z telefonu do sieci (tylko to):** profil bez historii zdrowia (`POST /v1/plans/generate`), rozmowa i wyniki narzędzi jako podsumowania po zgodzie (`POST /v1/coach/chat`), gotowa rekomendacja z silnika reguł (`POST /v1/texts/recommendation`). Wideo, obrazy, historia zdrowia i surowe próbki z Apple Health nie wychodzą nigdy.

**Backend ma właścicieli plików** (szczegóły i uruchomienie: [backend/README.md](backend/README.md)):

| Ścieżka | Właściciel | Zawartość |
|---|---|---|
| `backend/app/{main,config,security,middleware,errors,logging_setup}.py`, `routers/{system,config}.py`, `Dockerfile`, `Makefile`, `scripts/`, CI, wdrożenie, `content/config/tempo.json` | Michał | rdzeń: start, konfiguracja, token, limity, błędy, logi, wdrożenie |
| `backend/app/ai/` (poza `prompts/text_system.md`), `services/{plan_builder,plan_validator,plan_service,coach_service}.py`, `routers/{plans,coach,catalog}.py`, `content/catalog.json`, `content/plan_templates.json` | Maciek | bramka AI, prompty trenera i planu, narzędzia, plan, czat, katalog |
| `backend/app/services/{text_service,safety}.py`, `ai/prompts/text_system.md`, `routers/texts.py`, `content/config/insights.json` | Wiktor | teksty rekomendacji, kontrola bezpieczeństwa tekstów (wzorce), progi reguł |
| `content/config/scoring.json` | Bartek | progi i wagi oceny techniki |
| `backend/app/schemas/` | wspólne | typy żądań i odpowiedzi; zmiany tylko addytywne i zgodne z `Contracts` (nazwy pól camelCase jak w Swifcie) |

**Kontrakt API** to `backend/openapi.json` (generowany, w repo). Zmieniasz endpoint albo schemat: `make openapi` w `backend/` i commit obu zmian. Klient w Swifcie powstaje przeciw temu plikowi.

## 4. Zasady wspólne

1. Przeczytaj PROJECT.md w całości, zwłaszcza sekcje 3.6 (ton tekstów zdrowotnych) i 11.2.
2. Pracujesz w **swoim module**. Zmiana wspólnych typów (kontraktów) tylko addytywnie i za zgodą zespołu.
3. Nowe pliki trafiają do `Packages/Core/Sources/<Moduł>` albo `App/Screens/<Funkcja>`, a nie do pliku projektu.
4. **Klucz do modelu tylko w środowisku serwera (`ANTHROPIC_API_KEY`), nigdy w repozytorium ani w aplikacji.** Aplikacja ma tylko adres i token backendu (`FORMA_API_URL`, `FORMA_API_TOKEN` w `Config/Secrets.xcconfig` poza gitem).
5. Wideo i obrazy nigdy nie opuszczają telefonu. Dane zdrowotne trafiają do modelu tylko po zgodzie użytkownika i jako podsumowania.
6. Teksty zdrowotne: „sygnał”, „warto rozważyć konsultację”, nigdy diagnoza.
7. Dane przykładowe są zawsze oznaczone w interfejsie jako symulowane.
8. Zgodność: Xcode 26, cel wdrożenia iOS 17, szkło tylko przez komponenty `DesignSystem`.
9. Zakres tylko z PROJECT.md, sekcja 4. Pomysły spoza zakresu zapisujemy w sekcji 14, nie implementujemy.
10. **Backend:** nie logujemy treści (żądań, promptów, czatu, danych zdrowotnych), tylko metadane. Wszystko, co zwraca model, jest walidowane po stronie serwera, a plan i teksty mają zapas w szablonie. Wolny tekst użytkownika jest daną, nie poleceniem (`sanitize_free_text`). Przed PR dotykającym `backend/` lub `content/`: `make check` w `backend/`.
11. **Praca bez klucza:** `make dev` w `backend/` działa w trybie atrapy (plany z szablonu, czat z gotowymi odpowiedziami, nawet z wywołaniem narzędzi), więc nikt nie czeka na klucz. Prawdziwy model uruchamia się przez `ANTHROPIC_API_KEY` w swoim terminalu.

## 5. Zadania na osoby (gałęzie, własne foldery, kryteria ukończenia)

Przy każdym zadaniu: **gałąź**, co powstaje, **gotowe, gdy** (kryterium ukończenia). Wszystko można testować na `SampleServices` i danych przykładowych.

### Michał: Lead, UI, integracja, seria na żywo

**Własne ścieżki:** `DesignSystem`, `LiveSet`, `API`, `App/` (poza `Screens/Analysis|Plan|Coach|Progress|Care`), `Screens/Today|CheckIn|Onboarding|LiveSet`, `Config/`, `project.yml`, dokumenty, rdzeń backendu (tabela wyżej).

| Gałąź | Zadanie | Gotowe, gdy |
|---|---|---|
| `feat/michal-onboarding` | Onboarding w 6 krokach + układanie planu (cel, o tobie, sprzęt, historia medyczna, przeciwwskazania, Apple Health) zapisujący `UserProfile` i plan; dane zdrowotne zostają na telefonie | gotowe w PR (profil i plan w `AppStore` i na dysku, kroki zgodne z prototypem, testy logiki). Do zrobienia osobno: ekran profilu |
| `feat/michal-live-set-device` | Test i strojenie serii na żywo na prawdziwym iPhonie: kamera, progi `PhaseTrackerConfig`, głos w słuchawkach, kadr | pełna seria na telefonie z poprawnie liczonymi fazami, lista zmian progów w PR |
| `feat/michal-api-client` | Moduł Swift `API` (wspólny, mały): klient HTTP backendu (adres i token z `Info.plist`, `X-Device-Id`, nagłówek `Authorization`), dekodowanie błędów `{"error":{"code",...}}`, parser SSE (`delta`, `tool_use`, `done`, `error`), cache ETag dla `/v1/catalog` i `/v1/config`, wstrzykiwany transport. Daty `.iso8601`. Dopisanie modułu w `Package.swift` i `project.yml` | Maciek i Wiktor wołają backend jedną linią, testy na fałszywym transporcie, `GET /health` z telefonu działa |
| `feat/michal-backend-deploy` | **Później, nie teraz** (na razie backend lokalnie: `make dev` na laptopie, telefon w tej samej sieci). Wdrożenie backendu na **Vercelu** (punkt wejścia ASGI, `vercel.json`, dołączenie `content/`, zmienne środowiskowe: `ANTHROPIC_API_KEY`, `FORMA_APP_TOKENS`, limit wydatków na kluczu) i **Supabase** (projekt, tabela limitów zapytań i liczników zużycia bez treści, wymiana `RateLimiter` w `app/security.py` na wersję opartą o Supabase; klucz `service_role` tylko w Vercelu), CI (`make check`), adres w konfiguracji aplikacji, sprawdzenie strumieniowania SSE i limitu czasu funkcji na Vercelu | (po przejściu na hosting) adres z Vercela działa z telefonu, limity zapytań działają między instancjami, `/health` pokazuje `aiMode: anthropic`, klucz tylko w sekretach hostingu |
| `feat/michal-content-sync` | Wczytanie `content/` w aplikacji: wbudowana kopia (`scripts/sync_content.py`, zastępuje `Content/Resources/catalog.json`), zdalne odświeżanie przez `/v1/config` i `/v1/catalog` z ETag, `RemoteConfig` dla progów (scoring, insights, tempo) z zapasem w kopii | aplikacja startuje offline na kopii, po sieci bierze nowszą wersję; progi z `tempo.json` zasilają `PhaseTrackerConfig` |
| `feat/michal-integration` | Podłączanie usług (`AppServices`), zapis wyników serii i analiz (`TechniqueHistoryProviding`), spięcie ekranów i nawigacji, przejścia Dziś → Plan → seria | cały przepływ klikalny na jednym urządzeniu na danych przykładowych, a potem na prawdziwych usługach |
| `feat/michal-submission` | README dla jury, slajdy (12.1), nagranie demo, zrzuty ekranu, zgłoszenie na HackTribe | komplet materiałów i kompletne zgłoszenie z zapasem przed terminem |

**Prompt startowy dla jego sesji Claude'a:**
```text
Jesteś Michałem (Lead) w projekcie Forma. Przeczytaj CLAUDE.md, PROJECT.md i WORKINGPLAN.md (sekcja „Michał”). Pracujesz na gałęziach feat/michal-*, każde zadanie z tabeli jako osobny mały PR do main. Zacznij od feat/michal-onboarding, potem feat/michal-api-client i feat/michal-backend-deploy (backend: backend/README.md). Nie edytuj modułów Bartka, Wiktora i Maćka; potrzeby zgłaszaj w opisie PR. Przed PR: swift test w Packages/Core i build aplikacji.
```

### Bartek: Analiza ruchu

**Własne ścieżki:** `Packages/Core/Sources/Analysis`, `content/config/scoring.json`, `Tests/AnalysisTests`, `App/Screens/Analysis`. Może używać `LiveSet` (`PhaseTracker`, `SquatSignal`, `FramingAssessor`, `BasicSquatAssessor`) zamiast pisać od zera.

| Gałąź | Zadanie | Gotowe, gdy |
|---|---|---|
| `feat/bartek-pose-extractor` | `VisionPoseExtractor`: film z pliku (`AVAssetReader`) → `[PoseFrame]`. Nagraj 5–8 przysiadów z boku (w tym błędne) i zapisz wyniki jako **JSON-y do testów** | z filmu wychodzą `PoseFrame` z poprawnymi współrzędnymi (origin lewy górny róg), fixtures w `Tests/AnalysisTests/Fixtures` |
| `feat/bartek-quality-gate` | `QualityGate` dla nagranego filmu (PROJECT.md 6.2): widoczność, wielkość, liczba osób, powtórzenia, klatki na sekundę → `QualityReport` z konkretną wskazówką | testy na fixtures: dobry film przechodzi, złe dostają właściwą podpowiedź |
| `feat/bartek-rep-scoring` | `RepAnalyzer` (powtórzenia i kąty) + `TechniqueScorer` (6.4) → `TechniqueResult`. Progi i wagi w **`content/config/scoring.json`** (jedno źródło; aplikacja czyta wbudowaną kopię, a nowsze dostaje z `/v1/config`; zestaw startowy już jest w pliku) | wynik 0–100, uwagi i zamiennik z fixtures, testy jednostkowe |
| `feat/bartek-analysis-screens` | Ekrany Analiza: wybór ćwiczenia, ustawienie telefonu, nagrywanie lub galeria, jakość, przetwarzanie, wynik (6 plansz z prototypu) | przepływ działa na filmie z galerii na symulatorze i na nagraniu na telefonie |

**Prompt startowy:**
```text
Jesteś Bartkiem (Analiza ruchu) w projekcie Forma. Przeczytaj CLAUDE.md, PROJECT.md (sekcja 6) i WORKINGPLAN.md (sekcja „Bartek”). Pracujesz na gałęziach feat/bartek-*, każde zadanie jako osobny mały PR do main. Zacznij od feat/bartek-pose-extractor. Edytuj tylko Packages/Core/Sources/Analysis, Tests/AnalysisTests i App/Screens/Analysis. Możesz używać modułu LiveSet. Zwracaj wynik jako TechniqueResult z Contracts. Przed PR: swift test i build aplikacji.
```

### Wiktor: Dane i reguły

**Własne ścieżki:** `Packages/Core/Sources/Health`, `Insights`, `Tests/HealthTests`, `Tests/InsightsTests`, `App/Screens/Progress`, `App/Screens/Care`, część backendu: `services/text_service.py`, `services/safety.py`, `ai/prompts/text_system.md`, `routers/texts.py`, `content/config/insights.json`.

| Gałąź | Zadanie | Gotowe, gdy |
|---|---|---|
| `feat/wiktor-healthkit` | `HealthKitService` jako `RecoveryProviding` **i `HealthAuthorizing`** (prośba o uprawnienia wołana z onboardingu): sen, tętno spoczynkowe, HRV jako **podsumowania** i punkt odniesienia, fallback na `SampleData` z oznaczeniem symulacji | logika agregacji przetestowana na tablicach próbek, na iPhonie widać prawdziwe dane (jeśli są) |
| `feat/wiktor-checkin-store` | Zapis i odczyt `CheckIn` jako `CheckInProviding` (plik JSON lokalnie) | zapis z ekranu check-inu wraca z `checkIns(days:)`, testy |
| `feat/wiktor-insight-engine` | `InsightEngine` → `DailyRecommendation` (7.2–7.4). Progi z **`content/config/insights.json`** (wbudowana kopia i `/v1/config`). **Napraw próg „Odpuść”**: dziś 3 sygnały dają „Odpuść”, a przykład w prototypie to „Zmodyfikuj”. Zmień `restFromSignals` w pliku i opisz w PR | testy reguł dla scenariuszy (dobry dzień, 1–2 sygnały, wiele sygnałów, flaga opieki), implementacja `RecommendationProviding` |
| `feat/wiktor-recommendation-text` | Teksty rekomendacji: po stronie telefonu klient `POST /v1/texts/recommendation` (po `feat/michal-api-client`) z zapasem na własne teksty z silnika, po stronie serwera strojenie `text_system.md` i wzorców w `safety.py` (diagnozy, leki, obietnice, linki), test z prawdziwym kluczem na kilku scenariuszach | rekomendacja dnia zawsze się wyświetla (bez sieci: tekst z silnika), tekst z modelu nie zmienia decyzji ani nie diagnozuje, wzorce złapały przykłady złych tekstów |
| `feat/wiktor-plan-adjuster-care` | `PlanAdjuster` (zmiana dzisiejszej sesji według decyzji) i `CarePathway` (flaga „warto rozważyć konsultację”, 7.4) | testy: „Zmodyfikuj” skraca serie i podmienia ćwiczenie z katalogu, „Odpuść” zamienia sesję na odpoczynek |
| `feat/wiktor-progress-care-screens` | Ekrany Postępy (Swift Charts) i Opieka (MapKit, fizjoterapeuci w pobliżu) | ekrany na danych przykładowych, wyszukiwanie w Mapach działa |

**Prompt startowy:**
```text
Jesteś Wiktorem (Dane i reguły) w projekcie Forma. Przeczytaj CLAUDE.md, PROJECT.md (sekcje 7 i 3.6) i WORKINGPLAN.md (sekcja „Wiktor”). Pracujesz na gałęziach feat/wiktor-*, każde zadanie jako osobny mały PR do main. Zacznij od feat/wiktor-healthkit albo feat/wiktor-insight-engine (są niezależne). Edytuj tylko Packages/Core/Sources/Health i Insights, ich testy oraz App/Screens/Progress i Care. Implementuj protokoły RecoveryProviding, CheckInProviding, RecommendationProviding z Contracts/Services.swift i podepnij je w swojej linii App/Services/AppServices.swift dopiero, gdy działają. Teksty zdrowotne: sygnał, nie diagnoza. Przed PR: swift test i build aplikacji.
```

### Maciek: Plan i trener AI

**Własne ścieżki:** `Packages/Core/Sources/Plan`, `Coaching`, `Content`, ich testy, `App/Screens/Plan`, `App/Screens/Coach`, część backendu: `backend/app/ai/` (poza `text_system.md`), `services/{plan_builder,plan_validator,plan_service,coach_service}.py`, `routers/{plans,coach,catalog}.py`, `content/catalog.json`, `content/plan_templates.json`.

| Gałąź | Zadanie | Gotowe, gdy |
|---|---|---|
| `feat/maciek-catalog-templates` | **Treść w `content/`** (jedno źródło prawdy): `catalog.json` (jest 28 ćwiczeń na start: popraw opisy, dodaj filmy wzorcowe `videoURL`, **dodaj ćwiczenia ciągnięcia bez sprzętu**, np. wiosłowanie z ręcznikiem, bo dziś jest tylko `superman`, oraz znacznik ćwiczenia złożonego, żeby cel „siła” nie brał izolacji) i `plan_templates.json`. Swift: `ExerciseCatalogProviding` czyta wbudowaną kopię (`scripts/sync_content.py`, razem z `feat/michal-content-sync`) | `make check` w `backend/` przechodzi (spójność katalogu i szablonów), katalog w aplikacji ładuje się z kopii, każdy zamiennik istnieje |
| `feat/maciek-plan-store` | `PlanProviding`: aktualny plan i dzisiejsza sesja, zapis lokalny JSON, plan z szablonu dla profilu (offline, na `SamplePlanBuilder` albo na kopii `plan_templates.json`) | `currentPlan()` i `todaySession()` działają, testy |
| `feat/maciek-backend-ai` | **Backend z prawdziwym modelem**: uruchom `make dev` z kluczem, sprawdź `POST /v1/plans/generate` i `POST /v1/coach/chat` na kilku profilach i rozmowach, dostrój `ai/prompts/{plan,coach}_system.md`, opisy narzędzi w `ai/tools.py`, modele w `config.py`, jakość planu z szablonu (`plan_builder.py`). Nic z tego nie było jeszcze uruchomione na prawdziwym modelu | plany od modelu przechodzą walidator na kilku profilach (w logach brak `plan_rejected`), czat woła narzędzia i odmawia diagnoz, krótki opis w PR: modele, koszt jednej rozmowy |
| `feat/maciek-plan-generator` | Swift `PlanGenerator` jako `PlanGenerating`: wywołuje `POST /v1/plans/generate` przez moduł `API` (profil bez historii zdrowia), mapuje odpowiedź na `TrainingPlan`, przy braku sieci lub błędzie plan lokalny z szablonu; pokazuje ostrzeżenia (`ai_unavailable` itd.) | test na fałszywym transporcie: odpowiedź AI, odpowiedź z szablonu z ostrzeżeniem, błąd sieci → plan lokalny |
| `feat/maciek-coach-chat` | Swift `CoachChat`: `POST /v1/coach/chat` ze strumieniem SSE, **pętla narzędzi na telefonie** (`get_current_plan`, `get_technique_history`, `get_today_recommendation`, `get_recovery_summary`, `get_checkins`: wykonywane na protokołach usług, wynik jako podsumowanie JSON), `DataConsent` → pole `consent.health`, kontekst (`profile`, `todayRecommendation` tylko po zgodzie), historia lokalnie, obsługa błędów (`error`, 503, 429) | testy na fałszywym transporcie SSE: tekst, wywołanie narzędzia i druga tura, brak narzędzi zdrowotnych bez zgody, błąd w trakcie strumienia |
| `feat/maciek-plan-coach-screens` | Ekrany Plan (tydzień, szczegóły sesji, tempo) i Trener (czat, zgoda, pusta rozmowa, błąd, trener pisze). Plan może przejąć Michał | ekrany na danych przykładowych i na atrapie backendu, potem na prawdziwym modelu |

**Prompt startowy:**
```text
Jesteś Maćkiem (Plan i trener AI) w projekcie Forma. Przeczytaj CLAUDE.md, PROJECT.md (sekcje 7.5, 7.6, 8) i WORKINGPLAN.md (sekcja „Maciek”). Pracujesz na gałęziach feat/maciek-*, każde zadanie jako osobny mały PR do main. Zacznij od feat/maciek-catalog-templates albo feat/maciek-backend-ai (są niezależne; backend: backend/README.md, działa bez klucza w trybie atrapy). Edytuj tylko Packages/Core/Sources/Plan, Coaching, Content, ich testy, App/Screens/Plan i Coach oraz swoje pliki backendu i content/ (tabela „Co gdzie żyje” w WORKINGPLAN.md). Implementuj ExerciseCatalogProviding i PlanProviding z Contracts/Services.swift i podepnij je w swoich liniach App/Services/AppServices.swift dopiero, gdy działają. Narzędzia czatu pisz przeciw protokołom usług i testuj na SampleServices. Model wołasz wyłącznie przez backend (moduł API), klucza do modelu nie ma w aplikacji. Przed PR: swift test i build aplikacji, a przy zmianach backendu make check w backend/.
```

## 6. Zależności (kto na kogo czeka)

**Nikt nie czeka.** Każdy buduje swój kawałek na `SampleServices` i `SampleData`. Backend w trybie atrapy daje wszystkim te same odpowiedzi bez klucza (plany z szablonu, czat z gotowymi odpowiedziami i wywołaniem narzędzi). Integrację robi Michał w `feat/michal-integration`, podmieniając sample na prawdziwe implementacje w `AppServices.swift`, gdy poszczególne PR-y trafią do `main`.

## 7. Warunki ukończenia faz

| Faza | Gotowe, gdy |
|---|---|
| 0. Przed startem | każdy zbuduje aplikację na swój telefon i symulator |
| 1. Start | szkielet aplikacji, kontrakty, usługi i **szkielet backendu** są w `main`, zespół ma swoje gałęzie |
| 2. Moduły równolegle | każdy moduł działa na danych przykładowych i ma testy logiki |
| 3. Integracja | backend wdrożony i dostępny z telefonu, jeden pełny przepływ działa na telefonie: onboarding → plan → seria na żywo → analiza → rekomendacja → trener |
| 4. Dopracowanie i zgłoszenie | funkcje zamrożone, zgłoszenie kompletne i wysłane z zapasem przed terminem |

## 8. Priorytety, gdy zabraknie czasu

Wyższy zawsze przed niższym (PROJECT.md, 4.2):
1. **Rdzeń:** analiza przysiadu z oceną jakości nagrania, regeneracja i check-in, rekomendacja dnia, ekran „Dziś”.
2. **Seria na żywo:** liczenie tempa w słuchawkach, podsumowanie serii.
3. **Plan:** onboarding, plan na tydzień, dzisiejsza sesja (zapas: szablon).
4. **Trener AI:** czat z kontekstem.
5. **Dopełnienie:** Opieka (MapKit), wykres postępów, przycisk „Zastosuj w planie”.

## 9. Status

Aktualizuj swój wiersz w tym samym PR, w którym kończysz zadanie.

| Zadanie | Kto | Gałąź | Status | Uwagi |
|---|---|---|---|---|
| Szkielet, kontrakty, DesignSystem, Dziś, Check-in | Michał | `main` | gotowe (dane przykładowe) | |
| Szkielet backendu (FastAPI: config, token, limity, bramka AI z atrapą, `/v1/{catalog,config,plans/generate,coach/chat,texts/recommendation}`, `content/`) | Michał | `main` | gotowe | działa w trybie atrapy (bez klucza); **nie uruchomiony z prawdziwym modelem** (brak klucza), obraz Dockera i CI niesprawdzone; bez testów automatycznych (decyzja: szkielet bez testów) |
| Klient API w Swifcie (`API`) | Michał | `feat/michal-api-client` | w PR | moduł `API`, `AppServices.api`; sprawdzony jednorazowo na działającym backendzie (zdrowie, katalog z 304, konfiguracja, plan, tekst, czat ze strumieniem i narzędziem, błąd), bez testów automatycznych; nie sprawdzony z prawdziwym modelem i na telefonie |
| Wdrożenie i CI backendu | Michał | `feat/michal-backend-deploy` | szkielet gotowy (`api/index.py`, `vercel.json`, `requirements.txt`, kroki w backend/README.md), niewdrożony | brakuje: konto Vercel, zmienne środowiskowe, test SSE na Vercelu, limity w Supabase, CI | na razie lokalnie; Vercel + Supabase później, niesprawdzone |
| Treść w aplikacji (kopia i odświeżanie) | Michał | `feat/michal-content-sync` | w PR | `ContentRepository` (moduł Content): kopia w aplikacji, cache na dysku, odświeżanie z ETag przy starcie; katalog w `AppServices.catalog`; progi serii z `tempo.json` w `LiveSetEngine`. Sprawdzone na symulatorze (200, potem 304). **Po zmianie `content/` uruchom `python scripts/sync_content.py`** (`make check` pilnuje). Progi `insights` i `scoring` są dostępne przez `ContentRepository.shared.configData(...)`, ale Wiktor i Bartek jeszcze ich stamtąd nie czytają |
| Seria na żywo (tempo, głos, podsumowanie) | Michał | `main` | pierwsza wersja | silnik ma testy, kamera niesprawdzona na iPhonie |
| Onboarding | Michał | `feat/michal-onboarding` | w PR | zależy od PR kontraktowego `contracts/onboarding-profile`; ekran profilu (edycja i usuwanie historii zdrowia) jeszcze nie istnieje |
| Seria na żywo na telefonie | Michał | `feat/michal-live-set-device` | do zrobienia | |
| Integracja usług i przepływu | Michał | `feat/michal-integration` | w PR (część 1) | silnik reguł Wiktora zasila ekran Dziś (po starcie i po check-inie), katalog z `ContentRepository`, plan z onboardingu z backendu z lokalnym zapasem, wyniki serii zapisywane lokalnie (`LocalTechniqueHistory`) i liczone przez silnik. Check-in zapisuje się na telefonie przez `CheckInStore` (Wiktor) i wraca po restarcie. Zostaje: wyniki analiz Bartka, nawigacja Dziś → Plan → seria, ekran profilu |
| Materiały i zgłoszenie | Michał | `feat/michal-submission` | do zrobienia | |
| Wydobycie punktów z filmu | Bartek | `feat/bartek-pose-extractor` | do zrobienia | |
| Jakość nagrania | Bartek | `feat/bartek-quality-gate` | do zrobienia | |
| Powtórzenia i scoring | Bartek | `feat/bartek-rep-scoring` | do zrobienia | |
| Ekrany Analiza i Wynik | Bartek | `feat/bartek-analysis-screens` | do zrobienia | |
| HealthKit | Wiktor | `feat/wiktor-healthkit` | w przeglądzie (PR) | agregacja przetestowana na tablicach próbek; odczyt z prawdziwego Apple Health do sprawdzenia na iPhonie |
| Zapis check-inu | Wiktor | `feat/wiktor-checkin-store` | scalone (#6) | `CheckInStore` gotowy; podpięcie ekranu Check-in robi Michał (`AppStore.saveCheckIn` → `CheckInStore.standard`) |
| Silnik reguł | Wiktor | `feat/wiktor-insight-engine` | scalone (#4, poprawki w #10) | `restFromSignals` = 4, do „Odpuść” liczą się tylko sygnały regeneracji, technika najwyżej „Zmodyfikuj”; liczą się analizy z ostatnich 14 dni |
| Teksty rekomendacji (klient + backend) | Wiktor | `feat/wiktor-recommendation-text` | do zrobienia | |
| Korekta sesji i opieka | Wiktor | `feat/wiktor-plan-adjuster-care` | do zrobienia | |
| Ekrany Postępy i Opieka | Wiktor | `feat/wiktor-progress-care-screens` | do zrobienia | |
| Katalog i szablony | Maciek | `feat/maciek-catalog-templates` | do zrobienia | |
| Magazyn planu | Maciek | `feat/maciek-plan-store` | do zrobienia | |
| Backend z prawdziwym modelem (prompty, narzędzia, jakość planu) | Maciek | `feat/maciek-backend-ai` | do zrobienia | |
| Generator planu (Swift, wywołuje backend) | Maciek | `feat/maciek-plan-generator` | do zrobienia | |
| Czat trenera (Swift: SSE, narzędzia, zgoda) | Maciek | `feat/maciek-coach-chat` | do zrobienia | |
| Ekrany Plan i Trener | Maciek | `feat/maciek-plan-coach-screens` | Plan: gotowy (Michał, `feat/michal-plan-screen`: tydzień, szczegóły sesji, start serii); Trener: do zrobienia | |

## 10. Co oddajemy (HackTribe)

- Tytuł projektu, nazwa zespołu, lista członków (1–6), opis projektu.
- **PDF maks. 10 slajdów** (PROJECT.md, 12.1) ze zrzutami ekranu, linkiem do repo i demo.
- Nagranie demo z prawdziwego iPhone'a (zapasowe na pitch).
- Link do prototypu klikalnego, oznaczony uczciwie jako prototyp.

## 11. Otwarte sprawy

- [ ] Potwierdzenie z organizatorami, że wcześniejsze planowanie jest w porządku.
- [ ] Potwierdzenie mapowania loginów GitHub na osoby (sekcja 2).
- [ ] Modele iPhone'ów i wersje iOS w zespole (czy cel wdrożenia iOS 17 wystarcza).
- [ ] Nazwa aplikacji i zespołu.
- [ ] Próg reguły „Odpuść” w silniku (zadanie Wiktora).
- [ ] Źródło filmów wzorcowych (własne nagranie albo materiał z jasną licencją).
- [x] **Teraz lokalnie na laptopie; docelowo Vercel + Supabase.** Do zrobienia w `feat/michal-backend-deploy`, gdy przejdziemy na hosting: kto zakłada konta i projekty, zmienne środowiskowe, schemat bazy. Zapas na demo: laptop w tej samej sieci co telefon.
- [ ] Kto trzyma klucz do modelu i token aplikacji (jedna osoba, limit wydatków na kluczu).
- [ ] Wersje Pythona i narzędzi u osób, które będą ruszać backend (`make install` wymaga Pythona 3.11+).
- [ ] Kanał komunikacji zespołu (np. Discord) i sposób zgłaszania blokad.
