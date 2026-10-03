# Trening z planu: przebieg sesji, wynik serii, minutnik, pytanie do trenera

Projekt refaktoru treningu (gałąź `feat/maciek-workout-flow`). Dotyka obszaru, który w WORKINGPLAN.md należy do
Michała (`session-flow`, `coach-in-flow`), więc zmiany w `LiveSetView`, `TodayView` i `PlanView` są małe i opisane w PR.

## Przebieg

```text
Dziś / Plan → „Zacznij trening” → podgląd sesji
  → [ ćwiczenie → SERIA → EKRAN PO SERII → następna seria / następne ćwiczenie ] × ćwiczenia
  → podsumowanie sesji → „Zapisz i zakończ” (sesja wykonana, `PlanStore.recordCompletion`)
```

- **Seria.** Ćwiczenie z analizą (przysiad, pompka, podciąganie, z tempem) idzie przez `LiveSetView`. Pozostałe
  (mostek, dead bug, plank) mają prosty ekran: powtórzenia albo czas, opcjonalny ciężar, „Zrobione”.
- **Ekran po serii:** wynik (powtórzenia lub czas, ciężar, przy analizie technika i tempo), minutnik odpoczynku,
  „Edytuj wynik”, „Zapytaj trenera”, podgląd tego, co dalej.
- **Minutnik.** Czas z planu (`restSeconds`), +15 s / −15 s, „Pomiń”. Na zerze dźwięk i wibracja; kolejną serię
  zaczyna użytkownik (trzeba ustawić telefon do kadru). Liczy się od znacznika czasu (`endsAt`), więc przeżywa
  zablokowanie ekranu i arkusz trenera.
- **Zapytaj trenera.** Arkusz z tym samym czatem co zakładka Trener (wspólna historia). Kontekst (`WorkoutContext`):
  ćwiczenie, seria X z Y, wynik ostatniej serii (z kamery: `lastSet`; wpisany ręcznie: `loggedSet`). Bez zgody na dane
  zdrowotne arkusz prosi o zgodę.
- **Ręczny wpis i edycja.** Po serii z analizą można poprawić liczbę powtórzeń (kamera się pomyliła) i dopisać
  ciężar. W ćwiczeniach bez analizy wszystko wpisuje się ręcznie. Ocen techniki i tempa z kamery się nie edytuje.
  Serię można poprawić także później, z zapisu sesji w Planie.
- **Ciężar** jest opcjonalny i podpowiada się z ostatniego razu dla danego ćwiczenia. Używamy go tylko tam, gdzie
  użytkownik go wpisał.
- **Wyjście w połowie.** Serie zapisują się od razu, więc zostają. Sesja jest wykonana po „Zapisz i zakończ” z co
  najmniej jedną serią; częściowa zapisuje „wykonane serie z zaplanowanych”.

## Dane i podział na moduły

| Co | Gdzie |
|---|---|
| `LoggedSet`, `TrainingLogStore` (`training-log.json`) | `Packages/Core/Sources/Plan/TrainingLog.swift` |
| `WorkoutRun` (automat stanów sesji), `RestTimer` | `Packages/Core/Sources/Plan/WorkoutRun.swift` |
| `LoggedSetDigest`, `WorkoutContext.loggedSet` (addytywnie) | `Packages/Core/Sources/Contracts/Session.swift`, backend `schemas/api.py`, `prompts.py` |
| kontekst trenera z biegu sesji | `Packages/Core/Sources/Coaching/WorkoutContextFactory.swift` |
| ekrany | `App/Screens/Workout/` |

Serie z kamery dalej trafiają do `store.recordSet` (historia techniki); ręczne tylko do dziennika. Dziennik zasila też
narzędzie trenera `get_training_log`.

## Czego świadomie nie robimy

Te rzeczy są poza zakresem tego refaktoru. Nie są zapomniane, tylko odłożone.

1. **Feedback po treningu** (RPE 1–10, ból z miejscem i nasileniem, uwagi, krótki tekst trenera, wpływ na reguły i
   rekomendację na jutro): to `session-feedback` Michała i `feedback-rules` Wiktora. Ekran podsumowania sesji zostawia
   na to miejsce, ale go nie wypełnia.
2. **Progresja na podstawie ciężaru** (`plan-progress`): propozycje „dołóż ciężar / powtórzenie” jako karty do
   zatwierdzenia. Dziennik daje jej dane, same propozycje nie wchodzą. Trener może tylko odpowiedzieć na pytanie o
   ciężar z kontekstu serii.
3. **Głos w serii i podczas odpoczynku** (Bartek, `voice-chat`) oraz **powiadomienia w tle**. Dźwięk i wibracja
   minutnika działają przy włączonej aplikacji; po zablokowaniu ekranu czas liczy się poprawnie, ale sygnału nie ma.
4. **Edycja ocen techniki i tempa z kamery.** Użytkownik poprawia liczbę powtórzeń i ciężar, nie wynik analizy.
5. **Automatyczny start kolejnej serii po minutniku.** Start jest ręczny, bo kamera potrzebuje ustawionego telefonu.
6. **Wznawianie przerwanego treningu** po zamknięciu aplikacji. Zapisane serie zostają w dzienniku, ale stan
   przebiegu sesji (które ćwiczenie jest następne) nie jest odtwarzany.
7. **Zmiana planu w trakcie treningu** (dodanie ćwiczenia, zamiana w locie) poza pominięciem ćwiczenia. Do tego
   służy edycja planu na ekranie Plan.
8. **Test na prawdziwym iPhonie.** Analiza z kamery nie działa w symulatorze (jest symulacja); pełny przebieg na
   telefonie trzeba zrobić osobno.
9. **Dane zdrowotne w kontekście pytania.** `WorkoutContext` niesie tylko dane treningowe (liczby, ciężar). Ból i
   wysiłek idą do modelu wyłącznie przez narzędzie za zgodą, jak dotąd.
