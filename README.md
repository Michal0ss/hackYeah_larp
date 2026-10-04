# hackGYM (HackYeah, Sport & Healthcare)

Aplikacja na iPhone'a: trener, plan treningowy i doradca w jednym. Ocenia technikę ćwiczenia z filmu i na żywo (na telefonie), łączy ją z regeneracją i samopoczuciem w rekomendację dnia, układa plan i prowadzi trening z planu, ma czat i rozmowę głosową z trenerem AI.

- Opis produktu i zasady: [PROJECT.md](PROJECT.md)
- Kto co robi, gałęzie i zadania: [WORKINGPLAN.md](WORKINGPLAN.md)
- Reguły pracy w repo (dla ludzi i dla Claude'a): [CLAUDE.md](CLAUDE.md)
- Przebieg treningu z planu: [WORKOUT_FLOW.md](WORKOUT_FLOW.md), jak liczymy technikę z filmu: [docs/ANALIZA_TECHNIKI.md](docs/ANALIZA_TECHNIKI.md)
- Backend: [backend/README.md](backend/README.md), wspólna treść: [content/README.md](content/README.md)

## Co jest w aplikacji

Dolny pasek: **Dziś, Plan, Trener, Analiza, Postępy.**

| Zakładka | Co robi |
|---|---|
| Dziś | na górze najbliższa sesja z odliczaniem („Dziś”, „Jutro”, „Za N dni”), rekomendacja dnia z silnika reguł (nie z modelu), sygnał opieki, pasek regeneracji z Apple Health, panel „Dane zdrowotne” (sen, kroki, cel kroków ustalany przez trenera, nastrój), check-in |
| Plan | tydzień z sesjami, szczegóły, korekta sesji pod regenerację i „Przywróć oryginał”, start treningu |
| Trener | czat z trenerem AI (zgoda na dane zdrowotne, narzędzia, karty „Zastosuj / Odrzuć” dla zmian planu, historia) i rozmowa głosowa |
| Analiza | film z galerii albo nagrany teraz → ocena jakości nagrania → liczba powtórzeń, technika i wykres kąta (przysiad, pompka, podciąganie, dipy) |
| Postępy | kalendarz aktywności, wykres techniki wybranego ćwiczenia, wykres ciężaru albo powtórzeń, opieka |

Poza zakładkami: onboarding (cel, poziom, dni, czas sesji 30–90 min, sprzęt, historia zdrowia zostaje na telefonie), trening z planu (ekran po serii, minutnik odpoczynku, ręczny wpis, karta „Jak poszło?” po sesji), seria na żywo z kamerą i trenerem tempa w słuchawkach, Profil (konto Google, synchronizacja, usuwanie danych i konta).

Konto w chmurze (Supabase, logowanie Google): plan, odpowiedzi z onboardingu bez pól zdrowotnych, serie, ukończone sesje, wyniki analiz, podsumowania serii na żywo i cel kroków idą za osobą na inny telefon. Wideo, pozy, czat, dane z Apple Health, check-iny i feedback po treningu zostają tylko na telefonie. Pełny podział: PROJECT.md, 8.3.

## Szybki start

Wymagania: Xcode 26 lub nowszy, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/Michal0ss/hackYeah_larp.git && cd hackYeah_larp
cp Config/Local.xcconfig.example Config/Local.xcconfig       # swój Team ID i unikalny bundle id
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig   # token backendu (nigdy do repo)
xcodegen generate
open Forma.xcodeproj
```

Plik `Forma.xcodeproj` jest **generowany** i nie ma go w repo (dzięki temu różne wersje Xcode nie kłócą się o format projektu). Po zmianie `project.yml` albo po `git pull` z nowymi plikami uruchom `xcodegen generate` ponownie.

Backend (FastAPI) uruchamiasz osobno, działa od razu bez klucza do modelu (tryb atrapy):

```bash
cd backend && make install && make dev     # http://localhost:8000, dokumentacja: /docs
```

Na prawdziwym telefonie ustaw `FORMA_API_URL` w `Config/Secrets.xcconfig` na adres Maca w sieci (np. `http://192.168.1.20:8000`). Szczegóły: [backend/README.md](backend/README.md).

Wspólny backend jest wdrożony na Vercelu z prawdziwym modelem (Gemini): `https://forma-api-three.vercel.app`, produkcja odświeża się sama po scaleniu do `main`. Żeby aplikacja z niego korzystała, wpisz w `Config/Secrets.xcconfig` `FORMA_API_URL = https:/$()/forma-api-three.vercel.app` i `FORMA_API_TOKEN` (token dostajesz od Michała, nigdy do repo). Bez tego aplikacja łączy się z lokalnym backendem albo działa na danych przykładowych. Klucz do modelu jest tylko w sekretach Vercela, nikt poza Michałem go nie potrzebuje.

Na symulatorze wystarczy `Cmd+R`. Kamera, HealthKit z prawdziwymi danymi i podpis wymagają prawdziwego iPhone'a (`Local.xcconfig` z `DEVELOPMENT_TEAM`). Logowanie Google i synchronizacja konta wymagają konfiguracji Supabase (`Config/Secrets.xcconfig`); bez niej aplikacja działa na samym telefonie.

## Stan projektu (4.10)

Zamrożenie funkcji i oddanie: **4.10, zgłoszenie z zapasem przed 23:00.** Aktualny stan zadań i uwag: [WORKINGPLAN.md](WORKINGPLAN.md), sekcja 9.

W `main` działa wszystko z tabeli wyżej oraz: seria na żywo i analiza z filmu dla czterech ćwiczeń (przysiad, pompka, podciąganie, dipy) z kątami liczonymi z poprawką proporcji obrazu, plan od AI z kontrolą po stronie serwera i planem z szablonu jako zapasem, czat z narzędziami (w tym ustawianiem celu kroków), głos trenera tempa z banku nagrań, historia treningów w koncie, usuwanie konta, wspólne limity zapytań w Supabase.

Czego **nikt jeszcze nie sprawdził na prawdziwym iPhonie**: kamera, seria na żywo i analiza na prawdziwych nagraniach (logika jest sprawdzona na syntetycznych pozach i na trzech nagraniach dipów), HealthKit z danymi z zegarka, synchronizacja konta na dwóch telefonach z prawdziwym kontem Google, przyciski i wczytywanie filmu w Analizie po ostatnim refaktorze, głos w słuchawkach. Migracja `user_records` w Supabase musi być zastosowana przez osobę z dostępem do projektu (Wiktor), inaczej synchronizacja historii nie zapisze nic.

## Struktura

```
App/                  aplikacja SwiftUI: ekrany (Screens/), usługi i konto (Services/), nawigacja, stan
Packages/Core/        cała logika w modułach (jedna biblioteka = jeden właściciel)
  Contracts           wspólne typy, interfejsy usług i dane przykładowe (zmiany tylko addytywne)
  DesignSystem        tokeny, szkło, przyciski, komponenty
  API                 klient backendu
  Analysis            Vision, jakość nagrania, powtórzenia, wynik z filmu
  LiveSet             seria na żywo: fazy ruchu, tempo, kamera, oceniacze ćwiczeń, głos trenera tempa
  CoachVoice          rozmowa głosowa z trenerem (rozpoznawanie mowy i czytanie odpowiedzi)
  Health, Insights    HealthKit, check-in, cel kroków, silnik reguł, opieka, dane wykresów
  Plan, Coaching, Content   plan, dziennik treningu, czat z trenerem AI, katalog ćwiczeń i kopia treści
  Onboarding          pierwsze uruchomienie (profil, historia zdrowia na telefonie, generowanie planu)
backend/              wspólny backend (FastAPI): plan, czat trenera, teksty, konto, treść; patrz backend/README.md
content/              wspólna treść: katalog ćwiczeń, szablony planów, progi, baza wiedzy trenera (serwowana przez backend, kopia w aplikacji)
api/, vercel.json     wejście i ustawienia wdrożenia backendu na Vercelu
scripts/              sync_content.py (kopia treści do aplikacji), generate_voice_bank.py (nagrania trenera tempa)
docs/                 analiza techniki z filmu, materiały marki (docs/brand)
Config/               ustawienia budowania (Local i Secrets są poza repo)
project.yml           opis projektu dla XcodeGen
```

Aplikacja nazywa się **hackGYM**. Nazwy techniczne zostają „Forma”: projekt i schemat Xcode (`Forma.xcodeproj`), typy w kodzie (`FormaColor`, `FormaAPI`), zmienne `FORMA_*`, folder danych na telefonie (`Application Support/Forma`), adres `forma-api-three.vercel.app` i bundle id. Zmiana któregokolwiek z nich wymagałaby migracji danych albo ponownej konfiguracji wszystkich osób.

Nowe pliki dodajemy do `Packages/Core` (albo do `App/`), a nie do `.xcodeproj`. Właściciele modułów: [CLAUDE.md](CLAUDE.md).

## Testy

```bash
cd Packages/Core && swift test      # logika aplikacji, bez symulatora
cd backend && make check            # lint, testy, walidacja treści, aktualność openapi.json i kopii treści
```

Przed PR dotykającym `backend/` lub `content/` uruchom `python scripts/sync_content.py` i `make check`. Po zmianie szablonów planów odśwież też plik porównawczy planu z backendu dla Swifta: `backend/.venv/bin/python Packages/Core/Tests/PlanTests/Fixtures/generate.py`.

## Zasady

- Zgodność: Xcode 26, cel wdrożenia iOS 17. Szkło (Liquid Glass) na iOS 26, na starszych system-owe rozmycie przez `#available`.
- Klucz do modelu tylko na serwerze (`GEMINI_API_KEY`), w aplikacji wyłącznie adres i token backendu (`Config/Secrets.xcconfig`, poza repo). Wideo i obrazy nie opuszczają telefonu.
- Dane przykładowe zawsze oznaczone w interfejsie jako „Dane przykładowe".
- Teksty zdrowotne: „sygnał", „warto rozważyć konsultację", nigdy diagnoza.
- Cudze PR-y scalamy merge commitem (nie squashem), bo Vercel (plan Hobby) blokuje wdrożenia commitów autorów spoza zespołu.
- Reszta zasad: sekcja 11.2 w [PROJECT.md](PROJECT.md).
