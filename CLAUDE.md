# Forma: instrukcje dla Claude'a (i dla ludzi) pracujących w tym repo

Aplikacja iOS (SwiftUI) na hackathon HackYeah, kategoria Sport & Healthcare: trener, plan treningowy i doradca w jednym, z analizą techniki i trenerem tempa na żywo. Termin oddania: **4.10, 23:00**. Zespół: Michał (Lead), Bartek, Wiktor, Maciek.

**Zanim zaczniesz:** przeczytaj [PROJECT.md](PROJECT.md) (co budujemy i dlaczego) oraz sekcję swojej osoby w [WORKINGPLAN.md](WORKINGPLAN.md) (twoje zadania, gałęzie i kryteria ukończenia). Pracujesz **niezależnie i asynchronicznie**: nie czekasz na innych, bo wszystkie zależności masz jako interfejsy z danymi przykładowymi (patrz niżej).

## Uruchomienie

```bash
brew install xcodegen
cp Config/Local.xcconfig.example Config/Local.xcconfig       # swój Team ID i unikalny bundle id
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig   # token backendu, nigdy do repo
xcodegen generate && open Forma.xcodeproj
```

Testy logiki (szybkie, bez symulatora): `cd Packages/Core && swift test`.
Backend (opcjonalnie, działa bez klucza): `cd backend && make install && make dev`, a przed PR dotykającym `backend/` lub `content/` `make check`.
Budowanie aplikacji: `xcodegen generate && xcodebuild -project Forma.xcodeproj -scheme Forma -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`.
Plik `Forma.xcodeproj` jest generowany i nie wchodzi do repo. Po `git pull` z nowymi plikami uruchom `xcodegen generate`.

## Mapa modułów i właścicieli

| Ścieżka | Właściciel | Zawartość |
|---|---|---|
| `Packages/Core/Sources/Contracts` | wspólne (zmiany tylko addytywne, patrz niżej) | typy danych, interfejsy usług, dane przykładowe |
| `Packages/Core/Sources/DesignSystem`, `App/` poza `Screens/*` | Michał | tokeny, szkło, komponenty, nawigacja, stan aplikacji |
| `Packages/Core/Sources/LiveSet`, `Onboarding`, `App/Screens/LiveSet`, `App/Screens/Today`, `App/Screens/CheckIn`, `App/Screens/Onboarding` | Michał | seria na żywo, onboarding (w tym historia zdrowia zostająca na telefonie), ekran Dziś, check-in |
| `Packages/Core/Sources/Analysis`, `App/Screens/Analysis` | Bartek | analiza filmu, jakość nagrania, scoring |
| `Packages/Core/Sources/Health`, `Insights`, `App/Screens/Progress`, `App/Screens/Care` | Wiktor | HealthKit, check-in (zapis), silnik reguł, opieka, postępy |
| `Packages/Core/Sources/Plan`, `Coaching`, `Content`, `App/Screens/Plan`, `App/Screens/Coach` | Maciek | katalog, plan, klient modelu, czat trenera |

| `backend/` i `content/` | rdzeń: Michał; AI, plan, czat, katalog: Maciek; teksty i bezpieczeństwo tekstów, `insights.json`: Wiktor; `scoring.json`: Bartek | wspólny backend FastAPI; dokładny podział plików w WORKINGPLAN.md („Co gdzie żyje”), uruchomienie i zasady w [backend/README.md](backend/README.md) |

Edytuj tylko swoje ścieżki. Cudze moduły czytaj, ale nie zmieniaj; jeśli czegoś potrzebujesz, dopisz prośbę w opisie PR albo napisz do właściciela.

## Praca na własnych gałęziach (obowiązkowo)

1. Nie pushuj bezpośrednio na `main`. Każde zadanie to **osobna gałąź** `feat/<imię>-<temat>` (nazwy są w WORKINGPLAN.md), np. `feat/bartek-pose-extractor`.
2. Zacznij od `git checkout main && git pull`, potem `git checkout -b feat/...`.
3. **Małe, częste PR-y** do `main` (najlepiej jedno zadanie = jeden PR, kilka godzin pracy, nie dzień). Otwieraj PR jako draft od razu, kiedy jest pierwszy działający kawałek.
4. Przed PR: `git pull --rebase origin main`, `swift test` w `Packages/Core` i build aplikacji (komendy wyżej) muszą przejść. Opisz w PR, co działa, co jest sprawdzone na symulatorze/telefonie, a co nie.
5. Scalanie: squash do `main` po szybkim przeglądzie przez drugą osobę (zwykle Michał). Po scaleniu inni robią `git pull --rebase origin main`.
6. Po scaleniu swojej gałęzi nie zostawiaj martwych zmian w cudzych plikach.

