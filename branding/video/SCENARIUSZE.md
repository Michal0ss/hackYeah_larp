# hackGym: film demo, 90 s

Cel: oprowadzić po najważniejszych funkcjach.
- **Główny wątek:** trening z trenerem i analiza wideo.
- **Domknięcie:** ścieżka do fizjoterapeuty.
- **Forma:** bez technikaliów. Pokazujemy flow oczami użytkownika.

Format: **1920×1080, 30 fps** (2700 klatek), Remotion.

## Układy kadru

| Układ | Kiedy | Wygląd |
|---|---|---|
| **FULL** | intro, plansze rozdziałów, outro | cały kadr to animacja |
| **SPLIT** | większość filmu | telefon z nagraniem ekranu po jednej stronie, po drugiej animacja, która dopowiada to, co dzieje się na ekranie, i napis |
| **DUO** | seria na żywo | dwa filmy obok siebie: osoba robiąca przysiad i nagranie ekranu telefonu; bez animacji, tylko layout |

### Geometria SPLIT
- Telefon ma wysokość 960 px i szerokość 442 px (proporcje iPhone'a), z zaokrągloną ramką i cieniem. Stoi w 1/3 szerokości kadru.
- **Panel animacji:** pozostałe ok. 1100 px szerokości.
  - Na górze mały nadtytuł rozdziału (Inter 700, 22 px, wersaliki, volt).
  - Pod nim napis (Inter 800, 56 px, maks. 2 linie).
  - Niżej animacja.
- **Strona telefonu:**
  - rozdział „Trening z trenerem”: telefon po lewej;
  - „Analiza wideo” i „Gdy coś nie gra”: telefon po prawej, co daje rytm i odróżnia rozdziały;
  - „Twój dzień”: telefon znów po lewej.
- **Tło:** ciemne tło marki z poświatami (`branding/`), a w panelu delikatna siatka CV na 6% krycia.
- **W obrębie rozdziału** telefon stoi w miejscu, a zmieniają się tylko nagranie i animacja obok (crossfade 6 klatek).
- **Między rozdziałami:** cięcie glitch (8 klatek).

### Geometria DUO (seria na żywo)
- Dwa pionowe kadry tej samej wysokości (880 px), wyśrodkowane, z odstępem 64 px.
  - **Po lewej:** film osoby robiącej przysiad (9:16), w zaokrąglonym prostokącie (promień 40 px) z cienką ramką `rgba(255,255,255,.12)`.
  - **Po prawej:** nagranie ekranu w tej samej ramce telefonu co w SPLIT.
- Nad kadrami wyśrodkowany napis (Inter 800, 52 px) i nadtytuł rozdziału.
- Pod kadrami dwa małe podpisy (Inter 600, 20 px, 60% krycia): „Ty” i „hackGym”.
- Tło: to samo ciemne tło marki z poświatami, bez siatki.
- Oba filmy startują w tej samej klatce, a synchronizację ustawiamy przy montażu (np. po klaśnięciu na początku nagrania).
- Jedyny ruch: wejście całego układu (oba kadry wjeżdżają od dołu ze `spring`, 12 klatek) i wyjście cięciem glitch. Dźwięk to głos trenera z nagrania ekranu.

## Oś czasu

| Czas | Układ | Nagranie | Animacja | Napis |
|---|---|---|---|---|
| 0–4 s | FULL | — | **Intro:** białe punkty, siatka rysuje kettlebell, wypełnia się szkło, glitch, „hack” się wpisuje, „Gym” wskakuje w kolorze volt | — |
| 4–10 s | SPLIT | **R1** onboarding: cel → sprzęt → „układam plan” → plan (×2) | Wybrane odpowiedzi („Siła”, „Bez sprzętu”, „3 dni”) jako chipy wpadają w kalendarz tygodnia, który wypełnia się sesjami | **Plan pod Twój cel i sprzęt** |
| 10–12 s | FULL | — | Plansza rozdziału **„Trening z trenerem”** | — |
| 12–18 s | SPLIT | **R2** Plan → sesja → „Przeprowadź mnie przez trening” → trener tłumaczy przysiad | Dymek trenera, w którym pojawiają się 2–3 krótkie wskazówki z nagrania, obok karta ćwiczenia | **Trener tłumaczy każde ćwiczenie** |
| 18–21 s | SPLIT | **R3** „Ustaw telefon” → „Gotowe, nagrywam” | Ilustracja z boku: telefon na podłodze, osoba 2–3 m dalej, przerywana linia kadru | **Postaw telefon i ćwicz** |
| 21–35 s | DUO | **R4** seria na żywo (ekran) + film osoby z boku, nagrane równocześnie | brak (tylko layout DUO) | **Liczy powtórzenia i prowadzi tempo głosem** |
| 35–40 s | SPLIT | **R5** ekran po serii: wynik, minutnik, „Zapytaj trenera” | Duży wynik serii, pierścień przerwy odlicza, dymek „Zapytaj trenera” | **Po serii wiesz, co poprawić** |
| 40–42 s | FULL | — | Plansza rozdziału **„Analiza wideo”**: siatka przelatuje po sylwetce | — |
| 42–56 s | SPLIT (telefon z prawej) | **R6** analiza: wybór ćwiczenia → film z galerii lub nagranie → sprawdzenie ujęcia → wynik, wykres ruchu, uwagi | Miniatura filmu → po sylwetce przesuwa się skan siatki → licznik wyniku rośnie do wartości z nagrania → uwagi z nagrania jako chipy (np. ✓ dobra głębokość, ! tułów pochylony) | **Nagraj ćwiczenie i sprawdź technikę** |
| 56–61 s | SPLIT (telefon z prawej) | **R7** Postępy: wynik techniki i kalendarz aktywności | Linia wyniku rośnie, kropki kolejnych analiz, plakietka ze zmianą od startu (z nagrania) | **Widzisz, jak rośnie Twoja technika** |
| 61–63 s | FULL | — | Plansza rozdziału **„Gdy coś nie gra”** | — |
| 63–73 s | SPLIT (telefon z prawej) | **R9** karta „Warto rozważyć konsultację” → „Skąd ten sygnał” → „Znajdź fizjoterapeutę w pobliżu” → mapa z wynikami | Chipy sygnałów („ból w notatce”, „ten sam błąd w kilku analizach”) zbiegają się w strzałkę → pinezka na mapie z pulsującym okręgiem 5 km | **Sygnał, nie diagnoza. Pomożemy znaleźć fizjoterapeutę.** |
| 73–83 s | SPLIT (telefon z lewej) | **R8** Dziś: rekomendacja i „Dlaczego?” → czat: „Czy dziś ćwiczyć nogi?” → odpowiedź | Cztery chipy (sen, tętno, samopoczucie, technika) wpadają w jedną kartę z rekomendacją dnia, potem dymki czatu | **Codziennie wiesz, co robić** |
| 83–90 s | FULL | — | **Outro:** logo poziome, hasło, imiona zespołu, link do repo; siatka gaśnie od krawędzi | **Zhakuj swój start na siłowni.** |

Proporcje: ok. 67 s z nagraniami ekranu (w SPLIT i DUO), a w pełni animowane jest 17 s (intro, 3 plansze, outro).

## Animacje do zbudowania w Remotion

**Komponenty wspólne:**
- `<Ambient>`: tło z poświatami;
- `<PhoneFrame src>`: telefon z `<OffthreadVideo>`;
- `<Panel eyebrow title>`: napis z wejściem od dołu (`spring`);
- `<Mesh>`: siatka CV z rysowaniem linii (`evolvePath`);
- `<GlitchCut>`: przejście;
- `<Chip>`, `<Bubble>`: elementy w stylu szkła z aplikacji.

**Sceny:**
1. **Intro** (FULL, 4 s).
2. **Plansze rozdziałów** (FULL, 3 × 2 s): duży tytuł, znak w rogu, przelatująca siatka.
3. **Plan z odpowiedzi:** chipy i kalendarz tygodnia.
4. **Dymek trenera** z wpisywanymi wskazówkami.
5. **Ustawienie telefonu:** prosta ilustracja.
6. **Layout DUO** (bez animacji): dwa filmy obok siebie, opis w sekcji „Geometria DUO”.
7. **Wynik serii** i pierścień przerwy.
8. **Analiza:** skan sylwetki, licznik wyniku, chipy uwag.
9. **Wykres postępów.**
10. **Ścieżka do fizjoterapeuty:** chipy sygnałów, pinezka z okręgiem.
11. **Rekomendacja dnia:** chipy wpadają w kartę, dymki czatu.
12. **Outro** (FULL, 7 s).

Liczby i teksty w animacjach (wynik, zmiana od startu, wskazówki, uwagi) bierzemy **z nagrań**, żeby animacja nie mówiła czegoś innego niż ekran.

## Nagrania do zrobienia (prawdziwy iPhone, nagrywanie ekranu)

| # | Co nagrać | Uwagi |
|---|---|---|
| R1 | Onboarding od celu do planu | czysta instalacja |
| R2 | Plan → sesja → „Przeprowadź mnie przez trening” | odpowiedź trenera przyspieszyć |
| R3 | Ekran „Ustaw telefon” | |
| R4 | Seria na żywo, 3–4 przysiady | **równocześnie** nagranie ekranu i drugi telefon nagrywający osobę z boku; dźwięk trenera z głośnika albo nagrany osobno |
| R5 | Ekran po serii z minutnikiem | |
| R6 | Analiza wideo od wyboru ćwiczenia do wyniku | wcześniej nagrany dobry film z boku |
| R7 | Postępy | |
| R8 | Dziś → „Dlaczego?” → czat | backend musi działać |
| R9 | Opieka → „Znajdź fizjoterapeutę w pobliżu” → mapa | zgoda na lokalizację; na mapie są prawdziwe gabinety, więc nie pokazujemy ich jako poleconych (aplikacja też ich nie poleca) |

## Dźwięk i montaż
- Podkład elektroniczny ok. 110–120 BPM z licencją do użytku.
- Cięcia na bicie.
- W R4 podkład ściszony, żeby był słyszalny głos trenera.

## Zasady
- Ekrany z danymi przykładowymi zostają z plakietką „Dane przykładowe”.
- Bez obietnic dokładności i bez sformułowań medycznych. Przy fizjoterapeucie: „sygnał, nie diagnoza” i „warto rozważyć konsultację”.
- Hasło w outro to propozycja do akceptacji zespołu.
