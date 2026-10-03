# Opis projektu i plan działania: HackYeah, kategoria „Sport & Healthcare”

> Wersja robocza, 2026-10-03. Dokument dla całego zespołu **i dla agentów AI pracujących przy projekcie**. Opisuje, co budujemy, dlaczego, jak ma to działać i jak się organizujemy. Przeczytaj go w całości, zanim zaczniesz pracować.
>
> **Kodu nie piszemy przed 23:00 3 października** (regulamin, pkt 5: zespół zaczyna rozwiązywać zadanie nie wcześniej niż o 23:00 3.10). Dotyczy to też agentów AI. Kwestię wcześniejszego przygotowania potwierdzamy z organizatorami na Discordzie HackYeah.
>
> Pozycje oznaczone **[do ustalenia]** czekają na decyzję zespołu.

## Spis treści

1. [Ramy z regulaminu](#1-ramy-z-regulaminu)
2. [Zadanie i kryteria oceny](#2-zadanie-i-kryteria-oceny)
3. [Idea produktu](#3-idea-produktu)
4. [Zakres demo](#4-zakres-demo)
5. [Opis ekranów i przepływów](#5-opis-ekranów-i-przepływów)
6. [Jak działa analiza ruchu](#6-jak-działa-analiza-ruchu)
7. [Jak powstaje rekomendacja, plan i odpowiedzi trenera](#7-jak-powstaje-rekomendacja-plan-i-odpowiedzi-trenera)
8. [Technologia i organizacja repozytorium](#8-technologia-i-organizacja-repozytorium)
9. [Architektura i kontrakty między modułami](#9-architektura-i-kontrakty-między-modułami)
10. [Plan działania](#10-plan-działania)
11. [Role i zasady pracy (zespół i agenci AI)](#11-role-i-zasady-pracy-zespół-i-agenci-ai)
12. [Prezentacja, demo i pitch](#12-prezentacja-demo-i-pitch)
13. [Ryzyka](#13-ryzyka)
14. [Dalsza wizja](#14-dalsza-wizja-po-hackathonie)
15. [Otwarte decyzje](#15-otwarte-decyzje)

---

## 1. Ramy z regulaminu

| Sprawa | Wymóg |
|---|---|
| Start pracy | nie wcześniej niż **3.10, 23:00** |
| Termin oddania | najpóźniej **4.10, 23:00**. Zmiany po terminie są nielegalne i jury ich nie uwzględnia |
| Zespół | do 6 osób |
| Oddajemy na HackTribe | tytuł projektu, nazwa zespołu, lista członków (1–6), opis projektu, **PDF maks. 10 slajdów** (zrzuty ekranu, repo, linki do demo, grafiki) |
| Język zgłoszenia | polski lub angielski |
| Faza 1 | komisja (min. 3 mentorów) ocenia zgłoszenia na HackTribe |
| Faza 2 | finaliści prezentują na żywo przed jury (pitch) |
| Nagroda | 8 000 zł brutto, wymaga co najmniej 50% punktów w fazie 1 |
| Prawa autorskie | zostają przy autorach |

**Wniosek:** w fazie 1 jurorzy widzą tylko to, co wrzucimy na HackTribe. Prezentacja, zrzuty ekranu i nagranie demo liczą się tak samo jak sama aplikacja.

## 2. Zadanie i kryteria oceny

Treść zadania: narzędzie, aplikacja lub system, które **holistycznie łączy sport, zdrowie fizyczne, dobrostan psychiczny i dostęp do opieki zdrowotnej**. Użytkownicy mają dużo rozproszonych danych (smartwatche, aplikacje, wyniki badań, samopoczucie), które trudno zinterpretować i rzadko zamieniają się w konkretne działania. Narzędzie ma nie tylko monitorować, ale **pomagać podejmować lepsze decyzje** o zdrowiu i stylu życia.

| Kryterium | Waga | Nasza odpowiedź |
|---|---|---|
| Pomysł i innowacyjność | 30% | Technika ruchu z nagrania telefonem, liczona wyłącznie na urządzeniu, połączona z danymi z Apple Health i samopoczuciem w jedną codzienną rekomendację |
| Związek z kategorią | 20% | Wszystkie cztery obszary: sport (analiza ruchu), zdrowie fizyczne (sen, tętno, regeneracja), dobrostan psychiczny (check-in), dostęp do opieki (kiedy i gdzie szukać fizjoterapeuty) |
| Praktyczne zastosowanie | 20% | Jedna odpowiedź na codzienne pytanie „co dziś zrobić?” zamiast kolejnych wykresów |
| Design | 20% | Spójny system wizualny i kilka dopracowanych ekranów zamiast wielu niedokończonych |
| Kompletność i wartość wdrożeniowa | 10% | Jeden przepływ działający od początku do końca na prawdziwym iPhonie, plus nagranie demo |

## 3. Idea produktu

### 3.1 Problem

Osoba, która ćwiczy i dba o zdrowie, ma dużo danych, ale żadnej odpowiedzi:

- Zegarek mówi, że spała 5,5 godziny i ma niższą zmienność rytmu serca. Co z tym zrobić przed dzisiejszym treningiem nóg?
- Ćwiczy przysiady sama, bez trenera. Nie wie, czy technika jest dobra ani czy to, że „coś ciągnie w kolanie”, to sygnał do zwolnienia, do zmiany ćwiczenia czy do wizyty u fizjoterapeuty.
- Gorszy nastrój i stres wpływają na trening i regenerację, ale żadna aplikacja treningowa tego nie łączy.
- Nie wie, kiedy samo „odpuszczenie” wystarczy, a kiedy warto zasięgnąć opinii specjalisty i gdzie go znaleźć.
- Nie ma trenera ani planu. Plan z internetu nie bierze pod uwagę jej regeneracji, a pytania („czy mogę dziś trenować nogi, skoro ciągnie mnie kolano?”) zostają bez odpowiedzi.

### 3.2 Rozwiązanie

Aplikacja na iPhone'a, która jest **twoim trenerem, planem treningowym i doradcą w jednym miejscu**:

1. **Daje plan treningowy** dopasowany do celu, poziomu, dni w tygodniu i sprzętu. Plan tworzy AI z naszego katalogu ćwiczeń i jest zapisany w aplikacji.
2. **Ocenia technikę ćwiczenia z filmu** (nagranego lub wybranego z galerii) na podstawie punktów ciała i kątów w stawach. Całe przetwarzanie filmu odbywa się na telefonie, a film nigdy go nie opuszcza.
3. **Zbiera dane o regeneracji** z Apple Health (sen, tętno spoczynkowe, zmienność rytmu serca) i krótki check-in samopoczucia.
4. **Łączy to w jedną rekomendację dnia**: trenuj według planu, zmodyfikuj dzisiejszy trening albo odpuść, z krótkim uzasadnieniem (które czynniki na to wpłynęły). Rekomendacja zmienia dzisiejszą sesję w planie.
5. **Jest doradcą (trener AI w czacie):** można zapytać o plan, ćwiczenie, zamiennik albo o to, czy ćwiczyć dziś. Trener zna twój plan, ostatni wynik techniki, regenerację i samopoczucie.
6. **Pokazuje drogę do opieki:** gdy ten sam problem techniczny albo sygnał powtarza się w kilku analizach, aplikacja podpowiada, że warto rozważyć konsultację ze specjalistą, i pomaga znaleźć fizjoterapeutę w pobliżu.

Hasło robocze: **„Twój trener, plan i doradca. Twoje dane mówią, co masz dziś zrobić.”** **[do ustalenia]**

### 3.3 Dla kogo (osoba docelowa na demo)

„Anna”, 28 lat, ćwiczy 3–4 razy w tygodniu w domu i na siłowni, nosi zegarek, ma za sobą jedną kontuzję kolana, nie ma stałego trenera. Chce ćwiczyć mądrzej i bezpieczniej, ale nie chce być pacjentką. **[do ustalenia]**

### 3.4 Dlaczego to jest inne

Aplikacje do oceny techniki z filmu już istnieją (m.in. Gymscore, CueForm, LiftForm, FitForm, polski TechnikaAI). Zatrzymują się jednak na ocenie ruchu. Nasza przewaga:

- **Trener, plan i doradca w jednym miejscu:** plan zmienia się razem z twoją regeneracją i techniką, a trener AI zna cały ten kontekst.
- **Jedna rekomendacja zamiast kilku pulpitów:** technika + regeneracja + samopoczucie.
- **Ocena jakości nagrania jako pierwszy krok:** aplikacja wymaga właściwego ujęcia i mówi, co poprawić, zanim w ogóle oceni technikę. Dzięki temu wynik jest wiarygodniejszy.
- **Prywatność z założenia:** wideo zostaje na telefonie, w chmurze nie ma żadnych nagrań ani obrazów.
- **Droga do opieki** jako część produktu, a nie tylko diagnoza „coś jest nie tak”.

### 3.5 Czego nie robimy

- **Żadnej diagnozy ani twierdzeń medycznych.** Używamy słów „sygnał”, „warto skonsultować”, „może wskazywać”. W aplikacji jest widoczne zastrzeżenie, że to nie jest porada medyczna.
- **Nie wysyłamy wideo ani obrazów** poza telefon. Do modelu językowego trafiają tylko liczby i podsumowania (w tym dane zdrowotne, **wyłącznie po wyraźnej zgodzie użytkownika**), dane profilu i tekst, który użytkownik sam wpisze w czacie. Informujemy o tym w aplikacji.
- **Trener AI nie diagnozuje i nie zaleca leczenia.** Przy bólu, urazie lub niepokojących objawach odsyła do specjalisty.
- **Nie dodajemy zakresu spoza sekcji 4.** Konta, płatności, analiza wielu ćwiczeń, długoterminowa progresja, Android: to mapa drogowa, nie demo.
- **Nie podajemy danych przykładowych jako prawdziwych.** Każdy ekran z symulowanymi danymi jest wyraźnie oznaczony.

### 3.6 Zasady tonu i treści (obowiązują w całej aplikacji)

| Tak | Nie |
|---|---|
| „Warto rozważyć konsultację z fizjoterapeutą” | „Masz uraz kolana” |
| „Sygnał: kolano ucieka do środka w 3 z 5 powtórzeń” | „Twoje kolano jest uszkodzone” |
| „Dziś lżejszy trening nóg” | „Nie wolno ci ćwiczyć” |
| „Dane przykładowe (symulacja)” | cichy użytek danych wymyślonych jako prawdziwych |

Ton: spokojny, konkretny, wspierający. Bez straszenia i bez moralizowania.

## 4. Zakres demo

### 4.1 W zakresie (musi działać na prawdziwym iPhonie)

1. **Start (onboarding):** krótki profil: cel, poziom, liczba dni w tygodniu, czas sesji, sprzęt, opcjonalnie „czego unikać” (np. ograniczenie kolana).
2. **Plan treningowy:** plan na tydzień (3–4 sesje) wygenerowany przez AI z katalogu ćwiczeń, zapisany w aplikacji. Widok planu i widok dzisiejszej sesji (ćwiczenia, serie, powtórzenia, przerwy), oznaczanie wykonania.
3. **Ekran „Dziś”:** dzisiejsza sesja z planu, sen, tętno spoczynkowe, zmienność rytmu serca, samopoczucie i jedna rekomendacja dnia.
4. **Check-in samopoczucia** (ok. 15 sekund): nastrój, stres, energia w skali 1–5.
5. **Analiza przysiadu:** instrukcja ustawienia telefonu (ujęcie z boku) → nagranie albo film z galerii → **ocena jakości nagrania** → wynik 0–100, 2–3 uwagi, film wzorcowy (link) i jeden zamiennik ćwiczenia.
6. **Rekomendacja dnia** łącząca technikę, regenerację i samopoczucie, z uzasadnieniem. Gdy decyzja to „Zmodyfikuj”, dzisiejsza sesja w planie zmienia się (lżejsze serie, zamiennik).
7. **Trener AI (czat):** pytania o plan, ćwiczenia, zamienniki i to, czy trenować dziś. Odpowiedzi opierają się na profilu, planie, regeneracji i ostatniej analizie.
8. **Opieka:** gdy ten sam problem się powtarza, podpowiedź rozważenia konsultacji i wyszukiwanie fizjoterapeutów w okolicy.
9. **Postępy:** wykres wyników techniki i regeneracji w czasie, historia wykonanych sesji.

### 4.2 Priorytety, gdy zabraknie czasu

Zakres jest duży jak na jeden dzień, więc ustalamy kolejność. Wyższy poziom ma zawsze pierwszeństwo przed niższym.

| Priorytet | Co | Uwaga |
|---|---|---|
| **1. Rdzeń** | Analiza przysiadu z oceną jakości nagrania, regeneracja i check-in, rekomendacja dnia, ekran „Dziś” | Bez tego nie ma produktu |
| **2. Plan** | Onboarding, plan na tydzień, widok dzisiejszej sesji | Gdy generowanie AI zawiedzie, działa plan z gotowego szablonu |
| **3. Trener AI** | Czat z kontekstem użytkownika | Działa przez internet. Przy błędzie połączenia aplikacja pokazuje to wprost i pozwala ponowić |
| **4. Dopełnienie** | Opieka (MapKit), wykres postępów, przyciski „Zastosuj w planie” w czacie | Jeśli zostanie czas |

### 4.3 Poza zakresem (na slajd „Co dalej”)

Analiza wielu ćwiczeń (w demo tylko przysiad), analiza na żywo w trakcie serii, wieloletnia progresja i kalendarz, powiadomienia, tryb trenera dla trenerów, Garmin, konta i płatności, Android.

## 5. Opis ekranów i przepływów

Nawigacja: pasek zakładek **Dziś · Plan · Analiza · Trener · Postępy**. Onboarding pojawia się przy pierwszym uruchomieniu. Check-in i Opieka otwierają się z ekranu Dziś i z wyniku analizy.

### 5.1 Dziś

- **Cel:** odpowiedzieć na pytanie „co dziś zrobić?” w kilka sekund.
- **Zawartość:** karta rekomendacji (decyzja, jedno zdanie uzasadnienia, „dlaczego” po rozwinięciu), dzisiejsza sesja z planu (zmieniona, gdy decyzja to „Zmodyfikuj”), pasek danych (sen, tętno spoczynkowe, HRV, nastrój), przycisk „Zrób check-in”, przycisk „Zapytaj trenera”.
- **Stany:** brak uprawnień do Apple Health (prośba i tryb z danymi przykładowymi), brak danych z dzisiaj (komunikat, co brakuje), brak check-inu.

### 5.2 Check-in

- **Cel:** zebrać samopoczucie w kilka sekund.
- **Zawartość:** trzy suwaki lub przyciski 1–5 (nastrój, stres, energia), opcjonalna krótka notatka. Zapis lokalny.
- **Zasada:** żadnych pytań medycznych i żadnych etykiet typu „depresja”. Tylko skala samopoczucia.

### 5.3 Analiza (przepływ)

1. **Wybór ćwiczenia** (w demo: przysiad).
2. **Instrukcja ujęcia:** schemat ustawienia telefonu (z boku, na wysokości bioder, cała sylwetka w kadrze, 2–3 m od osoby).
3. **Nagranie lub wybór filmu z galerii.**
4. **Ocena jakości nagrania** (patrz 6.2). Jeśli nie przejdzie: konkretna wskazówka i powrót do kroku 3.
5. **Wynik:** liczba 0–100, wykres kąta kolana w czasie z zaznaczonymi powtórzeniami, szkielet nałożony na wybrane klatki, 2–3 uwagi (co poprawić i dlaczego), film wzorcowy, zamiennik ćwiczenia.
6. **Zapis wyniku** (tylko liczby) i przejście do rekomendacji dnia.

### 5.4 Rekomendacja i opieka

- Rekomendacja pokazuje **decyzję**, **powody** (które czynniki, ze źródłem: sen, HRV, check-in, technika) i **jedno działanie** (np. „skróć serię, zamień na przysiad kielichowy”).
- Karta **„Warto rozważyć konsultację”** pojawia się dopiero wtedy, gdy spełnione są warunki z sekcji 7.4. Zawiera krótkie wyjaśnienie bez diagnozy i przycisk „Znajdź fizjoterapeutę w pobliżu” (wyszukiwanie w Mapach).

### 5.5 Postępy

- Wykres wyniku techniki w kolejnych analizach, linia regeneracji i nastroju w czasie. Opis jednym zdaniem, co się zmienia.

### 5.6 Onboarding i profil

- **Cel:** zebrać minimum potrzebne do planu, w około minutę.
- **Pytania:** cel (siła, sylwetka, ogólna kondycja, powrót do ruchu), poziom (początkujący, średni), dni w tygodniu (2–5), czas jednej sesji, sprzęt (brak, hantle, siłownia), opcjonalne „czego unikać”.
- **Zasady:** bez pytań o choroby. Pole „czego unikać” to wolny tekst użytkownika, a aplikacja nie ocenia go medycznie. Przy pierwszym uruchomieniu prosimy też o uprawnienia do Apple Health i wyjaśniamy po co.
- **Wynik:** profil zapisany lokalnie i uruchomienie generowania planu.

### 5.7 Plan

- **Cel:** miejsce, w którym użytkownik ma swój plan i widzi, co jest dziś.
- **Zawartość:** widok tygodnia (dni z sesjami), szczegóły sesji (ćwiczenie, serie, powtórzenia, przerwa, krótki opis i film wzorcowy, jeśli jest), oznaczanie wykonania, przycisk „Zmień plan” (ponowne generowanie z nowymi ustawieniami).
- **Powiązanie z analizą:** przy przysiadzie przycisk „Przeanalizuj technikę”, a po analizie uwagi i zamiennik widoczne przy ćwiczeniu.
- **Powiązanie z rekomendacją:** gdy decyzja dnia to „Zmodyfikuj”, sesja pokazuje zmiany (np. mniej serii, zamiennik) z wyjaśnieniem.
- **Stany:** plan w trakcie generowania, błąd generowania (użyj planu z szablonu i powiedz o tym), brak profilu.

### 5.8 Trener (czat)

- **Cel:** doradca, z którym można porozmawiać o treningu, planie i samopoczuciu.
- **Zawartość:** okno rozmowy, kilka gotowych pytań na start („Czy dziś ćwiczyć nogi?”, „Czym zastąpić przysiad?”, „Jak poprawić technikę?”), informacja, że to nie jest porada medyczna.
- **Dostęp trenera do aplikacji:** stały kontekst (decyzja dnia, profil) plus narzędzia, przez które pyta o plan, regenerację (z Apple Health), check-iny, wyniki analiz i opisy ćwiczeń (patrz 7.6). Użytkownik widzi pod odpowiedzią, z jakich danych trener skorzystał (np. „na podstawie: sen z 7 dni, ostatnia analiza przysiadu”).
- **Zgoda na dane zdrowotne:** ekran zgody przed pierwszą rozmową (patrz 7.6).
- **Zasady odpowiedzi:** patrz 7.6. Przy wzmiance o bólu, urazie lub niepokojących objawach trener nie zgaduje przyczyny, tylko odsyła do specjalisty i pokazuje kartę „Warto rozważyć konsultację”.
- **Stany:** błąd połączenia lub modelu (krótki komunikat i ponowienie), trwa odpowiedź (wskaźnik pisania), pusta rozmowa (gotowe pytania).

### 5.9 Zasady designu

- Jedna główna akcja na ekran.
- Kolor stanu (zielony, żółty, czerwony) nigdy nie jest jedynym nośnikiem informacji: zawsze też tekst lub ikona.
- Obsługa dużych czcionek systemowych (Dynamic Type), kontrast czytelny w jasnym i ciemnym trybie.
- Puste stany i błędy zaprojektowane, a nie domyślne. Każdy komunikat mówi, co zrobić dalej.
- Spójny system: wspólne kolory, typografia, odstępy i komponenty w jednym miejscu.

## 6. Jak działa analiza ruchu

```
Film (nagrany lub z galerii)
  → klatki → punkty ciała (Apple Vision, 19 punktów 2D)
  → ocena jakości nagrania
  → wygładzenie punktów, podział na powtórzenia, kąty
  → wynik 0–100 + lista uwag
```

### 6.1 Wejście

Film z kamery lub z galerii, ujęcie z boku. Klatki czytamy z pliku (`AVAssetReader`), na każdej uruchamiamy detekcję pozy człowieka. Dostajemy współrzędne znormalizowane (0–1) i pewność wykrycia dla stawów: nos, szyja, barki, łokcie, nadgarstki, biodra i środek bioder, kolana, kostki. Nie dostajemy pięt ani palców stóp (ograniczenie 2D i tego narzędzia).

### 6.2 Ocena jakości nagrania (pierwszy krok, nasz wyróżnik)

Nagranie przechodzi dalej tylko wtedy, gdy:

| Warunek | Wartość startowa |
|---|---|
| Cała sylwetka w kadrze (od głowy do kostek) | tak |
| Kluczowe stawy widoczne z pewnością powyżej progu | w ponad 85% klatek |
| Postać zajmuje wysokość kadru | co najmniej 50% |
| Liczba osób w kadrze | dokładnie 1 |
| Liczba powtórzeń | co najmniej 3 |
| Ujęcie zgodne z ćwiczeniem (przysiad: z boku) | tak |
| Klatki na sekundę | co najmniej 24 (30 preferowane) |

Gdy warunek nie jest spełniony, aplikacja podaje **konkretną wskazówkę**: „Odejdź krok do tyłu, nie widzę stóp”, „Ustaw się bokiem do kamery”, „Zrób co najmniej 3 powtórzenia”. Wartości progowe są startowe i do strojenia.

### 6.3 Przetwarzanie

1. **Wygładzenie** współrzędnych (np. filtr One Euro albo średnia ruchoma) i odrzucenie klatek o niskiej pewności.
2. **Podział na powtórzenia** na podstawie ruchu bioder w pionie (szczyty i doliny).
3. **Obliczenie kątów** w każdej klatce: kąt kolana, kąt biodra, pochylenie tułowia względem pionu i względem piszczeli.
4. **Metryki powtórzenia:** głębokość (minimalny kąt kolana i biodro względem kolana), pochylenie tułowia w najniższym punkcie, czas opadania i wstawania, powtarzalność między powtórzeniami.

### 6.4 Wynik 0–100

Wynik to ważona suma ocen składowych. Wagi i progi trzymamy w **jednym pliku konfiguracyjnym JSON**, żeby można je szybko stroić.

| Składowa | Waga startowa | Co mierzy |
|---|---|---|
| Głębokość | 35% | czy biodro schodzi odpowiednio nisko względem kolana |
| Tułów | 30% | czy pochylenie tułowia jest w sensownym zakresie i jest proporcjonalne do ruchu piszczeli |
| Powtarzalność | 20% | czy kolejne powtórzenia są do siebie podobne |
| Kontrola tempa | 15% | czy opadanie nie jest gwałtowne |

Wagi i progi to **wartości inżynierskie na demo**, nie normy medyczne ani sportowe. Nie przedstawiamy ich jako zalecenia fizjoterapeuty.

### 6.5 Uwagi

Każda uwaga to struktura: identyfikator problemu (np. `torso_lean_high`), nasilenie, liczba powtórzeń, w których wystąpił, i krótki tekst. Tekst formułuje szablon albo model językowy (patrz 7.5).

### 6.6 Zamiennik ćwiczenia

Przy niskim wyniku w danej składowej aplikacja proponuje zamiennik z krótkiej, ręcznie przygotowanej tabeli (np. głębokość lub tułów → przysiad kielichowy, przysiad do pudła). Do każdego zamiennika: krótki opis i link do filmu wzorcowego. **Źródło filmów wzorcowych [do ustalenia]**: najlepiej własne nagranie albo materiał z jasną licencją, a nie film z internetu użyty bez zgody.

## 7. Jak powstaje rekomendacja, plan i odpowiedzi trenera

### 7.1 Dane wejściowe

| Źródło | Co bierzemy |
|---|---|
| Apple Health (HealthKit) | czas snu, tętno spoczynkowe, zmienność rytmu serca (HRV, SDNN) i ich punkt odniesienia z ostatnich dni |
| Check-in | nastrój, stres, energia (1–5) |
| Analiza techniki | ostatni wynik, lista uwag, historia uwag |

Gdy telefon nie ma wystarczających danych, aplikacja używa **zestawu danych przykładowych** (profil „Anna”, ok. 14 dni) wyraźnie oznaczonego jako symulacja.

### 7.2 Silnik reguł

Rekomendację liczy **silnik reguł w Swifcie**, a nie model językowy. Zwraca on strukturę: decyzja, lista czynników, sugerowane działanie, opcjonalna flaga opieki. Dzięki temu wynik jest deterministyczny, testowalny i bezpieczny.

Decyzje:

| Decyzja | Znaczenie |
|---|---|
| **Trenuj** | dane regeneracji i samopoczucie bez niepokojących sygnałów |
| **Zmodyfikuj** | pojedyncze sygnały (np. krótki sen, podwyższony stres, uwagi o technice): lżejszy trening, krótsze serie, zamiennik ćwiczenia |
| **Odpuść / regeneracja** | kilka sygnałów naraz: dzień odpoczynku albo lekka aktywność |

Decyzja dotyczy **dzisiejszej sesji z planu**. „Zmodyfikuj” zmienia ją według prostych reguł (mniej serii, niższa intensywność, zamiennik ćwiczenia z katalogu), „Odpuść” zamienia sesję na odpoczynek albo lekką aktywność. Zmiana jest zapisana w planie i wyjaśniona użytkownikowi.

### 7.3 Przykładowe reguły startowe (do strojenia)

| Czynnik | Przykładowy próg | Wpływ |
|---|---|---|
| Sen | poniżej 6 godzin | w stronę „Zmodyfikuj” |
| HRV | wyraźnie poniżej własnego punktu odniesienia z ostatnich dni | w stronę „Zmodyfikuj” |
| Tętno spoczynkowe | wyraźnie powyżej własnego punktu odniesienia | w stronę „Zmodyfikuj” |
| Check-in | stres 4–5 lub energia 1–2 | w stronę „Zmodyfikuj” |
| Technika | wynik poniżej 60 lub ta sama uwaga w większości powtórzeń | uwaga w rekomendacji i zamiennik |
| Kilka czynników naraz | co najmniej 3 sygnały | „Odpuść / regeneracja” |

To są **progi inżynierskie na potrzeby demo**, a nie wartości kliniczne. Nie przedstawiamy ich jako zaleceń medycznych.

### 7.4 Kiedy pojawia się „Warto rozważyć konsultację”

Tylko gdy spełniony jest któryś z warunków:

- ta sama uwaga o technice (np. niestabilność kolana) powtarza się w co najmniej 3 analizach w ciągu 14 dni,
- użytkownik w check-inie lub notatce sam zaznaczy ból albo dyskomfort w czasie ćwiczenia,
- utrzymują się przez kilka dni jednocześnie niepokojące wskaźniki regeneracji i niskie samopoczucie.

Aplikacja nie mówi, co jest przyczyną, tylko że **warto porozmawiać ze specjalistą**, i oferuje wyszukanie fizjoterapeuty w okolicy. W przypadku silnego bólu, urazu lub niepokojących objawów zawsze obowiązuje komunikat, by skontaktować się z lekarzem.

### 7.5 Rola modelu językowego w rekomendacji dnia

Model (Claude Haiku 4.5) dostaje **gotową strukturę** z silnika reguł (decyzja, czynniki, uwagi) i tylko **formułuje tekst** po polsku w naszym tonie (sekcja 3.6). Nie wybiera decyzji, nie dodaje nowych zaleceń ani nie widzi żadnego obrazu. Tekst jest sprawdzany pod kątem zakazanych sformułowań. Gdy wywołanie modelu się nie powiedzie (błąd API, limit, słabe łącze), ten sam wynik opisują **gotowe szablony tekstu**, więc rekomendacja dnia zawsze się wyświetla.

### 7.6 Plan treningowy i trener AI

**Katalog ćwiczeń.** Mała, ręcznie przygotowana lista (ok. 12–15 ćwiczeń, np. przysiad, przysiad kielichowy, przysiad do pudła, martwy ciąg rumuński, wykrok, mostek biodrowy, pompka, wiosłowanie z hantlem, wyciskanie nad głowę, plank). Każde ćwiczenie ma stałe `id`, nazwę, grupę mięśni, wymagany sprzęt, poziom, krótki opis i opcjonalnie link do filmu wzorcowego. **Plan i trener używają wyłącznie ćwiczeń z tego katalogu.**

**Generowanie planu.**
1. Wejście: profil z onboardingu (cel, poziom, dni, czas sesji, sprzęt, „czego unikać”).
2. Model (Claude Sonnet 5) zwraca plan jako **ustrukturyzowany JSON**: tydzień, sesje, ćwiczenia (tylko `id` z katalogu), serie, zakresy powtórzeń, przerwy.
3. Nasz kod **waliduje** wynik: czy `id` istnieją, czy ćwiczenia pasują do sprzętu, czy liczba ćwiczeń i serii mieści się w limitach, czy uwzględniono „czego unikać”. Niepoprawny plan jest odrzucany.
4. Gdy generowanie lub walidacja zawiedzie (błąd API, niepoprawny wynik): **plan z gotowego szablonu** dobranego do celu, poziomu i dni.

**Trener AI (czat).** Czat działa wewnątrz aplikacji i jest podłączony do **gotowego modelu językowego przez API** (domyślnie Claude, wybór modelu w sekcji 8). Nie trenujemy własnego modelu. Trener ma **dostęp do zawartości aplikacji i danych zdrowotnych użytkownika**, a odbywa się to na dwa sposoby:

1. **Stały kontekst w każdej rozmowie** (mały, budowany przez aplikację):
   - **instrukcja systemowa** z naszymi zasadami tonu i bezpieczeństwa (sekcja 3.6) i informacją, że trener nie jest lekarzem,
   - **dzisiejsza decyzja z silnika reguł** wraz z czynnikami (żeby trener nigdy jej nie ominął),
   - krótki **profil** (cel, poziom, sprzęt, „czego unikać”),
   - historia bieżącej rozmowy.
2. **Narzędzia wywoływane przez model** (function calling). Gdy trener potrzebuje danych, prosi o nie, a aplikacja wykonuje zapytanie **lokalnie na telefonie** i zwraca wynik. Dzięki temu do modelu trafia tylko to, o co zapytał, a nie cała baza.

| Narzędzie | Co zwraca |
|---|---|
| `get_training_plan` | plan tygodnia albo dzisiejsza sesja (ćwiczenia, serie, powtórzenia, status) |
| `get_recovery_history` | sen, tętno spoczynkowe i HRV z ostatnich N dni jako **podsumowania** (średnie, odchylenie od punktu odniesienia), nie surowe próbki z Apple Health |
| `get_checkins` | nastrój, stres, energia z ostatnich N dni |
| `get_technique_results` | ostatnie analizy: wynik, uwagi, trend |
| `get_exercise_info` | opis ćwiczenia, zamienniki, link do filmu wzorcowego z katalogu |
| `propose_plan_change` (priorytet 4) | **propozycja** zmiany sesji (np. zamiennik). Zmiana wchodzi do planu dopiero po kliknięciu przez użytkownika „Zastosuj” |

Narzędzia tylko **czytają** dane. Model nie ma narzędzia, które samo zmieniłoby plan lub dane.

Zasady odpowiedzi trenera:
- Decyzję dnia podaje **silnik reguł**, a trener ją tylko wyjaśnia. Trener nie zmienia decyzji ani nie pomija sygnałów, które wykrył silnik.
- Proponuje zamienniki i modyfikacje **wyłącznie z katalogu**.
- Nie diagnozuje i nie zaleca leczenia. Przy bólu, urazie lub niepokojących objawach odsyła do specjalisty.
- Mówi, czego nie wie. Nie zmyśla danych, których nie dostał w kontekście.
- Odpowiada po polsku, krótko, w naszym tonie.

**Prywatność czatu i dane zdrowotne.** Do modelu trafiają: stały kontekst, wyniki wywołanych narzędzi (podsumowania, nie surowe dane z Apple Health), dane profilu i tekst, który użytkownik sam wpisze. **Wideo i obrazy nigdy.** Dane zdrowotne są szczególnie wrażliwe, więc:
- przed pierwszą rozmową aplikacja prosi o **wyraźną zgodę** na przekazanie modelowi danych zdrowotnych i opisuje, co dokładnie trafia do usługi zewnętrznej, a użytkownik może ją wycofać (wtedy czat działa bez danych zdrowotnych),
- przekazujemy **minimum**: podsumowania zamiast surowych próbek,
- dane zdrowotne z Apple Health nie służą do reklam ani do niczego poza funkcją trenera (wymóg zasad Apple dotyczących HealthKit),
- przed wdrożeniem poza demo sprawdzamy warunki przetwarzania danych u dostawcy modelu oraz wymogi RODO dla danych o zdrowiu,
- informujemy o tym w aplikacji i w prezentacji.

Historię rozmowy trzymamy lokalnie na telefonie. W demo trener pracuje na danych przykładowych (oznaczonych jako symulowane), a na prawdziwych danych z Apple Health tylko po zgodzie właściciela telefonu.

**Połączenie z internetem.** Aplikacja jest zaprojektowana do pracy z internetem: plan, czat i teksty rekomendacji korzystają z modelu przez sieć. Gdy połączenie lub model zawiedzie, aplikacja mówi to wprost, pozwala ponowić i, tam gdzie to możliwe (plan, rekomendacja dnia), pokazuje wersję z szablonu. Analiza filmu działa na telefonie z wyboru (prywatność), ale to nie jest tryb offline jako cecha produktu.

## 8. Technologia i organizacja repozytorium

| Warstwa | Wybór | Uwagi |
|---|---|---|
| Aplikacja | **Swift + SwiftUI**, cel wdrożenia **iOS 17** | Zgodność z Xcode 26 (część zespołu nie ma 27). Nie używamy API dostępnych dopiero w nowszych wersjach iOS bez sprawdzenia dostępności |
| Punkty ciała | **Apple Vision**, `VNDetectHumanBodyPoseRequest` | Wbudowane w system, 19 punktów 2D, bez pięt i palców stóp, bez zależności zewnętrznych |
| Wideo | AVFoundation (nagrywanie i `AVAssetReader`), `PhotosPicker` do wyboru filmu | Kamera działa tylko na prawdziwym telefonie |
| Dane o zdrowiu | **HealthKit** (sen, tętno spoczynkowe, HRV) | Na symulatorze zwykle brak danych, stąd zestaw przykładowy |
| Rekomendacje | Silnik reguł w Swifcie, tekst: Claude Haiku 4.5 lub szablony | Patrz sekcje 7.1–7.5 |
| Plan i trener AI | Gotowy model przez API (Claude). Plan: Sonnet 5 (JSON z walidacją, szablon jako zapas). Czat: Haiku 4.5 (szybszy i tańszy) lub Sonnet 5 (lepszy przy użyciu narzędzi) **[do ustalenia po próbie]**, z narzędziami i streamingiem odpowiedzi | Patrz sekcja 7.6. Wywołania przez `URLSession` (HTTP), bo na liście SDK, które znamy, nie ma Swifta **[do sprawdzenia]**. Serwer pośredniczący opcjonalnie |
| Opieka | MapKit (`MKLocalSearch`) | Wyszukiwanie fizjoterapeutów w pobliżu |
| Wykresy | Swift Charts | |
| Zapis lokalny | SwiftData lub prosty plik JSON | Profil, plan, historia sesji, wyniki, rozmowy z trenerem. Nigdy wideo |

### 8.1 Klucz do modelu językowego

Klucza API nie wolno commitować ani wkompilować w kod w repo. Na demo trzymamy go w pliku `Secrets.xcconfig` poza repozytorium (wpis w `.gitignore`). W prezentacji mówimy uczciwie, że docelowo wywołania pójdą przez nasz serwer pośredniczący. Jeśli zostanie czas, dodajemy małą funkcję serwerową, która ukrywa klucz.

### 8.2 Organizacja repozytorium (ważne przy różnych wersjach Xcode)

- **Projekt Xcode zakłada osoba z Xcode 26.** Projekt zapisany w Xcode 27 może się nie otwierać w 26. Kto ma 27, nie zgadza się na „upgrade project format”.
- **Prawie cały kod trafia do lokalnego pakietu Swift** (`Packages/Core`), a sam plik projektu (`.pbxproj`) zmieniamy rzadko. Mniej konfliktów przy scalaniu i mniejsza zależność od wersji Xcode.
- Kontrakty (wspólne typy danych) mają jeden moduł, który zmienia się tylko za zgodą zespołu.
- Małe commity na `main` albo krótkie gałęzie funkcji, częste scalanie. Nie edytujemy równocześnie tych samych plików.
- `README.md` dla jury (jak uruchomić, co robi, zrzuty ekranu) powstaje w trakcie pracy.
- `.gitignore` ma `Secrets.xcconfig`, dane użytkownika i pliki wideo.

## 9. Architektura i kontrakty między modułami

Zasada: na początku uzgadniamy **kontrakty** i każdy buduje swój moduł na danych przykładowych, bez czekania na resztę.

```
Video / kamera
  → VisionPoseExtractor      (klatki → punkty ciała)
  → QualityGate              (ujęcie, kadr, widoczność, liczba powtórzeń)
  → RepAnalyzer              (wygładzanie, powtórzenia, kąty)
  → TechniqueScorer          (wynik 0–100 + uwagi)
        ↘
HealthKitService  (sen, HRV, tętno)  ─→  InsightEngine ─→ DailyRecommendation
CheckIn           (nastrój, stres)   ─↗         │               │
                                                 │               └─ PlanAdjuster (zmiana dzisiejszej sesji)
                                                 ├─ CarePathway (flaga „warto rozważyć konsultację”)
                                                 └─ CoachTextGenerator (Claude lub szablony)

UserProfile ─→ PlanGenerator (Claude → JSON → walidacja, zapas: szablon) ─→ TrainingPlan
ExerciseCatalog ───────────────────────────────────────────────────────────↗   │
                                                                              ▼
CoachContextBuilder (profil + plan + regeneracja + analiza + decyzja) ─→ CoachChat (Claude)
```

### 9.1 Kontrakty (pola do uzgodnienia na starcie)

| Typ | Najważniejsze pola |
|---|---|
| `PoseFrame` | czas, lista stawów (nazwa, x, y, pewność) |
| `QualityReport` | zaliczone/niezaliczone, lista warunków z wynikiem, wskazówka dla użytkownika |
| `RepMetrics` | indeks powtórzenia, minimalny kąt kolana, pochylenie tułowia, czas opadania i wstawania |
| `TechniqueResult` | wynik 0–100, wyniki składowych, lista uwag (id, nasilenie, liczba powtórzeń), zamiennik |
| `RecoverySnapshot` | data, sen, tętno spoczynkowe, HRV, punkt odniesienia, czy dane są symulowane |
| `CheckIn` | data, nastrój, stres, energia, notatka |
| `DailyRecommendation` | decyzja, lista czynników (źródło, opis), sugerowane działanie, flaga opieki, tekst |
| `UserProfile` | cel, poziom, dni w tygodniu, czas sesji, sprzęt, „czego unikać” (tekst) |
| `ExerciseItem` | `id`, nazwa, grupa mięśni, sprzęt, poziom, opis, link do filmu wzorcowego, lista `id` zamienników |
| `TrainingPlan` | tydzień → sesje (dzień, lista pozycji: `id` ćwiczenia, serie, zakres powtórzeń, przerwa), źródło (AI lub szablon) |
| `PlannedSession` | data, pozycje, status (zaplanowana, wykonana, zmieniona), powód zmiany |
| `ChatMessage` | rola (użytkownik lub trener), tekst, czas |
| `CoachContext` | stały kontekst rozmowy: krótki profil, dzisiejsza `DailyRecommendation` z czynnikami |
| `CoachTool` | nazwa, opis i schemat parametrów narzędzia (np. `get_recovery_history(days)`), funkcja wykonywana lokalnie, wynik jako podsumowanie. Lista narzędzi w 7.6 |
| `DataConsent` | zgoda na przekazanie danych zdrowotnych modelowi (tak/nie, data), możliwość wycofania |

Reguła: moduł, który zmienia kontrakt, informuje zespół i aktualizuje ten opis.

## 10. Plan działania

Bez rozpisywania na godziny. Kolejność jest ważniejsza niż zegar: przechodzimy do następnego kroku, gdy spełniony jest warunek ukończenia.

### Krok 0: Przygotowanie (przed startem, tylko środowisko)

- Każdy ma działający Xcode, iPhone w trybie dewelopera i zaufany komputerowi.
- Konta: Apple ID do podpisywania, dostęp do HackTribe i Discorda HackYeah, klucz do Claude API (jedna osoba).
- Sprawdzenie na **pustej aplikacji testowej poza projektem**, że instalacja na iPhonie i uprawnienia HealthKit działają.
- Potwierdzenie z organizatorami, że wcześniejsze planowanie jest w porządku.

**Gotowe, gdy:** każdy może zbudować pustą aplikację na telefon. **Kodu projektu nie piszemy.**

### Krok 1: Start i fundament

- Decyzje: nazwa aplikacji i zespołu, podział ról, zakres (sekcja 4).
- Osoba z Xcode 26 zakłada projekt i lokalny pakiet `Core`, wszyscy sprawdzają, że się otwiera i buduje.
- Uzgodnienie kontraktów (sekcja 9) i wspólnych elementów designu (kolory, typografia, komponenty).
- Nagranie kilku testowych przysiadów (z boku, w różnych warunkach).

**Gotowe, gdy:** pusty projekt buduje się u wszystkich i kontrakty są spisane.

### Krok 2: Moduły równolegle

Każdy moduł powstaje na danych przykładowych, w swoim obszarze.

| Moduł | Warunek ukończenia |
|---|---|
| Szkielet i UI | nawigacja (Dziś, Plan, Analiza, Trener, Postępy) i ekran „Dziś” z danymi przykładowymi |
| Analiza ruchu | z testowego filmu wychodzi wynik, uwagi i ocena jakości nagrania |
| Dane i silnik wniosków | z danych przykładowych i check-inu wychodzi rekomendacja z uzasadnieniem, a „Zmodyfikuj” zmienia sesję |
| Katalog i plan | katalog ćwiczeń, plan z szablonu oraz plan z AI z walidacją, widok planu i dzisiejszej sesji |
| Trener AI i teksty | czat z kontekstem i zasadami z 7.6, szablony tekstów jako wersja zapasowa przy błędzie API, prompt do modelu zwraca poprawny tekst |
| Design i prezentacja | makiety głównych ekranów i szkielet slajdów |

### Krok 3: Integracja

Łączymy moduły: onboarding → plan → analiza → wynik → rekomendacja (zmiana sesji w planie) → trener AI z kontekstem. Na prawdziwym iPhonie przechodzimy cały przepływ.

**Gotowe, gdy:** jeden pełny przepływ działa od początku do końca na telefonie. Jeśli czas się kurczy, pilnujemy priorytetów z sekcji 4.2 (rdzeń, potem plan, potem trener).

### Krok 4: Dopracowanie i zamrożenie funkcji

- Strojenie progów na nagraniach testowych.
- Design: spójność, animacje, puste stany, błędy.
- Ścieżka do opieki, wykres postępów, obsługa braku danych oraz błędów połączenia i modelu.
- **Zamrożenie funkcji**, gdy przepływ działa stabilnie. Od tej chwili tylko poprawki błędów.

**Gotowe, gdy:** aplikacja nie wywala się na pustych danych ani przy błędzie połączenia lub modelu.

### Krok 5: Materiały i zgłoszenie

- Nagranie demo (zapasowe na wypadek awarii na żywo), zrzuty ekranu, PDF z maks. 10 slajdami, README, opis projektu.
- **Wczesny szkic zgłoszenia na HackTribe**, żeby sprawdzić platformę, zanim zrobi się późno.
- Test od zera na czystym telefonie i próba pitchu.
- **Wysłanie zgłoszenia z wyraźnym zapasem przed terminem.**

**Gotowe, gdy:** zgłoszenie jest widoczne i kompletne na HackTribe.

### Krok 6: Po terminie

Niczego nie zmieniamy. Zmiany po terminie są nielegalne i jury ich nie uwzględnia.

## 11. Role i zasady pracy (zespół i agenci AI)

### 11.1 Role

Zespół do 6 osób, role można łączyć.

| Rola | Zadania | Własność w repo |
|---|---|---|
| **A. Szkielet i UI** | projekt Xcode, nawigacja, system wizualny, ekran „Dziś” | aplikacja, `DesignSystem` |
| **B. Analiza ruchu** | Vision, ocena jakości nagrania, powtórzenia, kąty, wynik | `Analysis` |
| **C. Dane i silnik wniosków** | HealthKit, dane przykładowe, check-in, silnik reguł, ścieżka do opieki | `Health`, `Insights` |
| **D. Plan i trener AI** | katalog ćwiczeń, generowanie i walidacja planu, szablony planów, czat z kontekstem, prompty, szablony tekstów, zastrzeżenia | `Plan`, `Coaching`, `Content` |
| **E. Design i prezentacja** | makiety, ikony, slajdy, grafiki do HackTribe | materiały poza kodem |
| **F. Demo i jakość** | nagrania testowe, testy na telefonie, nagranie demo, README, zgłoszenie | `README`, materiały |

Rola D jest najbardziej obciążona (plan i czat), więc przy mniejszym zespole łączymy raczej E z F oraz A z częścią C, a nie dokładamy D innych zadań. Zakres tej roli można podzielić na dwie osoby: katalog i plan oraz czat.

### 11.2 Zasady dla wszystkich (ludzie i agenci AI)

1. **Przeczytaj ten dokument w całości**, zanim zaczniesz pracę.
2. **Nie pisz kodu przed 23:00 3.10.** Agent uruchomiony wcześniej ma wyłącznie rozmawiać i planować.
3. **Trzymaj się zakresu z sekcji 4.** Pomysły spoza zakresu zapisz w sekcji 14, nie implementuj.
4. **Pracuj w swoim module.** Zmiana kontraktu (sekcja 9) lub cudzego modułu wymaga uzgodnienia z zespołem.
5. **Nie commituj kluczy ani danych osobowych.** Klucz API tylko w `Secrets.xcconfig` poza repo.
6. **Nie wysyłaj wideo ani obrazów poza telefon.** Do sieci wychodzą tylko liczby i podsumowania, dane profilu i tekst, który użytkownik sam wpisał w czacie. Dane zdrowotne trafiają do modelu wyłącznie po wyraźnej zgodzie użytkownika i tylko jako podsumowania.
   Plan i trener używają wyłącznie ćwiczeń z katalogu i zawsze przechodzą walidację.
7. **Teksty zdrowotne zgodnie z sekcją 3.6:** sygnał, nie diagnoza. Każdy nowy tekst przechodzi tę kontrolę.
8. **Zgodność z Xcode 26 i iOS 17.** Nowsze API tylko z `#available` i alternatywą.
9. **Nie zmieniaj pliku `.pbxproj`, jeśli nie musisz.** Nowe pliki trafiają do pakietu `Core`.
10. **Dane przykładowe zawsze oznaczone** jako symulowane w interfejsie.
11. **Definicja ukończenia modułu:** buduje się, działa na danych przykładowych i na pustych danych, ma podgląd lub przykład użycia, a logika oceny i silnik reguł mają testy.
12. **Małe commity z opisem**, scalanie często, bez edycji tych samych plików równocześnie.
13. **Język:** interfejs po polsku, identyfikatory i komentarze w kodzie po angielsku, dokumentacja po polsku.
14. **Uczciwość w demo i na slajdach:** pokazujemy to, co faktycznie działa, i mówimy, co jest symulowane albo planowane.

## 12. Prezentacja, demo i pitch

### 12.1 Slajdy (PDF, maks. 10)

| # | Slajd | Po co (kryterium) |
|---|---|---|
| 1 | Tytuł, nazwa zespołu, hasło | Pierwsze wrażenie |
| 2 | Problem: dane są rozproszone, nikt nie mówi, co z nimi zrobić | Związek z kategorią |
| 3 | Rozwiązanie w jednym zdaniu („trener, plan i doradca w jednym”) i zrzut ekranu „Dziś” | Pomysł |
| 4 | Jak to działa: nagranie → punkty ciała → kąty → wynik (film zostaje na telefonie) | Innowacyjność, prywatność |
| 5 | Łączymy sport, zdrowie fizyczne, dobrostan psychiczny i dostęp do opieki | Związek z kategorią |
| 6 | Ekran: analiza i ocena jakości nagrania | Design, kompletność |
| 7 | Ekrany: plan treningowy, rekomendacja dnia i trener AI | Praktyczne zastosowanie |
| 8 | Prywatność i bezpieczeństwo (film na urządzeniu, co trafia do modelu, brak diagnoz, ścieżka do specjalisty, zastrzeżenie) | Wiarygodność |
| 9 | Stan prac i co dalej (kolejne ćwiczenia, plany, Android, Garmin, tryb trenera) | Kompletność |
| 10 | Zespół oraz link do repo i demo | Zamknięcie |

Język slajdów i opisu: polski lub angielski **[do ustalenia]**.

### 12.2 Pitch na żywo (3 minuty, faza 2)

1. **15 s:** problem w jednym zdaniu i pytanie do sali.
2. **90 s:** demo na telefonie: plan na dziś → analiza przysiadu z oceną jakości nagrania → rekomendacja dnia zmienia sesję → jedno pytanie do trenera AI. Zapasowe nagranie gotowe na wypadek awarii.
3. **30 s:** dlaczego to działa (na urządzeniu, jakość nagrania, połączenie danych).
4. **30 s:** co dalej i dlaczego to się skaluje.
5. **15 s:** podziękowanie i pytania.

## 13. Ryzyka

| Ryzyko | Środek zaradczy |
|---|---|
| Wynik z Vision jest zaszumiony | Wygładzanie, filtrowanie klatek o niskiej pewności, jedno ćwiczenie i jedno ujęcie |
| Brak danych w HealthKit na telefonie | Tryb z danymi przykładowymi, wyraźnie oznaczony jako symulowany |
| Słabe łącze (np. na hali hackathonu), błąd lub limit modelu językowego | Szablony tekstu dla rekomendacji i plan z szablonu jako wersja zapasowa, komunikat z ponowieniem w czacie, hotspot z telefonu jako zapas łącza |
| Projekt Xcode nie otwiera się u części zespołu | Projekt zakłada osoba z Xcode 26, pakiet Swift na większość kodu, sprawdzenie u wszystkich zaraz po założeniu |
| Podpisywanie aplikacji (darmowe konto Apple ID) i uprawnienia HealthKit | Sprawdzić w kroku 0 na pustej aplikacji testowej poza projektem |
| Awaria demo na żywo | Nagranie demo i zrzuty ekranu |
| Konflikty w repo | Małe commity, podział modułów, pakiet Swift |
| Brak czasu | Zamrożenie funkcji, gdy przepływ działa, i zgłoszenie z zapasem przed terminem |
| Stwierdzenia medyczne w treści | Każdy tekst sprawdzany pod kątem „sygnał, nie diagnoza” (sekcja 3.6) |
| Spór o czas rozpoczęcia pracy | Potwierdzić z organizatorami przed startem. Nie commitować kodu przed 23:00 |
| Film wzorcowy z internetu bez licencji | Własne nagranie albo materiał z jasną licencją |
| Zakres jest duży jak na jeden dzień (plan, czat, analiza, dane) | Priorytety z sekcji 4.2, plan z szablonu jako zapas, czat jako element, który można ograniczyć |
| Model wygeneruje niepoprawny plan albo wymyśli ćwiczenie | Katalog jako jedyne źródło `id`, walidacja kodem, plan z szablonu przy błędzie |
| Trener AI da radę medyczną, zmyśli dane albo zbagatelizuje ból | Instrukcja systemowa, kontekst z silnika reguł, odsyłanie do specjalisty przy bólu i urazie, kontrola odpowiedzi na kilku testowych pytaniach przed demo |
| Opóźnienie lub błąd API podczas demo | Krótkie odpowiedzi (Haiku), komunikat o błędzie z ponowieniem, nagranie demo jako zapas |
| Czat wysyła dane użytkownika, w tym zdrowotne, do zewnętrznego modelu | Wyraźna zgoda przed pierwszą rozmową z możliwością wycofania, minimum danych (podsumowania, narzędzia zamiast całej bazy), brak wideo i obrazów, jasna informacja w aplikacji i na slajdzie. Przed wdrożeniem poza demo: warunki dostawcy i RODO |
| Trener błędnie użyje narzędzi lub pominie dane | Krótki zestaw narzędzi z jasnymi opisami, narzędzia tylko do odczytu, testy na kilku typowych pytaniach przed demo |

## 14. Dalsza wizja (po hackathonie)

- Więcej ćwiczeń (martwy ciąg rumuński, pompka, wykrok) i wymagane ujęcia (przód i bok), z biblioteką ok. 40 ćwiczeń, filmami wzorcowymi i grafem zamienników.
- Plany wielotygodniowe z progresją, kalendarzem, powiadomieniami i adaptacją na podstawie historii treningów, regeneracji i techniki.
- Trener AI zmieniający plan na życzenie użytkownika (z zatwierdzeniem), pamiętający cele i historię rozmów.
- Serwer pośredniczący dla modelu językowego (ukrycie klucza, limity, logowanie).
- Dokładniejsze punkty ciała (MediaPipe, 33 punkty z piętami i stopami) oraz progi ocen strojone z trenerem lub fizjoterapeutą na nagraniach testowych.
- Dane z zegarków: Apple Health na start, później Garmin (bezpośrednie API Garmina jest od wiosny 2026 zamknięte dla nowych wniosków, więc dopiero po wznowieniu programu albo przez pośrednika).
- Analiza na żywo w trakcie serii, tryb trenera (podopieczny wysyła wyniki, nie filmy), Android.
- Konta, subskrypcje i serwer pośredniczący dla modelu językowego.

## 15. Otwarte decyzje

- [ ] Liczba osób i przydział ról (sekcja 11).
- [ ] Nazwa aplikacji, hasło i nazwa zespołu.
- [ ] Potwierdzenie z organizatorami, że wcześniejsze planowanie jest w porządku.
- [ ] Kto z zespołu ma Xcode 26 i założy projekt.
- [ ] Wersje iOS i modele iPhone'ów w zespole (czy cel iOS 17 wystarcza).
- [ ] Czy zostajemy przy przysiadzie jako jedynym analizowanym ćwiczeniu.
- [ ] Które ćwiczenia wchodzą do katalogu (ok. 12–15) i kto go przygotowuje.
- [ ] Czy czat trenera ma tylko odpowiadać, czy też proponować zmiany w planie z przyciskiem „Zastosuj” (priorytet 4).
- [ ] Czy wywołania modelu idą bezpośrednio z aplikacji (klucz w `Secrets.xcconfig`), czy przez serwer pośredniczący. Przy danych zdrowotnych serwer jest bezpieczniejszy, ale kosztuje czas.
- [ ] Który model w czacie (Haiku 4.5 czy Sonnet 5) po próbie szybkości i jakości.
- [ ] Czy w demo trener pracuje na danych przykładowych, na prawdziwych danych z telefonu, czy na obu (przełącznik).
- [ ] Źródło filmów wzorcowych i danych przykładowych (kto się nagrywa, za zgodą).
- [ ] Klucz do Claude API: kto go zakłada i gdzie przechowujemy.
- [ ] Język slajdów i opisu: polski czy angielski.
