# Plan pracy zespołu: HackYeah, kategoria „Sport & Healthcare”

> Stan na 2026-10-03, wieczór (po scaleniu #34 i uruchomieniu Gemini na Vercelu). Ten plik mówi, **kto co robi, na jakiej gałęzi i w jakiej kolejności**. Opis produktu i zasady są w [PROJECT.md](PROJECT.md) (numery sekcji w nawiasach), reguły pracy w repo w [CLAUDE.md](CLAUDE.md). Prototyp wyglądu: [Forma — prototyp iOS](https://claude.ai/artifact/STg7G33PFgjptESaMzF8Jk).
>
> Termin oddania: **4 października, 23:00**. Zmiany po terminie są nielegalne.

## 1. Cel i zakres w trzech zdaniach

Budujemy aplikację na iPhone'a (SwiftUI): trener, plan treningowy i doradca w jednym. Ocenia technikę przysiadu, pompki i podciągania (z filmu i na żywo z trenerem tempa w słuchawkach), łączy ją z regeneracją z Apple Health i samopoczuciem w rekomendację dnia, ma plan od AI i czat z trenerem AI. **Jeden wspólny backend** (FastAPI, folder `backend/`) trzyma klucz do modelu (**Gemini**) i robi całą pracę z modelem (plan, czat, teksty), a telefon robi resztę: analizę wideo, tempo na żywo, reguły, dane zdrowotne (PROJECT.md, 8.1 i 8.3). Szkielet backendu jest w `main` i działa od razu bez klucza (tryb offline z atrapą modelu).

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

### Jak uruchomić i zbudować na telefonie

1. Raz: `brew install xcodegen`, `cp Config/Local.xcconfig.example Config/Local.xcconfig` (swój Team ID i unikalny bundle id), `cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig`.
2. Backend (opcjonalny, działa bez klucza w trybie atrapy): `cd backend && make install && make dev`. Z prawdziwym modelem: `export GEMINI_API_KEY=...` (klucz z **płatnego** projektu Google z limitem budżetu).
3. `git checkout main && git pull`, potem `xcodegen generate && open Forma.xcodeproj`. Wybierz symulator albo swojego iPhone'a i Cmd+R. iPhone: tryb dewelopera włączony, sparowany z Xcode, a w `Config/Secrets.xcconfig` `FORMA_API_URL` ustawiony na adres komputera w sieci (np. `http:/$()/192.168.1.20:8000`).
4. **Test analizy na żywo na telefonie:** Dziś → ikona profilu → „Test analizy na żywo” (przysiad, pompka, podciąganie) → ikona biedronki pokazuje liczby, a „Wyślij pozy (JSON)” eksportuje nagrane pozy (do fixtures Bartka).
5. Po zmianie `content/` uruchom `python scripts/sync_content.py`; przed PR dotykającym `backend/` lub `content/`: `make check` w `backend/`; przed każdym PR: `swift test` w `Packages/Core` i build aplikacji.

## 4. Zasady wspólne

1. Przeczytaj PROJECT.md w całości, zwłaszcza sekcje 3.6 (ton tekstów zdrowotnych) i 11.2.
2. Pracujesz w **swoim module**. Zmiana wspólnych typów (kontraktów) tylko addytywnie i za zgodą zespołu.
3. Nowe pliki trafiają do `Packages/Core/Sources/<Moduł>` albo `App/Screens/<Funkcja>`, a nie do pliku projektu.
4. **Klucz do modelu tylko w środowisku serwera (`GEMINI_API_KEY`), nigdy w repozytorium ani w aplikacji.** Aplikacja ma tylko adres i token backendu (`FORMA_API_URL`, `FORMA_API_TOKEN` w `Config/Secrets.xcconfig` poza gitem).
5. Wideo i obrazy nigdy nie opuszczają telefonu. Dane zdrowotne trafiają do modelu tylko po zgodzie użytkownika i jako podsumowania.
6. Teksty zdrowotne: „sygnał”, „warto rozważyć konsultację”, nigdy diagnoza.
7. Dane przykładowe są zawsze oznaczone w interfejsie jako symulowane.
8. Zgodność: Xcode 26, cel wdrożenia iOS 17, szkło tylko przez komponenty `DesignSystem`.
9. Zakres tylko z PROJECT.md, sekcja 4. Pomysły spoza zakresu zapisujemy w sekcji 14, nie implementujemy.
10. **Backend:** nie logujemy treści (żądań, promptów, czatu, danych zdrowotnych), tylko metadane. Wszystko, co zwraca model, jest walidowane po stronie serwera, a plan i teksty mają zapas w szablonie. Wolny tekst użytkownika jest daną, nie poleceniem (`sanitize_free_text`). Przed PR dotykającym `backend/` lub `content/`: `make check` w `backend/`.
11. **Praca bez klucza:** `make dev` w `backend/` działa w trybie atrapy (plany z szablonu, czat z gotowymi odpowiedziami, nawet z wywołaniem narzędzi), więc nikt nie czeka na klucz. Prawdziwy model uruchamia się przez `GEMINI_API_KEY` w swoim terminalu.

## 5. Zadania na osoby (gałęzie, własne foldery, kryteria ukończenia)

Przy każdym zadaniu: **gałąź**, co powstaje, **gotowe, gdy**. „Zrobione” to rzeczy już w `main` (szczegóły i uwagi w sekcji 9). Tematy poniżej są **aktualne na 3.10 wieczór** i uporządkowane od najważniejszego. Zakres jest zamrożony: nowe pomysły idą do PROJECT.md, sekcja 14.

### Michał: Lead, UI, integracja, seria na żywo

**Własne ścieżki:** `DesignSystem`, `LiveSet`, `API`, `App/` (poza `Screens/Analysis|Plan|Coach|Progress|Care`), `Screens/Today|CheckIn|Onboarding|LiveSet|Profile`, `Config/`, `project.yml`, dokumenty, rdzeń backendu (tabela wyżej).

**Zrobione:** szkielet, kontrakty, DesignSystem, Dziś, Check-in, onboarding, Profil, klient API, `ContentRepository`, integracja usług (silnik reguł, korekta sesji, teksty rekomendacji, zapis wyników), ekran Plan, wejście do Opieki z Dziś, szkielet backendu, szkielet Vercela, analiza na żywo dla przysiadu, pompki i podciągania z diagnostyką.

| Gałąź | Temat | Gotowe, gdy |
|---|---|---|
| `feat/michal-live-set-device` | **Test analizy na żywo na iPhonie** (przysiad, pompka, podciąganie): szkielet pokrywa się z ciałem, 15/15 stawów, FPS ≥ 15, kąty i liczba powtórzeń zgodne z rzeczywistością, głos nadąża. Strojenie progów w `content/config/tempo.json` i ocen w `UpperBodyAssessors`/`BasicSquatAssessor`. Nagranie 2–3 serii dobrych i złych na każde ćwiczenie i wysłanie JSON-ów do Bartka | pełna seria każdego z trzech ćwiczeń na telefonie z poprawnie liczonymi fazami, lista zmian progów w PR, pliki z pozami u Bartka |
| `feat/michal-submission` | README dla jury, 10 slajdów (PROJECT.md 12.1), nagranie demo z prawdziwego iPhone'a (zapasowe na pitch), zrzuty ekranu, zgłoszenie na HackTribe | komplet materiałów i wysłane zgłoszenie z zapasem przed terminem |
| `feat/michal-backend-deploy` | **Wdrożone na Vercelu z Gemini** (adres i zasady w `backend/README.md`). Zostaje: test czatu z telefonu, sprawdzenie kosztów i decyzja o Supabase (limity zapytań) | czat działa przez strumień z telefonu, klucz tylko w sekretach hostingu, decyzja o Supabase zapisana |
| `feat/michal-demo-polish` | Scenariusz demo: dane startowe (check-in, plan), tryb demo bez przypadkowych błędów, puste stany, jasny motyw i Dynamic Type na Dziś/Plan/Profil, edycja pól profilu, wejście do Opieki z wyniku analizy (po #22), zapis wyników analiz Bartka do Dziś/Postępów, usunięcie tymczasowego `BackendPlanGenerator`, gdy Maciek odda swój | całe demo da się przejść od czystej instalacji bez ręcznych obejść |

**Prompt startowy dla jego sesji Claude'a:**
```text
Jesteś Michałem (Lead) w projekcie Forma. Przeczytaj CLAUDE.md, PROJECT.md i WORKINGPLAN.md (sekcja „Michał” i „Jak uruchomić i zbudować na telefonie”). Pracujesz na gałęziach feat/michal-*, każde zadanie jako osobny mały PR do main. Zacznij od feat/michal-live-set-device (test na iPhonie), potem feat/michal-submission. Nie edytuj modułów Bartka, Wiktora i Maćka; potrzeby zgłaszaj w opisie PR. Przed PR: swift test w Packages/Core i build aplikacji.
```

### Bartek: Analiza ruchu i głos

**Własne ścieżki:** `Packages/Core/Sources/Analysis`, `content/config/scoring.json`, `Tests/AnalysisTests`, `App/Screens/Analysis`. Od 3.10 także **głos** (decyzja Michała): `Packages/Core/Sources/LiveSet/Engine/CoachVoice.swift`, `LiveSet/Tempo/CuePlanner.swift`, `LiveSet/Tempo/PolishText.swift`, nowy folder `LiveSet/Voice/` oraz nowe pliki `App/Screens/Coach/Voice/` (rozmowa głosowa). Pozostałe pliki `LiveSet` i `Screens/Coach` zostają u Michała i Maćka: potrzebną tam zmianę zrób minimalną w osobnym małym PR i opisz ją w PR, żeby właściciel zrobił rebase. Może używać `LiveSet` (`MovementKind`, `PhaseTracker`, `SquatSignal`, `FramingAssessor`, `Basic*Assessor`).

**Zrobione (w `main`):** `VisionPoseExtractor` z obsługą obrotu filmu (#13), `QualityGate` (#28), `RepAnalyzer` + `TechniqueScorer` (przysiad) i **sześć ekranów analizy** (#34): wideo kasowane po odczycie, plik z galerii kopiowany, bez sztucznego czekania, ekstrakcja poza wątkiem interfejsu.

| Gałąź | Temat | Gotowe, gdy |
|---|---|---|
| `feat/bartek-voice-tempo` | **Głos trenera tempa na żywo: płynniejszy i naturalniejszy** (priorytet 2, to część rdzenia dema). Dziś `SpeechCoachVoice` mówi systemowym głosem `pl-PL` bez wyboru jakości, uciętymi wypowiedziami i gubi korekty, gdy coś mówi. Do zrobienia: (1) wybór najlepszego zainstalowanego głosu polskiego (`AVSpeechSynthesisVoice.speechVoices()`, jakość `premium` > `enhanced` > `default`), a gdy tylko podstawowy, podpowiedź w Profilu, jak pobrać lepszy (Ustawienia → Dostępność → Treści mówione → Głosy); (2) odstępy i tempo liczenia dopasowane do tempa fazy (przy wolnym tempie „jeeedeen… dwaaa…” zamiast równego klikania), mniejsze opóźnienie (rozgrzanie syntezatora w `prepare()`, opcjonalnie wcześniejsze wyrenderowanie słów liczenia przez `AVSpeechSynthesizer.write` i odtwarzanie przez `AVAudioEngine` z dokładnym czasem); (3) korekty **w kolejce na następną pauzę** zamiast gubienia, kilka wariantów każdej korekty bez powtarzania tej samej dwa razy z rzędu (`CuePlanner`/`CoachingPolicy`), poprawna polszczyzna liczb i jednostek (`PolishText`); (4) odliczanie przed serią („trzy, dwa, jeden, start”) i krótkie podsumowanie na końcu („osiem powtórzeń, dobra robota”); (5) opóźnienie Bluetooth (A2DP ok. 200 ms): przesuń sygnały o `AVAudioSession.outputLatency`; przerwania (telefon, Siri), zmiana wyjścia i oddanie muzyki po serii (`duckOthers` + `notifyOthersOnDeactivation`); (6) wspólny wybór głosu i tempa mowy w `LiveSet/Voice/`, żeby korzystał z niego też czat | seria przysiadów na iPhonie ze słuchawkami brzmi płynnie: liczenie nie urywa się, korekta nie ginie, nie ma ciszy ani nakładania; logika kolejkowania i wariantów ma testy (czysta logika bez głośnika); w PR opis, jaki głos i jakie ustawienia wybrano |
| `feat/bartek-voice-chat` | **Rozmowa głosowa z trenerem** (priorytet 4, po `voice-tempo`). Przycisk mikrofonu na ekranie Trener: mówisz, widzisz rozpoznany tekst, odpowiedź trenera jest czytana na głos w miarę napływu strumienia (zdanie po zdaniu, nie po całości). Zasady: (1) rozpoznawanie mowy tylko **na telefonie**: `SFSpeechRecognizer(locale: pl-PL)` z `requiresOnDeviceRecognition = true` i sprawdzeniem `supportsOnDeviceRecognition`; gdy niedostępne, mikrofon jest ukryty z jasnym komunikatem (nagranie głosu nie może wychodzić z telefonu; do backendu idzie tylko tekst, jak dziś); (2) rozpoznany tekst idzie normalną drogą `CoachViewModel.send` (ta sama zgoda, te same narzędzia, ta sama historia), a **nie** osobnym kanałem do modelu; (3) automatyczne wysłanie po ok. 1,2 s ciszy z możliwością anulowania i poprawienia tekstu; (4) czytanie odpowiedzi: wspólny syntezator z `voice-tempo`, czyszczenie markdownu i źródeł przed mówieniem, przerwanie (barge-in) po dotknięciu mikrofonu lub przycisku stop, przełącznik „Czytaj odpowiedzi” zapamiętany w `UserDefaults`; (5) sesja audio `.playAndRecord` + `.spokenAudio`/`.voiceChat`, `defaultToSpeaker`, `allowBluetooth`, po rozmowie oddanie sesji; (6) uprawnienia: `NSSpeechRecognitionUsageDescription` i opis mikrofonu są już w `project.yml`, pytaj o nie dopiero po pierwszym dotknięciu mikrofonu, a odmowa nie psuje czatu tekstowego; (7) **nie zmieniaj** `CoachViewModel`/`CoachChat`: dodaj `VoiceChatController` w `App/Screens/Coach/Voice/`, który obserwuje `messages` i `streamingText`, a w `CoachView` dopisz tylko przycisk (zmianę zgłoś Maćkowi w PR) | rozmowa „zapytaj głosem → usłyszysz odpowiedź” działa na iPhonie na prawdziwym modelu; odmowa uprawnień i brak rozpoznawania offline obsłużone; wycofanie zgody zdrowotnej nadal czyści rozmowę; logika segmentowania zdań i czyszczenia tekstu ma testy; w PR uczciwy opis, co nie sprawdzone (np. dokładność rozpoznawania polskiego na urządzeniu) |
| `feat/bartek-scoring-kinds` | **Dokończ analizę z filmu dla trzech ćwiczeń:** scoring pompki (kąt łokcia, linia ciała) i podciągania (głowa nad rękami, kąt łokcia), spójny z ocenami na żywo z `LiveSet` (nie dwa różne wyniki), `QualityGate` z parametrem `kind` (dziś sprawdza kadr tylko jak dla przysiadu), `RepAnalyzer` na `MovementKind`, wejście do Opieki z ekranu wyniku (`CareView`), tekst „Przysiady z boku” na ekranie nagrania zależny od ćwiczenia | wynik 0–100, uwagi i zamiennik dla każdego z trzech ćwiczeń, testy, wejście do Opieki z wyniku |
| `feat/bartek-fixtures` | **Prawdziwe dane:** pliki póz z testu na żywo (JSON od Michała) i własne nagrania przez `VisionPoseExtractor`, po 5–8 na ćwiczenie (dobre i złe: płytko, pochylony, opadające biodra, niepełne podciągnięcie), testy na fixtures, strojenie `content/config/scoring.json` | `swift test` na fixtures przechodzi, progi dostrojone, opis w PR które nagrania i co zmieniono |

**Kolejność przy ograniczonym czasie:** `voice-tempo` (to słychać w demo) → `scoring-kinds` (pompka i podciąganie z filmu) → `voice-chat` → `fixtures`. Rozmowa głosowa to rozszerzenie spoza pierwotnego zakresu (PROJECT.md, sekcja 4), dodane decyzją Michała 3.10: jeśli zabraknie czasu, wypada przed resztą, a czat tekstowy zostaje bez zmian.

**Prompt startowy:**
```text
Jesteś Bartkiem (Analiza ruchu i głos) w projekcie Forma. Przeczytaj CLAUDE.md, PROJECT.md (sekcje 6 i 6.7) i WORKINGPLAN.md (sekcja „Bartek”). Pracujesz na gałęziach feat/bartek-*, każde zadanie jako osobny mały PR do main. Zacznij od feat/bartek-voice-tempo: ulepsz głos trenera tempa w serii na żywo (Packages/Core/Sources/LiveSet/Engine/CoachVoice.swift, Tempo/CuePlanner.swift, Tempo/PolishText.swift, nowy folder LiveSet/Voice/), tak żeby brzmiał płynnie i naturalnie na iPhonie w słuchawkach. Potem feat/bartek-scoring-kinds, feat/bartek-voice-chat (rozmowa głosowa z trenerem; rozpoznawanie mowy tylko na telefonie, do backendu tylko tekst przez CoachViewModel.send) i feat/bartek-fixtures. Edytuj tylko Packages/Core/Sources/Analysis, content/config/scoring.json, Tests/AnalysisTests, App/Screens/Analysis, swoje pliki głosu (lista w WORKINGPLAN.md) i nowy App/Screens/Coach/Voice; w pozostałych plikach LiveSet i Coach tylko minimalne zmiany w osobnym PR i z opisem. Zwracaj wynik jako TechniqueResult z Contracts. Przed PR: swift test i build aplikacji. Test na prawdziwym iPhonie ze słuchawkami jest częścią zadania.
```

### Wiktor: Dane i reguły

**Własne ścieżki:** `Packages/Core/Sources/Health`, `Insights`, `Tests/HealthTests`, `Tests/InsightsTests`, `App/Screens/Progress`, `App/Screens/Care`, część backendu: `services/text_service.py`, `services/safety.py`, `ai/prompts/text_system.md`, `routers/texts.py`, `content/config/insights.json`.

**Zrobione (w `main`):** HealthKit, `CheckInStore`, silnik reguł z poprawkami, `PlanAdjuster` i `CarePathway`, teksty rekomendacji (serwer i telefon), ekrany Postępy i Opieka.

| Gałąź | Temat | Gotowe, gdy |
|---|---|---|
| `feat/wiktor-device-checks` | **Sprawdzenie na iPhonie:** prawdziwe dane z Apple Health (sen, tętno spoczynkowe, HRV; brak dzisiejszego snapshotu rano, dzień z brakującym HRV), wyszukiwanie fizjoterapeutów z prawdziwą lokalizacją, wykresy w jasnym motywie, Dynamic Type i VoiceOver. Poprawki w PR | lista sprawdzonych rzeczy w PR, błędy poprawione |
| `feat/wiktor-text-live` | **Teksty z prawdziwym modelem:** `cd backend && GEMINI_API_KEY=... .venv/bin/python scripts/check_texts.py --live`, dostrojenie `text_system.md` i filtrów (odrzuca „nie diagnozuję”, więc sprawdź fałszywe alarmy). Uzupełnij `detect_red_flags` w `safety.py` o „boli mnie w klatce”, „brakuje mi tchu”, „kłuje w klatce” | co najmniej 10 odpowiedzi modelu przeszło przez filtry bez fałszywych odrzuceń, nowe wzorce złapały przykłady objawów |
| `feat/wiktor-copy-audit` | **Audyt tekstów zdrowotnych w całej aplikacji** (PROJECT.md 3.6): ekrany, prompty trenera i planu, Opieka, Profil, czat, teksty reguł. Szukaj diagnoz, obietnic, rozkazów, ostrzeżeń bez „sygnał / warto rozważyć konsultację”. Lista zmian w PR | żaden tekst w aplikacji nie diagnozuje, każdy ma odesłanie do specjalisty tam, gdzie trzeba |
| `feat/wiktor-progress-history` | (priorytet 5, tylko jeśli starczy czasu) zapis decyzji dnia i historia sesji w Postępach, karta „Dzień odpoczynku” na Dziś | decyzje dnia widać na osi czasu w Postępach |

**Prompt startowy:**
```text
Jesteś Wiktorem (Dane i reguły) w projekcie Forma. Przeczytaj CLAUDE.md, PROJECT.md (sekcje 7 i 3.6) i WORKINGPLAN.md (sekcja „Wiktor”). Pracujesz na gałęziach feat/wiktor-*, każde zadanie jako osobny mały PR do main. Zacznij od feat/wiktor-device-checks albo feat/wiktor-text-live (są niezależne). Edytuj tylko Packages/Core/Sources/Health i Insights, ich testy, App/Screens/Progress i Care oraz swoje pliki backendu i content/config/insights.json. Teksty zdrowotne: sygnał, nie diagnoza. Przed PR: swift test i build aplikacji, a przy zmianach backendu make check w backend/.
```

### Maciek: Plan i trener AI

**Własne ścieżki:** `Packages/Core/Sources/Plan`, `Coaching`, `Content`, ich testy, `App/Screens/Plan`, `App/Screens/Coach`, część backendu: `backend/app/ai/` (poza `text_system.md`), `services/{plan_builder,plan_validator,plan_service,coach_service}.py`, `routers/{plans,coach,catalog}.py`, `content/catalog.json`, `content/plan_templates.json`.

**Zrobione (w `main`):** backend AI na Gemini z kaskadą modeli i testami (#11), czat trenera ze zgodą, narzędziami i historią (#30), ekran Trener. Ekran Plan zrobił Michał, tymczasowy `BackendPlanGenerator` też.

| Gałąź | Temat | Gotowe, gdy |
|---|---|---|
| `feat/maciek-plan-generator` | **Swift `PlanGenerator`** jako `PlanGenerating` (zastępuje tymczasowy `BackendPlanGenerator` w `AppServices.swift`): `POST /v1/plans/generate` przez moduł `API`, ostrzeżenia (`ai_unavailable`, `ai_invalid_plan`...) widoczne w UI, plan offline z kopii `plan_templates.json` | test na fałszywym transporcie: plan AI, plan z szablonu z ostrzeżeniem, błąd sieci → plan lokalny; onboarding działa bez backendu |
| `feat/maciek-plan-store` | **Magazyn planu:** `PlanProviding` z zapisem lokalnym, **oznaczanie sesji jako wykonanej** (`PlannedSession.status`) i jego trwałość, plan i status wracają po restarcie | `currentPlan()` i `todaySession()` działają na zapisanym planie, status sesji przeżywa restart |
| `feat/maciek-catalog-templates` | **Treść:** ćwiczenia ciągnięcia bez sprzętu (dziś tylko `superman`), `videoURL`, znacznik ćwiczenia złożonego (cel „siła” nie bierze izolacji), sprawdzenie planów z `pullup` i `pushup` (które mają analizę na żywo), spójność tempa. `make check` pilnuje spójności | katalog ma sensowny wybór bez sprzętu i na siłownię, plany od modelu i z szablonu przechodzą walidator |
| `feat/maciek-coach-polish` | **Czat na telefonie i z płatnym kluczem:** test na iPhonie, koszt rozmowy, test widoku (wycofanie zgody czyści rozmowę), „Zastosuj w planie” (`propose_plan_change`, priorytet 5, tylko jeśli starczy czasu), karta konsultacji po wzmiance o bólu | czat działa na telefonie na prawdziwym modelu, opis w PR: modele, koszt, ograniczenia |

**Prompt startowy:**
```text
Jesteś Maćkiem (Plan i trener AI) w projekcie Forma. Przeczytaj CLAUDE.md, PROJECT.md (sekcje 7.5, 7.6, 8) i WORKINGPLAN.md (sekcja „Maciek”). Pracujesz na gałęziach feat/maciek-*, każde zadanie jako osobny mały PR do main. Zacznij od feat/maciek-plan-generator, potem feat/maciek-plan-store (backend: backend/README.md). Edytuj tylko Packages/Core/Sources/Plan, Coaching, Content, ich testy, App/Screens/Plan i Coach oraz swoje pliki backendu i content/ (tabela „Co gdzie żyje” w WORKINGPLAN.md). Model wołasz wyłącznie przez backend (moduł API), klucza do modelu nie ma w aplikacji. Przed PR: swift test i build aplikacji, a przy zmianach backendu make check w backend/.
```

## 6. Zależności (kto na kogo czeka)

**Nikt nie czeka.** Każdy buduje swój kawałek na `SampleServices` i `SampleData`. Backend w trybie atrapy daje wszystkim te same odpowiedzi bez klucza (plany z szablonu, czat z gotowymi odpowiedziami i wywołaniem narzędzi). Integrację robi Michał w `feat/michal-integration`, podmieniając sample na prawdziwe implementacje w `AppServices.swift`, gdy poszczególne PR-y trafią do `main`.

## 7. Warunki ukończenia faz

| Faza | Gotowe, gdy |
|---|---|
| 0. Przed startem | każdy zbuduje aplikację na swój telefon i symulator |
| 1. Start | szkielet aplikacji, kontrakty, usługi i **szkielet backendu** są w `main`, zespół ma swoje gałęzie |
| 2. Moduły równolegle | każdy moduł działa na danych przykładowych i ma testy logiki |
| 3. Integracja (**jesteśmy tutaj**) | jeden pełny przepływ działa na telefonie: onboarding → plan → seria na żywo → analiza → rekomendacja → trener; backend lokalnie albo na Vercelu |
| 4. Dopracowanie i zgłoszenie | **zamrożenie funkcji 4.10 rano** (propozycja, do potwierdzenia przez zespół), ostatnie PR-y tylko poprawki, zgłoszenie kompletne i wysłane **najpóźniej 4.10 wieczorem z zapasem co najmniej 3 godzin** przed terminem 23:00 |

## 8. Priorytety, gdy zabraknie czasu

Wyższy zawsze przed niższym (PROJECT.md, 4.2):
1. **Rdzeń:** analiza przysiadu z oceną jakości nagrania, regeneracja i check-in, rekomendacja dnia, ekran „Dziś”.
2. **Seria na żywo:** liczenie tempa w słuchawkach, podsumowanie serii.
3. **Plan:** onboarding, plan na tydzień, dzisiejsza sesja (zapas: szablon).
4. **Trener AI:** czat z kontekstem.
5. **Dopełnienie:** Opieka (MapKit), wykres postępów, przycisk „Zastosuj w planie”.

## 9. Status

Aktualizuj swój wiersz w tym samym PR, w którym kończysz zadanie. Stan: 3.10 wieczór. „Nie sprawdzone” znaczy, że nikt nie uruchomił tego na prawdziwym urządzeniu lub modelu.

| Obszar | Kto | Status | Uwagi |
|---|---|---|---|
| Szkielet, kontrakty, DesignSystem, Dziś, Check-in, onboarding, Profil | Michał | w `main` | Profil: podgląd, usuwanie historii zdrowia i wszystkich danych, ponowne układanie planu; edycji pól jeszcze nie ma |
| Klient API (`API`), `ContentRepository` (kopia treści, cache, ETag) | Michał | w `main` | po zmianie `content/` uruchom `python scripts/sync_content.py`; przy zmianie typów w cache podbij `cacheFormat` |
| Integracja: silnik reguł na Dziś, korekta sesji (Plan, Dziś), teksty rekomendacji, zapis wyników, check-in | Michał, Wiktor | w `main` | `BackendPlanGenerator` (tymczasowy) do zastąpienia przez Maćka |
| Ekran Plan | Michał | w `main` | tydzień, szczegóły sesji, start serii, „Przywróć oryginał”; bez oznaczania wykonania (Maciek: magazyn planu) |
| Seria na żywo: przysiad, pompka, podciąganie, diagnostyka, eksport póz | Michał | w `main` | sprawdzone na symulacji i headless; **kamera i iPhone nie sprawdzone**, progi to wartości startowe |
| Backend: szkielet (Michał), AI na Gemini z kaskadą i testami (Maciek) | Michał, Maciek | w `main` | 58 testów, `make check`; plany 6/6 i czat 9/9 na prawdziwym modelu; 3.10: plan (`source: ai`) i strumień czatu sprawdzone `curl`-em na Vercelu z prawdziwym modelem; z telefonu nie sprawdzone |
| Wdrożenie na Vercel | Michał | **wdrożone, Gemini aktywny** (`https://forma-api-three.vercel.app`) | `/health` pokazuje `aiMode: gemini`; `GEMINI_API_KEY` w sekretach Vercela (produkcja i podgląd); token (401 bez, 200 z), katalog z ETag, plan i czat działają. Supabase: nie założony, limit 2 darmowych projektów, limity zapytań są w pamięci |
| Analiza z filmu: ekstraktor póz, `QualityGate` | Bartek | w `main` | obrót filmu z iPhone'a obsłużony; bez prawdziwych nagrań |
| Analiza z filmu: `RepAnalyzer` + `TechniqueScorer`, sześć ekranów analizy (#34) | Bartek | w `main` | tylko przysiad; pompka, podciąganie, `QualityGate` z `kind` i wejście do Opieki z wyniku w `feat/bartek-scoring-kinds`; bez prawdziwych nagrań i bez sprawdzenia na iPhonie |
| Głos trenera tempa: płynność i naturalność | Bartek | do zrobienia | `feat/bartek-voice-tempo`; dziś systemowy głos `pl-PL`, korekty giną, gdy coś mówi |
| Rozmowa głosowa z trenerem (mikrofon + czytanie odpowiedzi) | Bartek | do zrobienia | `feat/bartek-voice-chat`; rozpoznawanie mowy tylko na telefonie, do backendu tylko tekst |
| HealthKit, `CheckInStore`, silnik reguł, `PlanAdjuster`, `CarePathway`, teksty rekomendacji | Wiktor | w `main` | dialog uprawnień sprawdzony na symulatorze; prawdziwe dane z zegarka i teksty z prawdziwym modelem nie sprawdzone |
| Ekrany Postępy i Opieka | Wiktor | w `main` | wejście do Opieki z Dziś jest; z wyniku analizy w `feat/bartek-scoring-kinds` |
| Czat trenera (zgoda, narzędzia lokalne, historia), ekran Trener | Maciek | w `main` | wycofanie zgody czyści rozmowę (#31); nie sprawdzone na telefonie |
| Swift `PlanGenerator`, magazyn planu, treść katalogu | Maciek | do zrobienia | tematy w sekcji 5 |

## 10. Co oddajemy (HackTribe)

- Tytuł projektu, nazwa zespołu, lista członków (1–6), opis projektu.
- **PDF maks. 10 slajdów** (PROJECT.md, 12.1) ze zrzutami ekranu, linkiem do repo i demo.
- Nagranie demo z prawdziwego iPhone'a (zapasowe na pitch).
- Link do prototypu klikalnego, oznaczony uczciwie jako prototyp.

## 11. Otwarte sprawy

- [ ] **Klucz Gemini:** ustawiony w sekretach Vercela 3.10 (trzyma go Michał, nikt inny go nie potrzebuje). Do potwierdzenia: czy to klucz z **płatnego** projektu z limitem budżetu. Darmowy poziom to 20 zapytań na dobę na model i Google może używać treści zapytań.
- [x] **Wdrożenie:** Vercel (`https://forma-api-three.vercel.app`). Token aplikacji ma Michał. Zapas na demo: laptop + hotspot i nagranie.
- [ ] Supabase: darmowy limit 2 projektów jest wyczerpany (TogetherPlan, trackly). Potrzebny tylko do wspólnych limitów zapytań; decyzja Michała (wstrzymać jeden projekt, użyć osobnego schematu w istniejącym albo zrezygnować).
- [ ] Zamrożenie funkcji 4.10 rano i godzina wysłania zgłoszenia (propozycja w sekcji 7), potwierdzenie przez zespół.
- [ ] Potwierdzenie z organizatorami, że wcześniejsze planowanie jest w porządku.
- [ ] Potwierdzenie mapowania loginów GitHub na osoby (sekcja 2) oraz modele iPhone'ów i wersje iOS w zespole.
- [ ] Nazwa aplikacji i zespołu na zgłoszenie.
- [ ] Źródło filmów wzorcowych (własne nagranie albo materiał z jasną licencją).
- [ ] Kanał komunikacji zespołu (np. Discord) i sposób zgłaszania blokad.
- [x] Próg reguły „Odpuść” w silniku (4 sygnały regeneracji, #4).
- [x] Dostawca modelu: Gemini (#11).
