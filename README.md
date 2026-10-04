# hackGYM (HackYeah, Sport & Healthcare)

Aplikacja na iPhone'a: trener, plan treningowy i doradca w jednym. Ocenia technikę ćwiczenia z filmu i na żywo (na telefonie), łączy ją z regeneracją i samopoczuciem w rekomendację dnia, układa plan i prowadzi trening z planu, ma czat i rozmowę głosową z trenerem AI.

- Opis produktu i zasady: [PROJECT.md](PROJECT.md)
- Kto co robi, gałęzie i zadania: [WORKINGPLAN.md](WORKINGPLAN.md)
- Reguły pracy w repo (dla ludzi i dla Claude'a): [CLAUDE.md](CLAUDE.md)
- Przebieg treningu z planu: [WORKOUT_FLOW.md](WORKOUT_FLOW.md), jak liczymy technikę z filmu: [docs/ANALIZA_TECHNIKI.md](docs/ANALIZA_TECHNIKI.md)
- Backend: [backend/README.md](backend/README.md), wspólna treść: [content/README.md](content/README.md)

## Po co jest aplikacja

Osoba, która ćwiczy, ma dużo danych (zegarek, sen, samopoczucie) i żadnej odpowiedzi: co dziś zrobić, czy technika jest dobra, kiedy odpuścić, a kiedy zapytać specjalistę. hackGYM ma być **jednym miejscem, które to łączy i podpowiada konkretną decyzję**, zamiast kolejnych wykresów.

Cele:

1. **Plan treningowy dopasowany do osoby** (cel, poziom, dni, czas sesji, sprzęt), który da się edytować i który trener AI może zmieniać za zgodą użytkownika.
2. **Ocena techniki ćwiczenia z kamery**, liczona wyłącznie na telefonie: z filmu z galerii albo na żywo w trakcie serii.
3. **Prowadzenie serii w tempie z planu**: trener mówi „zaczynaj” i oznacza dźwiękiem początek fazy w dół i w górę.
4. **Decyzja dnia** (trenuj według planu, zrób lżej, odpuść) z regeneracji z Apple Health i samopoczucia, z krótkim uzasadnieniem.
5. **Droga do opieki**: gdy ten sam sygnał się powtarza, aplikacja podpowiada konsultację i pomaga znaleźć fizjoterapeutę. Nigdy nie stawia diagnoz.
6. **Prywatność z założenia**: wideo, pozy, rozmowy i dane zdrowotne zostają na telefonie.

## Główne funkcje

- **Plan i trening**: tydzień z sesjami, ręczna edycja (serie, powtórzenia, przerwy, zamiana ćwiczenia, własna sesja, „Cofnij”), ekran po serii, minutnik odpoczynku, wpis ręczny, karta „Jak poszło?” po sesji.
- **Seria na żywo z kamerą**: kadrowanie, kalibracja, komenda „zaczynaj”, potem **dźwięki w stałym rytmie tempa z planu** (niższy = faza w dół, wyższy = faza w górę, pauzy bez dźwięku), liczenie powtórzeń i ocena techniki. Ćwiczenia statyczne (plank) mają tylko „zaczynaj” i odliczanie czasu.
- **Analiza z filmu**: ocena jakości nagrania z konkretną wskazówką („odejdź krok do tyłu”), liczba powtórzeń, wynik techniki 0–100 z uwagami i wykres kąta (przysiad, pompka, podciąganie, dipy).
- **Trener AI**: czat, który zna plan i wyniki, z narzędziami (ustawia cel kroków, proponuje zmiany planu jako karty „Zastosuj / Odrzuć / Cofnij”, sugeruje konsultację) oraz opcjonalna rozmowa głosowa (domyślnie wyłączona).
- **Dziś**: najbliższa sesja, rekomendacja dnia z silnika reguł, regeneracja z Apple Health, cel kroków, check-in.
- **Postępy**: kalendarz aktywności, wykres techniki wybranego ćwiczenia, wykres ciężaru albo powtórzeń.
- **Konto (opcjonalne)**: plan i historia treningów idą za osobą na inny telefon, usuwanie danych i konta w aplikacji.

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

## Jak korzystać z aplikacji

1. **Pierwsze uruchomienie.** Onboarding pyta o cel, poziom, dni w tygodniu, długość sesji, sprzęt oraz o to, czego unikać (historia zdrowia zostaje na telefonie). Potem aplikacja układa plan (AI przez backend, a gdy się nie uda, z gotowego szablonu). Dostęp do Apple Health jest opcjonalny, bez niego użyje danych przykładowych oznaczonych jako takie. Konto Google też jest opcjonalne („Kontynuuj bez konta”).
2. **Dziś.** Zobacz najbliższą sesję i rekomendację dnia. Check-in (nastrój, stres, energia) poprawia dopasowanie. Gdy regeneracja jest słaba, sesja pojawia się w lżejszej wersji; „Przywróć oryginał” cofa korektę.
3. **Plan.** Wybierz dzień. „Zacznij trening” prowadzi przez całą sesję, a strzałka przy ćwiczeniu zaczyna od niego. „Edytuj sesję” zmienia serie, powtórzenia i przerwy, zamienia lub usuwa ćwiczenie (dla jednej sesji albo wszystkich kolejnych), „Dodaj własną sesję” dodaje trening w wolny dzień.
4. **Seria z kamerą.** Postaw telefon w miejscu z podpowiedzi na ekranie (np. przy przysiadzie bokiem do siebie, 2–3 m od ciebie) i załóż słuchawki. Aplikacja sprawdza kadr, prosi o spokojną pozycję startową, a potem mówi „zaczynaj”. Dalej słuchaj dźwięków: **niski dźwięk oznacza początek fazy w dół, wysoki początek fazy w górę**, odstępy wynikają z tempa w planie (np. 3-1-2-0), nie z tego, jak się ruszasz. Po serii dostajesz podsumowanie: tempo, technikę i jakość kadru. Przy ćwiczeniach bez kamery (np. plank) po „Start” słyszysz „zaczynaj” i widzisz odliczanie do celu, a telefon wibruje po jego osiągnięciu. Zawsze możesz wpisać wynik ręcznie.
5. **Analiza.** Wybierz film z galerii albo nagraj teraz (ujęcie z boku, cała sylwetka, co najmniej 3 powtórzenia). Aplikacja najpierw ocenia nagranie i mówi, co poprawić, potem pokazuje wynik 0–100, uwagi i wykres kąta. Film jest kasowany po odczycie.
6. **Trener.** Zapytaj o plan, ćwiczenie, zamiennik albo o to, czy dziś ćwiczyć. Po zgodzie na dane zdrowotne trener zna też regenerację. Gdy proponuje zmianę planu, pojawia się karta: **plan zmienia się dopiero po „Zastosuj”**, a „Cofnij” przywraca poprzedni stan. Rozmowę głosową włączysz w menu „…” u góry ekranu (opcja „Czat głosowy”).
7. **Postępy.** Kalendarz aktywności z ostatnich 12 tygodni oraz wykresy techniki i ciężaru (wybierasz ćwiczenie z planu). Wykresy pokazują się po pierwszych zapisanych seriach i analizach.
8. **Profil.** Konto, synchronizacja, usuwanie danych i konta. Dane przykładowe są wszędzie oznaczone „Dane przykładowe”.

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

W `main` działa wszystko z tabeli wyżej oraz: seria na żywo i analiza z filmu dla czterech ćwiczeń (przysiad, pompka, podciąganie, dipy) z kątami liczonymi z poprawką proporcji obrazu, plan od AI z kontrolą po stronie serwera i planem z szablonu jako zapasem, czat z narzędziami (w tym ustawianiem celu kroków), komenda „zaczynaj” i dźwięki w rytmie tempa z planu (głos systemowy), historia treningów w koncie, usuwanie konta, wspólne limity zapytań w Supabase.

Czego **nikt jeszcze nie sprawdził na prawdziwym iPhonie**: kamera, seria na żywo i analiza na prawdziwych nagraniach (logika jest sprawdzona na syntetycznych pozach i na trzech nagraniach dipów), HealthKit z danymi z zegarka, synchronizacja konta na dwóch telefonach z prawdziwym kontem Google, przyciski i wczytywanie filmu w Analizie po ostatnim refaktorze, głos w słuchawkach. Migracja `user_records` w Supabase musi być zastosowana przez osobę z dostępem do projektu (Wiktor), inaczej synchronizacja historii nie zapisze nic.

## Najważniejsze decyzje architektoniczne

1. **Wrażliwe dane zostają na telefonie.** Punkty ciała liczy Apple Vision na urządzeniu, wideo i klatki nie są wysyłane ani zapisywane. Do sieci idą liczby, podsumowania i tekst wpisany przez użytkownika, a dane zdrowotne tylko po zgodzie. Baza w chmurze **odrzuca** (CHECK) klucze mogące nieść zdrowie, rozmowy albo pozy, więc nawet błąd w kliencie ich tam nie wyśle.
2. **Decyzję dnia podaje silnik reguł, nie model językowy.** Reguły są deterministyczne i testowalne (progi w `content/config/`). Model tylko formułuje tekst, a odpowiedź przechodzi kontrolę bezpieczeństwa i ma szablon zapasowy. Żadnych diagnoz ani twierdzeń medycznych.
3. **Model wołamy wyłącznie przez własny backend.** Klucz do modelu istnieje tylko w środowisku serwera (FastAPI, bezstanowy, na Vercelu). Serwer waliduje wszystko, co zwraca model, nie loguje treści i ma tryb atrapy bez klucza, więc nikt nie czeka na dostęp. Kontrakt API to `backend/openapi.json`.
4. **Plan i trener używają tylko ćwiczeń z katalogu.** Zmiany planu trener tylko **proponuje**: ta sama walidacja działa przy propozycji i przy zatwierdzeniu, a zmiana jest odwracalna.
5. **Logika w modułach SwiftPM, ekrany cienkie.** Cały kod domenowy leży w `Packages/Core` (Contracts, Analysis, LiveSet, Insights, Plan, Coaching i inne) z testami bez symulatora, a ekrany SwiftUI w `App/`. Moduły mają wspólne kontrakty z danymi przykładowymi, więc każdy rozwija swój fragment niezależnie. Projekt Xcode jest generowany z `project.yml` (XcodeGen) i nie leży w repo.
6. **Jeden sygnał ruchu dla wszystkich ćwiczeń.** Przysiad, pompka, podciąganie i dipy sprowadzamy do „głębokości” w długościach tułowia, więc jeden `PhaseTracker` i jeden trener tempa obsługują wszystkie. Kąty liczymy z poprawką proporcji obrazu, a serię na żywo i film oceniają te same oceniacze, więc wyniki są spójne.
7. **Dźwięki tempa to stały zegar, nie reakcja na ruch.** `TempoMetronome` liczy odstępy tylko z tempa w planie. Dzięki temu użytkownik porusza się do rytmu, a nie za nim, a opóźnienie wykrywania fazy (ok. 0,2 s) nie psuje odstępów.
8. **Dane w dwóch warstwach.** Plan, dziennik serii i ukończone sesje leżą w plikach na telefonie i działają bez konta. Po zalogowaniu synchronizują się do Supabase (RLS po `auth.uid()`, telefon pisze bezpośrednio na tokenie użytkownika, backend nie przechowuje danych). Magazyny zgłaszają zmiany, a `AppStore` odświeża ekrany, więc zmiana planu w czacie czy ukończony trening są widoczne od razu we wszystkich zakładkach.
9. **Jedna treść dla backendu i aplikacji.** Katalog ćwiczeń, szablony planów, progi i baza wiedzy trenera są w `content/`: backend je serwuje, a aplikacja ma wbudowaną kopię (`scripts/sync_content.py`), więc działa offline.
10. **iOS 17, szkło tylko przez DesignSystem.** Wygląd wyłącznie przez tokeny i komponenty z `DesignSystem` (Liquid Glass na iOS 26, rozmycie systemowe na starszych przez `#available`), interfejs po polsku, kod i komentarze po angielsku.
11. **Uczciwość wobec użytkownika.** Dane przykładowe zawsze oznaczamy w interfejsie, a w opisach mówimy, co jest zmierzone, a co tylko symulowane.

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
scripts/              sync_content.py (kopia treści do aplikacji)
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
