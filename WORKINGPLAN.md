# Plan pracy zespołu: HackYeah, kategoria „Sport & Healthcare”

> Wersja robocza, 2026-10-03. Ten plik mówi, **kto co robi i w jakiej kolejności**. Opis produktu, zasady oceny i szczegóły techniczne są w [PROJECT.md](PROJECT.md) (numery sekcji w nawiasach). Prototyp wyglądu: [Forma — prototyp iOS](https://claude.ai/artifact/STg7G33PFgjptESaMzF8Jk).
>
> **Kodu projektu nie piszemy przed 23:00 3 października** (regulamin, pkt 5). Do tej pory robimy tylko „Teraz”, czyli przygotowanie środowiska. Termin oddania: **4 października, 23:00**.

## 1. Cel i zakres w trzech zdaniach

Budujemy aplikację na iPhone'a (SwiftUI): trener, plan treningowy i doradca w jednym. Ocenia technikę przysiadu z filmu (na telefonie), łączy ją z regeneracją z Apple Health i samopoczuciem w rekomendację dnia, ma plan od AI i czat z trenerem AI. Wersja hackathonowa działa **bez własnego backendu** (model wołany z telefonu), a serwer pośredniczący i Supabase dochodzą po hackathonie (PROJECT.md, 8.1).

## 2. Zespół

| | Rola | Imię | iPhone / iOS | Xcode |
|---|---|---|---|---|
| **Osoba 1** | Lead, UI i integracja | [uzupełnić] | [uzupełnić] | [uzupełnić] |
| **Osoba 2** | Analiza ruchu | [uzupełnić] | [uzupełnić] | [uzupełnić] |
| **Osoba 3** | Dane i reguły | [uzupełnić] | [uzupełnić] | [uzupełnić] |
| **Osoba 4** | Plan i trener AI | [uzupełnić] | [uzupełnić] | [uzupełnić] |

Projekt Xcode zakłada **osoba z Xcode 26** (projekt zapisany w Xcode 27 może się nie otwierać w 26). Kto ma 27, nie zgadza się na „upgrade project format”. Założy go: **[uzupełnić]**.

## 3. Flow projektu

```
Faza 0: Przed startem  →  Faza 1: Start razem  →  Faza 2: Moduły równolegle  →  Faza 3: Integracja  →  Faza 4: Dopracowanie i zgłoszenie
(tylko środowisko)        (decyzje, projekt,       (każdy swój moduł            (jeden pełny            (zamrożenie funkcji,
                           kontrakty)               na danych przykładowych)     przepływ na telefonie)  slajdy, demo, HackTribe)
```

Do następnej fazy przechodzimy, gdy spełniony jest jej warunek ukończenia, a nie według zegara.

## 4. Zasady dla wszystkich

1. Przeczytaj PROJECT.md w całości, zwłaszcza sekcję 11.2.
2. Pracujesz w **swoim module**. Zmiana wspólnych typów (kontraktów, 9.1) tylko za zgodą zespołu.
3. Nowe pliki trafiają do lokalnego pakietu `Core`, a nie do pliku projektu (`.pbxproj`).
4. Małe commity, częste scalanie, nie edytujemy równocześnie tych samych plików.
5. **Klucz API tylko w `Secrets.xcconfig` poza repozytorium** (wpis w `.gitignore`).
6. Wideo i obrazy nigdy nie opuszczają telefonu. Dane zdrowotne trafiają do modelu tylko po zgodzie użytkownika i jako podsumowania.
7. Teksty zdrowotne: „sygnał”, „warto rozważyć konsultację”, nigdy diagnoza.
8. Dane przykładowe są zawsze oznaczone w interfejsie jako symulowane.
9. Zgodność: Xcode 26, cel wdrożenia iOS 17, szkło (Liquid Glass) z zapasem na starsze systemy przez `#available`.
10. Zakres tylko z PROJECT.md, sekcja 4. Pomysły spoza zakresu zapisujemy w sekcji 14, nie implementujemy.

## 5. Zadania na osoby

### Osoba 1: Lead, UI i integracja

**Teraz (przed 23:00):**
- [ ] Konto na HackTribe i dostęp do Discorda HackYeah.
- [ ] Pytanie do organizatorów: czy wcześniejsze planowanie jest w porządku.
- [ ] Zebranie od zespołu: kto ma Xcode 26, modele iPhone'ów i wersje iOS (tabela w sekcji 2).
- [ ] Propozycje nazwy aplikacji (w prototypie „Forma”) i nazwy zespołu.

**Od 23:00, po kolei:**
- [ ] Poprowadzić start: decyzje (nazwa, zakres, role) i sprawdzenie, że projekt buduje się u wszystkich.
- [ ] Spisać **kontrakty** (9.1) w `Core/Contracts` i zebrać akceptację zespołu.
- [ ] Moduł **DesignSystem** z tokenów prototypu (kolory, typografia, szkło, promienie) i szklane komponenty.
- [ ] Pasek zakładek **Dziś · Plan · Analiza · Trener · Postępy**.
- [ ] Ekrany **Dziś, Check-in, Onboarding**.
- [ ] Integracja modułów, nagranie demo, slajdy (12.1), README dla jury, zgłoszenie na HackTribe.

**Dostarcza innym:** kontrakty i DesignSystem (jako pierwsze).
**Wsparcie:** po skończeniu przejmuje UI ekranu **Plan** od Osoby 4.

### Osoba 2: Analiza ruchu

**Teraz (przed 23:00):**
- [ ] Kamera i podpis aplikacji sprawdzone na **pustej aplikacji testowej poza projektem**.
- [ ] Statyw i miejsce do nagrań (same nagrania po 23:00).

**Od 23:00, po kolei:**
- [ ] Nagranie 5–8 przysiadów z boku, w tym błędnych (za duże pochylenie, za płytko, postać za mała w kadrze).
- [ ] `VisionPoseExtractor`: klatki z pliku → punkty ciała → `PoseFrame`. Wynik zapisany też jako **JSON do testów**, żeby reszta nie potrzebowała wideo.
- [ ] `QualityGate` (progi z 6.2) z konkretną wskazówką przy porażce.
- [ ] `RepAnalyzer`: wygładzenie, powtórzenia, kąty.
- [ ] `TechniqueScorer` (6.4): wynik 0–100, uwagi, zamiennik. Progi i wagi w jednym pliku JSON.
- [ ] Ekrany **Analiza** (wybór, ustawienie telefonu, nagrywanie, jakość, przetwarzanie) i **Wynik**.
- [ ] Testy jednostkowe scoringu na zapisanych `PoseFrame`.

**Dostarcza innym:** `TechniqueResult` (najpierw makieta z prawdziwymi polami) dla Osób 1 i 3.

### Osoba 3: Dane i reguły

**Teraz (przed 23:00):**
- [ ] Uprawnienie HealthKit sprawdzone na **pustej aplikacji testowej poza projektem** przy darmowym podpisie.
- [ ] Sprawdzenie, jakie dane o śnie i tętnie ma jej iPhone.

**Od 23:00, po kolei:**
- [ ] `RecoverySnapshot` i **dane przykładowe** profilu „Anna” (14 dni, oznaczone jako symulowane, spójne z prototypem).
- [ ] `HealthKitService`: sen, tętno spoczynkowe, HRV jako **podsumowania** i punkt odniesienia.
- [ ] Model `CheckIn` i zapis lokalny.
- [ ] `InsightEngine` (7.2–7.4) z testami. Do rozstrzygnięcia: reguła „Odpuść” przy 3 sygnałach nie zgadza się z przykładem w prototypie („Zmodyfikuj”). Zaproponować zespołowi poprawkę progu.
- [ ] `PlanAdjuster` (zmiana dzisiejszej sesji) i `CarePathway` z wyszukiwaniem fizjoterapeutów (MapKit).
- [ ] Ekrany **Opieka** i **Postępy** (Swift Charts).
- [ ] Funkcje dla narzędzi czatu: `get_recovery_history` i `get_checkins`.

**Dostarcza innym:** `DailyRecommendation` (najpierw makieta) dla Osób 1 i 4.

### Osoba 4: Plan i trener AI

**Teraz (przed 23:00):**
- [ ] Konto i klucz do Claude API z **limitem wydatków**, jedno zapytanie testowe poza projektem, klucz trzymany poza repozytorium.

**Od 23:00, po kolei:**
- [ ] **Katalog ćwiczeń** (12–15 pozycji, JSON) i typ `ExerciseItem`.
- [ ] **Plan z szablonu** (kilka szablonów według celu i poziomu). To wersja zapasowa, więc najpierw ona.
- [ ] Klient API w Swifcie (`URLSession`, streaming, pętla narzędzi). Adres wywołań modelu jako jedno ustawienie w konfiguracji.
- [ ] `PlanGenerator`: model zwraca JSON, nasz kod **waliduje** (istniejące `id`, sprzęt, limity), a przy błędzie używa szablonu.
- [ ] `CoachChat`: instrukcja systemowa (3.6, 7.6), narzędzia (`get_training_plan`, `get_recovery_history`, `get_checkins`, `get_technique_results`, `get_exercise_info`), **zgoda na dane zdrowotne** (`DataConsent`).
- [ ] Ekrany **Plan** i **Trener** (zgoda, pusta rozmowa, trener pisze, błąd). Plan może przejąć Osoba 1.
- [ ] Testy walidatora planu i kilka testowych pytań do czatu (ból, uraz, „czy ćwiczyć dziś”).

**Dostarcza innym:** `TrainingPlan` i dzisiejszą sesję dla Osób 1 i 3.

## 6. Zależności

| Od | Do | Co |
|---|---|---|
| Osoba 1 | wszyscy | kontrakty i DesignSystem |
| Osoba 2 | Osoby 1 i 3 | `TechniqueResult` (makieta, potem prawdziwy) |
| Osoba 3 | Osoby 1 i 4 | `DailyRecommendation` i funkcje narzędzi czatu |
| Osoba 4 | Osoby 1 i 3 | `TrainingPlan` i dzisiejsza sesja |

**Zasada:** każdy publikuje najpierw makietę swojego typu (z prawdziwymi polami), żeby nikt nie czekał na gotowy moduł.

## 7. Warunki ukończenia faz

| Faza | Gotowe, gdy |
|---|---|
| 0. Przed startem | każdy zbuduje pustą aplikację testową na swój telefon |
| 1. Start razem | projekt buduje się u wszystkich, kontrakty są w repo i zaakceptowane |
| 2. Moduły równolegle | każdy moduł działa na danych przykładowych i na pustych danych, ma testy logiki |
| 3. Integracja | jeden pełny przepływ działa na telefonie: onboarding → plan → analiza → rekomendacja (zmiana sesji) → trener |
| 4. Dopracowanie i zgłoszenie | funkcje zamrożone, zgłoszenie na HackTribe kompletne i wysłane z zapasem przed terminem |

## 8. Priorytety, gdy zabraknie czasu

Wyższy zawsze przed niższym (PROJECT.md, 4.2):
1. **Rdzeń:** analiza przysiadu z oceną jakości nagrania, regeneracja i check-in, rekomendacja dnia, ekran „Dziś”.
2. **Plan:** onboarding, plan na tydzień, dzisiejsza sesja (zapas: szablon).
3. **Trener AI:** czat z kontekstem.
4. **Dopełnienie:** Opieka (MapKit), wykres postępów, przycisk „Zastosuj w planie”.

## 9. Co oddajemy (HackTribe)

- Tytuł projektu, nazwa zespołu, lista członków (1–6), opis projektu.
- **PDF maks. 10 slajdów** (PROJECT.md, 12.1) ze zrzutami ekranu, linkiem do repo i demo.
- Nagranie demo z prawdziwego iPhone'a (zapasowe na pitch).
- Link do prototypu klikalnego, oznaczony uczciwie jako prototyp.

## 10. Status

| Obszar | Osoba | Status | Uwagi |
|---|---|---|---|
| Projekt i kontrakty | 1 | do zrobienia | |
| DesignSystem i nawigacja | 1 | do zrobienia | |
| Dziś / Check-in / Onboarding | 1 | do zrobienia | |
| Analiza ruchu i scoring | 2 | do zrobienia | |
| Ekrany Analiza i Wynik | 2 | do zrobienia | |
| Dane, HealthKit, silnik reguł | 3 | do zrobienia | |
| Opieka i Postępy | 3 | do zrobienia | |
| Katalog i plan | 4 | do zrobienia | |
| Czat trenera | 4 | do zrobienia | |
| Slajdy, demo, README, zgłoszenie | 1 | do zrobienia | |

## 11. Otwarte sprawy

- [ ] Potwierdzenie z organizatorami, że wcześniejsze planowanie jest w porządku.
- [ ] Kto zakłada projekt w Xcode 26.
- [ ] Modele iPhone'ów i wersje iOS w zespole (czy cel wdrożenia iOS 17 wystarcza).
- [ ] Nazwa aplikacji i zespołu.
- [ ] Próg reguły „Odpuść” w silniku (spójność z prototypem).
- [ ] Źródło filmów wzorcowych (własne nagranie albo materiał z jasną licencją).
- [ ] Kanał komunikacji zespołu (np. Discord) i sposób zgłaszania blokad.
