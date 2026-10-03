# Plan pracy zespołu: HackYeah, kategoria „Sport & Healthcare”

> Wersja robocza, 2026-10-03. Ten plik mówi, **kto co robi, na jakiej gałęzi i w jakiej kolejności**. Opis produktu i zasady są w [PROJECT.md](PROJECT.md) (numery sekcji w nawiasach), reguły pracy w repo w [CLAUDE.md](CLAUDE.md). Prototyp wyglądu: [Forma — prototyp iOS](https://claude.ai/artifact/STg7G33PFgjptESaMzF8Jk).
>
> Termin oddania: **4 października, 23:00**. Zmiany po terminie są nielegalne.

## 1. Cel i zakres w trzech zdaniach

Budujemy aplikację na iPhone'a (SwiftUI): trener, plan treningowy i doradca w jednym. Ocenia technikę przysiadu (z filmu i na żywo z trenerem tempa w słuchawkach), łączy ją z regeneracją z Apple Health i samopoczuciem w rekomendację dnia, ma plan od AI i czat z trenerem AI. Wersja hackathonowa działa **bez własnego backendu** (model wołany z telefonu), a serwer pośredniczący i Supabase dochodzą po hackathonie (PROJECT.md, 8.1).

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

## 4. Zasady wspólne

1. Przeczytaj PROJECT.md w całości, zwłaszcza sekcje 3.6 (ton tekstów zdrowotnych) i 11.2.
2. Pracujesz w **swoim module**. Zmiana wspólnych typów (kontraktów) tylko addytywnie i za zgodą zespołu.
3. Nowe pliki trafiają do `Packages/Core/Sources/<Moduł>` albo `App/Screens/<Funkcja>`, a nie do pliku projektu.
4. **Klucz API tylko w `Config/Secrets.xcconfig` poza repozytorium.**
5. Wideo i obrazy nigdy nie opuszczają telefonu. Dane zdrowotne trafiają do modelu tylko po zgodzie użytkownika i jako podsumowania.
6. Teksty zdrowotne: „sygnał”, „warto rozważyć konsultację”, nigdy diagnoza.
7. Dane przykładowe są zawsze oznaczone w interfejsie jako symulowane.
8. Zgodność: Xcode 26, cel wdrożenia iOS 17, szkło tylko przez komponenty `DesignSystem`.
9. Zakres tylko z PROJECT.md, sekcja 4. Pomysły spoza zakresu zapisujemy w sekcji 14, nie implementujemy.

## 5. Zadania na osoby (gałęzie, własne foldery, kryteria ukończenia)

Przy każdym zadaniu: **gałąź**, co powstaje, **gotowe, gdy** (kryterium ukończenia). Wszystko można testować na `SampleServices` i danych przykładowych.

### Michał: Lead, UI, integracja, seria na żywo

**Własne ścieżki:** `DesignSystem`, `LiveSet`, `App/` (poza `Screens/Analysis|Plan|Coach|Progress|Care`), `Screens/Today|CheckIn|Onboarding|LiveSet`, `Config/`, `project.yml`, dokumenty.

| Gałąź | Zadanie | Gotowe, gdy |
|---|---|---|
| `feat/michal-onboarding` | Onboarding w 6 krokach + układanie planu (cel, o tobie, sprzęt, historia medyczna, przeciwwskazania, Apple Health) zapisujący `UserProfile` i plan; dane zdrowotne zostają na telefonie | gotowe w PR (profil i plan w `AppStore` i na dysku, kroki zgodne z prototypem, testy logiki). Do zrobienia osobno: ekran profilu |
| `feat/michal-live-set-device` | Test i strojenie serii na żywo na prawdziwym iPhonie: kamera, progi `PhaseTrackerConfig`, głos w słuchawkach, kadr | pełna seria na telefonie z poprawnie liczonymi fazami, lista zmian progów w PR |
| `feat/michal-integration` | Podłączanie usług (`AppServices`), zapis wyników serii i analiz (`TechniqueHistoryProviding`), spięcie ekranów i nawigacji, przejścia Dziś → Plan → seria | cały przepływ klikalny na jednym urządzeniu na danych przykładowych, a potem na prawdziwych usługach |
| `feat/michal-submission` | README dla jury, slajdy (12.1), nagranie demo, zrzuty ekranu, zgłoszenie na HackTribe | komplet materiałów i kompletne zgłoszenie z zapasem przed terminem |

**Prompt startowy dla jego sesji Claude'a:**
```text
Jesteś Michałem (Lead) w projekcie Forma. Przeczytaj CLAUDE.md, PROJECT.md i WORKINGPLAN.md (sekcja „Michał”). Pracujesz na gałęziach feat/michal-*, każde zadanie z tabeli jako osobny mały PR do main. Zacznij od feat/michal-onboarding. Nie edytuj modułów Bartka, Wiktora i Maćka; potrzeby zgłaszaj w opisie PR. Przed PR: swift test w Packages/Core i build aplikacji.
```

### Bartek: Analiza ruchu

**Własne ścieżki:** `Packages/Core/Sources/Analysis` (w tym `Resources/scoring.json`), `Tests/AnalysisTests`, `App/Screens/Analysis`. Może używać `LiveSet` (`PhaseTracker`, `SquatSignal`, `FramingAssessor`, `BasicSquatAssessor`) zamiast pisać od zera.

| Gałąź | Zadanie | Gotowe, gdy |
|---|---|---|
| `feat/bartek-pose-extractor` | `VisionPoseExtractor`: film z pliku (`AVAssetReader`) → `[PoseFrame]`. Nagraj 5–8 przysiadów z boku (w tym błędne) i zapisz wyniki jako **JSON-y do testów** | z filmu wychodzą `PoseFrame` z poprawnymi współrzędnymi (origin lewy górny róg), fixtures w `Tests/AnalysisTests/Fixtures` |
| `feat/bartek-quality-gate` | `QualityGate` dla nagranego filmu (PROJECT.md 6.2): widoczność, wielkość, liczba osób, powtórzenia, klatki na sekundę → `QualityReport` z konkretną wskazówką | testy na fixtures: dobry film przechodzi, złe dostają właściwą podpowiedź |
| `feat/bartek-rep-scoring` | `RepAnalyzer` (powtórzenia i kąty) + `TechniqueScorer` (6.4) → `TechniqueResult`. Progi i wagi w `Resources/scoring.json` | wynik 0–100, uwagi i zamiennik z fixtures, testy jednostkowe |
| `feat/bartek-analysis-screens` | Ekrany Analiza: wybór ćwiczenia, ustawienie telefonu, nagrywanie lub galeria, jakość, przetwarzanie, wynik (6 plansz z prototypu) | przepływ działa na filmie z galerii na symulatorze i na nagraniu na telefonie |

**Prompt startowy:**
```text
Jesteś Bartkiem (Analiza ruchu) w projekcie Forma. Przeczytaj CLAUDE.md, PROJECT.md (sekcja 6) i WORKINGPLAN.md (sekcja „Bartek”). Pracujesz na gałęziach feat/bartek-*, każde zadanie jako osobny mały PR do main. Zacznij od feat/bartek-pose-extractor. Edytuj tylko Packages/Core/Sources/Analysis, Tests/AnalysisTests i App/Screens/Analysis. Możesz używać modułu LiveSet. Zwracaj wynik jako TechniqueResult z Contracts. Przed PR: swift test i build aplikacji.
```

### Wiktor: Dane i reguły

**Własne ścieżki:** `Packages/Core/Sources/Health`, `Insights`, `Tests/HealthTests`, `Tests/InsightsTests`, `App/Screens/Progress`, `App/Screens/Care`.

| Gałąź | Zadanie | Gotowe, gdy |
|---|---|---|
| `feat/wiktor-healthkit` | `HealthKitService` jako `RecoveryProviding` **i `HealthAuthorizing`** (prośba o uprawnienia wołana z onboardingu): sen, tętno spoczynkowe, HRV jako **podsumowania** i punkt odniesienia, fallback na `SampleData` z oznaczeniem symulacji | logika agregacji przetestowana na tablicach próbek, na iPhonie widać prawdziwe dane (jeśli są) |
| `feat/wiktor-checkin-store` | Zapis i odczyt `CheckIn` jako `CheckInProviding` (plik JSON lokalnie) | zapis z ekranu check-inu wraca z `checkIns(days:)`, testy |
| `feat/wiktor-insight-engine` | `InsightEngine` → `DailyRecommendation` (7.2–7.4). **Napraw próg „Odpuść”**: dziś 3 sygnały dają „Odpuść”, a przykład w prototypie to „Zmodyfikuj”. Zaproponuj w PR nowy próg | testy reguł dla scenariuszy (dobry dzień, 1–2 sygnały, wiele sygnałów, flaga opieki), implementacja `RecommendationProviding` |
| `feat/wiktor-plan-adjuster-care` | `PlanAdjuster` (zmiana dzisiejszej sesji według decyzji) i `CarePathway` (flaga „warto rozważyć konsultację”, 7.4) | testy: „Zmodyfikuj” skraca serie i podmienia ćwiczenie z katalogu, „Odpuść” zamienia sesję na odpoczynek |
| `feat/wiktor-progress-care-screens` | Ekrany Postępy (Swift Charts) i Opieka (MapKit, fizjoterapeuci w pobliżu) | ekrany na danych przykładowych, wyszukiwanie w Mapach działa |

**Prompt startowy:**
```text
Jesteś Wiktorem (Dane i reguły) w projekcie Forma. Przeczytaj CLAUDE.md, PROJECT.md (sekcje 7 i 3.6) i WORKINGPLAN.md (sekcja „Wiktor”). Pracujesz na gałęziach feat/wiktor-*, każde zadanie jako osobny mały PR do main. Zacznij od feat/wiktor-healthkit albo feat/wiktor-insight-engine (są niezależne). Edytuj tylko Packages/Core/Sources/Health i Insights, ich testy oraz App/Screens/Progress i Care. Implementuj protokoły RecoveryProviding, CheckInProviding, RecommendationProviding z Contracts/Services.swift i podepnij je w swojej linii App/Services/AppServices.swift dopiero, gdy działają. Teksty zdrowotne: sygnał, nie diagnoza. Przed PR: swift test i build aplikacji.
```

### Maciek: Plan i trener AI

**Własne ścieżki:** `Packages/Core/Sources/Plan` (w tym `Resources/templates.json`), `Coaching`, `Content` (w tym `Resources/catalog.json`), ich testy, `App/Screens/Plan`, `App/Screens/Coach`.

| Gałąź | Zadanie | Gotowe, gdy |
|---|---|---|
| `feat/maciek-catalog-templates` | Katalog ćwiczeń 12–15 pozycji z domyślnym tempem i zamiennikami (`Resources/catalog.json`) jako `ExerciseCatalogProviding` oraz szablony planów (`templates.json`) wg celu, poziomu i dni | katalog ładuje się z zasobów, każdy zamiennik wskazuje istniejące ćwiczenie (test), szablony przechodzą walidację |
| `feat/maciek-plan-store` | `PlanProviding`: aktualny plan i dzisiejsza sesja, zapis lokalny JSON, plan z szablonu dla profilu | `currentPlan()` i `todaySession()` działają, testy |
| `feat/maciek-ai-client` | Klient modelu w Swifcie (`URLSession`, Messages API, streaming, pętla narzędzi). Adres z konfiguracji (`AnthropicBaseURL`), klucz z `AnthropicAPIKey`. Wstrzykiwany transport, żeby testować bez sieci | testy z fałszywym transportem (odpowiedź, streaming, wywołanie narzędzia) |
| `feat/maciek-plan-generator` | `PlanGenerator` jako `PlanGenerating`: model zwraca JSON planu, kod waliduje (istniejące `id`, sprzęt, limity, „czego unikać”, **`profile.avoidTags`** zamieniane na ćwiczenia z katalogu, **`profile.easyStart`** = mniej serii na start), przy błędzie plan z szablonu. Plan ustawia `tempo` w pozycjach | testy walidatora na poprawnych i błędnych odpowiedziach, fallback działa |
| `feat/maciek-coach-chat` | `CoachChat`: instrukcja systemowa (3.6, 7.6), narzędzia (`get_training_plan`, `get_recovery_history`, `get_checkins`, `get_technique_results`, `get_exercise_info`) podpięte do protokołów usług, zgoda `DataConsent` | testy z fałszywym modelem: narzędzia wołane, brak danych zdrowotnych bez zgody, przy bólu odesłanie do specjalisty |
| `feat/maciek-plan-coach-screens` | Ekrany Plan (tydzień, szczegóły sesji, tempo) i Trener (czat, zgoda, pusta rozmowa, błąd, trener pisze). Plan może przejąć Michał | ekrany na danych przykładowych i fałszywym modelu, potem na prawdziwym |

**Prompt startowy:**
```text
Jesteś Maćkiem (Plan i trener AI) w projekcie Forma. Przeczytaj CLAUDE.md, PROJECT.md (sekcje 7.5, 7.6, 8) i WORKINGPLAN.md (sekcja „Maciek”). Pracujesz na gałęziach feat/maciek-*, każde zadanie jako osobny mały PR do main. Zacznij od feat/maciek-catalog-templates albo feat/maciek-ai-client (są niezależne). Edytuj tylko Packages/Core/Sources/Plan, Coaching, Content, ich testy oraz App/Screens/Plan i Coach. Implementuj ExerciseCatalogProviding i PlanProviding z Contracts/Services.swift i podepnij je w swoich liniach App/Services/AppServices.swift dopiero, gdy działają. Narzędzia czatu pisz przeciw protokołom usług i testuj na SampleServices. Klucz API tylko w Config/Secrets.xcconfig. Przed PR: swift test i build aplikacji.
```

## 6. Zależności (kto na kogo czeka)

**Nikt nie czeka.** Każdy buduje swój kawałek na `SampleServices` i `SampleData`. Integrację robi Michał w `feat/michal-integration`, podmieniając sample na prawdziwe implementacje w `AppServices.swift`, gdy poszczególne PR-y trafią do `main`.

## 7. Warunki ukończenia faz

| Faza | Gotowe, gdy |
|---|---|
| 0. Przed startem | każdy zbuduje aplikację na swój telefon i symulator |
| 1. Start | szkielet, kontrakty i usługi są w `main`, zespół ma swoje gałęzie |
| 2. Moduły równolegle | każdy moduł działa na danych przykładowych i ma testy logiki |
| 3. Integracja | jeden pełny przepływ działa na telefonie: onboarding → plan → seria na żywo → analiza → rekomendacja → trener |
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
| Seria na żywo (tempo, głos, podsumowanie) | Michał | `main` | pierwsza wersja | silnik ma testy, kamera niesprawdzona na iPhonie |
| Onboarding | Michał | `feat/michal-onboarding` | w PR | zależy od PR kontraktowego `contracts/onboarding-profile`; ekran profilu (edycja i usuwanie historii zdrowia) jeszcze nie istnieje |
| Seria na żywo na telefonie | Michał | `feat/michal-live-set-device` | do zrobienia | |
| Integracja usług i przepływu | Michał | `feat/michal-integration` | do zrobienia | |
| Materiały i zgłoszenie | Michał | `feat/michal-submission` | do zrobienia | |
| Wydobycie punktów z filmu | Bartek | `feat/bartek-pose-extractor` | do zrobienia | |
| Jakość nagrania | Bartek | `feat/bartek-quality-gate` | do zrobienia | |
| Powtórzenia i scoring | Bartek | `feat/bartek-rep-scoring` | do zrobienia | |
| Ekrany Analiza i Wynik | Bartek | `feat/bartek-analysis-screens` | do zrobienia | |
| HealthKit | Wiktor | `feat/wiktor-healthkit` | do zrobienia | |
| Zapis check-inu | Wiktor | `feat/wiktor-checkin-store` | do zrobienia | |
| Silnik reguł | Wiktor | `feat/wiktor-insight-engine` | do zrobienia | |
| Korekta sesji i opieka | Wiktor | `feat/wiktor-plan-adjuster-care` | do zrobienia | |
| Ekrany Postępy i Opieka | Wiktor | `feat/wiktor-progress-care-screens` | do zrobienia | |
| Katalog i szablony | Maciek | `feat/maciek-catalog-templates` | do zrobienia | |
| Magazyn planu | Maciek | `feat/maciek-plan-store` | do zrobienia | |
| Klient modelu | Maciek | `feat/maciek-ai-client` | do zrobienia | |
| Generator planu | Maciek | `feat/maciek-plan-generator` | do zrobienia | |
| Czat trenera | Maciek | `feat/maciek-coach-chat` | do zrobienia | |
| Ekrany Plan i Trener | Maciek | `feat/maciek-plan-coach-screens` | do zrobienia | |

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
- [ ] Kanał komunikacji zespołu (np. Discord) i sposób zgłaszania blokad.
