# Forma (HackYeah, Sport & Healthcare)

Aplikacja na iPhone'a: trener, plan treningowy i doradca w jednym. Ocenia technikę ćwiczenia z filmu (na telefonie), łączy ją z regeneracją i samopoczuciem w rekomendację dnia, ma plan od AI i czat z trenerem AI.

- Opis produktu i zasady: [PROJECT.md](PROJECT.md)
- Kto co robi, gałęzie i zadania: [WORKINGPLAN.md](WORKINGPLAN.md)
- Reguły pracy w repo (dla ludzi i dla Claude'a): [CLAUDE.md](CLAUDE.md)

## Szybki start

Wymagania: Xcode 26 lub nowszy, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/Michal0ss/hackYeah_larp.git && cd hackYeah_larp
cp Config/Local.xcconfig.example Config/Local.xcconfig       # swój Team ID i unikalny bundle id
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig   # klucz API (nigdy do repo)
xcodegen generate
open Forma.xcodeproj
```

Plik `Forma.xcodeproj` jest **generowany** i nie ma go w repo (dzięki temu różne wersje Xcode nie kłócą się o format projektu). Po zmianie `project.yml` albo po `git pull` z nowymi plikami uruchom `xcodegen generate` ponownie.

Na symulatorze wystarczy `Cmd+R`. Kamera, HealthKit z prawdziwymi danymi i podpis wymagają prawdziwego iPhone'a (Local.xcconfig z `DEVELOPMENT_TEAM`).

## Struktura

```
App/                  aplikacja SwiftUI: ekrany, nawigacja, stan
Packages/Core/        cała logika w modułach (jedna biblioteka = jeden właściciel)
  Contracts           wspólne typy i dane przykładowe (zmiany tylko za zgodą zespołu)
  DesignSystem        tokeny, szkło, przyciski, komponenty
  Analysis            Bartek: Vision, jakość nagrania, powtórzenia, wynik
  Health, Insights    Wiktor: HealthKit, check-in, silnik reguł, opieka
  Plan, Coaching, Content   Maciek: plan, czat z trenerem AI, katalog ćwiczeń
  LiveSet             Michał: seria na żywo (fazy ruchu, tempo, głos, kamera, podsumowanie)
Config/               ustawienia budowania (Local i Secrets są poza repo)
project.yml           opis projektu dla XcodeGen
```

Nowe pliki dodajemy do `Packages/Core` (albo do `App/`), a nie do `.xcodeproj`.

## Testy logiki

```bash
cd Packages/Core && swift test
```

## Zasady

- Zgodność: Xcode 26, cel wdrożenia iOS 17. Szkło (Liquid Glass) na iOS 26, na starszych system-owe rozmycie przez `#available`.
- Klucz API tylko w `Config/Secrets.xcconfig` (poza repo). Wideo i obrazy nie opuszczają telefonu.
- Dane przykładowe zawsze oznaczone w interfejsie jako „Dane przykładowe".
- Teksty zdrowotne: „sygnał", „warto rozważyć konsultację", nigdy diagnoza.
- Reszta zasad: sekcja 11.2 w [PROJECT.md](PROJECT.md).