## Wspólne pliki (konflikty!)

- **`Contracts`:** zmiany tylko **addytywne** (nowe pola z wartością domyślną, nowe typy). Nie zmieniaj ani nie usuwaj istniejących pól bez zgody zespołu. Zmianę kontraktu wrzucaj jako **osobny, malutki PR** („contracts: ...") i od razu pisz na kanale zespołu, bo inni muszą zrobić rebase.
- **`App/Services/AppServices.swift`:** zmieniasz tylko **swoją linię**, kiedy twoja usługa jest gotowa (kto za którą odpowiada, jest w komentarzu w pliku).
- **`Packages/Core/Package.swift`, `project.yml`:** każdy moduł i test target już istnieją, więc zwykle nie trzeba ich zmieniać. Jeśli musisz, zmiana ma być minimalna.
- **`App/AppStore.swift`, `App/RootTabView.swift`, `App/FormaApp.swift`:** należą do Michała. Własny stan trzymaj w swoim module albo w swojej usłudze.

## Interfejsy zamiast czekania

W `Contracts/Services.swift` są protokoły usług (`PlanProviding`, `RecoveryProviding`, `CheckInProviding`, `RecommendationProviding`, `TechniqueHistoryProviding`, `ExerciseCatalogProviding`) i `SampleServices` z danymi przykładowymi („Anna"). Pisz kod przeciw protokołom i testuj na `SampleServices`. Własną implementację podepniesz w `AppServices.swift`, gdy będzie gotowa.

## Konwencje

- Swift 5 (tryb językowy), SwiftUI, cel wdrożenia **iOS 17**, zgodność z **Xcode 26**. Nie używaj API dostępnych tylko w nowszych systemach bez `#available` i rozwiązania zapasowego (szkło Liquid Glass tylko przez komponenty z `DesignSystem`).
- Interfejs po **polsku**, identyfikatory i komentarze w kodzie po **angielsku**.
- Wygląd tylko przez `DesignSystem` (`FormaColor`, `glassCard()`, `.formaPrimary`, `.formaGlass`, `NumberText`, `AmbientBackground`). Nie dodawaj własnych kolorów ani fontów na sztywno.
- Logika w `Packages/Core` z testami (`swift test`), ekrany w `App/Screens/<Funkcja>`. Czysta logika bez UI i bez kamery, żeby dało się ją testować.
- Dane przykładowe zawsze oznaczone w UI jako „Dane przykładowe" (`SimulatedBadge`).
- Nowe pliki dodawaj do `Packages/Core/Sources/<Moduł>` albo `App/Screens/...`. `project.yml` bierze foldery automatycznie.

## Zasady produktu (nie do negocjacji)

- **Żadnych diagnoz ani twierdzeń medycznych.** Piszemy „sygnał", „warto rozważyć konsultację". Każdy nowy tekst zdrowotny przechodzi tę kontrolę (PROJECT.md, 3.6).
- **Wideo i obrazy nie opuszczają telefonu.** Do sieci wychodzą liczby, podsumowania i tekst wpisany przez użytkownika. Dane zdrowotne trafiają do modelu wyłącznie po zgodzie (`DataConsent`) i jako podsumowania.
- **Klucz do modelu nigdy w repozytorium ani w aplikacji.** Żyje tylko w środowisku serwera (`GEMINI_API_KEY`). Aplikacja zna adres i token backendu (`Config/Secrets.xcconfig`, poza gitem). Przed commitem sprawdź `git diff` pod kątem kluczy.
- **Model wołamy tylko przez backend** (`backend/`). Backend nie loguje treści, waliduje wszystko, co zwraca model, i ma szablon zapasowy. Zmiana API = zmiana schematu + `make openapi` + zgodna zmiana po stronie Swifta.
- Decyzję dnia podaje **silnik reguł**, nie model językowy. Plan i trener używają wyłącznie ćwiczeń z katalogu.
- Mówimy uczciwie, co działa, a co jest symulowane. Nie obiecujemy dokładności, której nie zmierzyliśmy.

## Co zrobić na koniec zadania

Zaktualizuj wiersz swojego zadania w tabeli „Status" w WORKINGPLAN.md (w tym samym PR), opisz w PR, jak to sprawdzić, i wskaż, co jeszcze trzeba przetestować na prawdziwym iPhonie.
