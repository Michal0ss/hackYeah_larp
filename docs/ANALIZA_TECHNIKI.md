# Analiza techniki: kąty, zakresy ruchu i model

Ten dokument opisuje, **jak liczymy kąty stawów z filmu**, **skąd są zakresy, którymi je oceniamy**, **jak bardzo im ufać** i **jaki gotowy model warto rozważyć dalej**. Kod: `Packages/Core/Sources/Analysis` (film), `Packages/Core/Sources/LiveSet/Tempo` (kąty, oceniacze, zakresy), konfiguracja: `content/config/scoring.json` (sekcje `angles`, `clip`, `quality`).

> **Stan sprawdzenia.** Logika jest sprawdzona na **syntetycznych pozach o znanych kątach** (przysiad, pompka, podciąganie, pion i poziom, 30 i 60 kl./s, braki stawów, zakłócenia): zmierzone kąty zgadzają się z prawdziwymi co do 1–2°. **Nie jest jeszcze sprawdzona na prawdziwym nagraniu człowieka**, a Apple Vision ma własny błąd. Zakresy poniżej są wartościami startowymi do strojenia na nagraniach (sekcja „Jak to skalibrować”).

## 1. Co było źle (dlaczego analiza z filmu „nie działała”)

1. **Kąty liczone na zniekształconych współrzędnych.** Vision zwraca staw jako ułamek szerokości (x) i wysokości (y) obrazu. Film z telefonu w pionie to 9:16, więc jednostka x jest ok. 1,8× krótsza niż y. Kąt kolana prawdziwego przysiadu równoległego (56°) wychodził jako 45°, pochylenie tułowia 42° jako 57° (poprawny przysiad dostawał „za duże pochylenie” w każdym powtórzeniu), a łokieć w poprawnej pompce nagranej poziomo 88° jako 116° („za płytko”). Teraz każda klatka niesie `aspect` (szerokość / wysokość obrazu), a wszystkie kąty i długości liczy `PoseGeometry` na współrzędnych w jednostkach wysokości obrazu.
2. **Liczenie powtórzeń jak na żywo.** Na żywo trener potrzebuje sekundy bezruchu na kalibrację i reaguje z opóźnieniem. Film, który zaczyna się od razu ruchem, albo ma ruch przed ćwiczeniem, nie kalibrował się wcale i dostawał 0 powtórzeń. Teraz `ClipRepDetector` patrzy na cały film naraz: nie potrzebuje kalibracji, bierze pozycję startową z samego nagrania i liczy powtórzenia po wyraźnych, szerokich szczytach wygładzonego sygnału.
3. **Zbyt ostra ocena jakości.** Próg pewności stawu 0,3 odrzucał kadry, w których Vision jest „w połowie pewny” kostek. Ocena kadrowała cały film, także dojście do telefonu. Teraz próg pewności dla filmu to 0,15, kadrowanie liczy tylko fragment z ćwiczeniem, a każda nieudana kontrola pokazuje zmierzone liczby (`QualityCheck.detail`). Gdy w nagraniu widać powtórzenia, można je przeanalizować mimo uwag („Analizuj mimo to”), a wynik jest wtedy oznaczony jako orientacyjny.
4. **Nic nie było widać.** Użytkownik czekał na kręcący się wskaźnik. Teraz w czasie odczytu pokazujemy klatkę z nałożonym szkieletem (jak w serii na żywo), pasek postępu i liczbę klatek. Obraz zostaje w pamięci, nie jest nigdzie zapisywany, a film kasujemy po odczycie.

## 2. Jak liczymy

- **Stawy:** Apple Vision `VNDetectHumanBodyPoseRequest` (2D, 19 punktów, na telefonie). Jedna osoba na klatkę (ta z największą sumą pewności), film przerzedzany do ok. 30 kl./s.
- **Kąt w stawie:** kąt wewnętrzny (180° = wyprostowana kończyna) z lepiej widocznej strony ciała (`PoseLimbs`), nigdy z mieszania lewej i prawej.
- **Powtórzenia:** wysokość bioder (przysiad) albo barków (pompka, podciąganie) w długościach tułowia → mediana 5 próbek → średnia ruchoma 0,25 s → szczyty z prominencją co najmniej: przysiad 0,12, pompka 0,06, podciąganie 0,10, dipy 0,10 długości tułowia, szerokością co najmniej 0,3 s (odrzuca jedno–dwuklatkowe błędy śledzenia) i co najmniej połową typowej prominencji w nagraniu. Powtórzenie musi **zgiąć staw ćwiczenia** o co najmniej 20° (kolano, łokieć); przesunięcie całego ciała (podejście do telefonu, schylenie się) nie liczy się. Klatka „najniższego punktu” to nie klatka ekstremalna, tylko ćwierć drogi od ekstremum, żeby pojedynczy błąd nie stał się „dnem”.
- **Ocena:** te same oceniacze co na żywo (`BasicSquatAssessor`, `BasicPushupAssessor`, `BasicPullupAssessor`, `BasicDipAssessor`), z progami z `scoring.json` → `angles`. Przysiad ma dodatkowo własny ważony wynik (głębokość, tułów, powtarzalność, tempo). W uwagach pokazujemy zmierzone liczby („kolano średnio 55°”, „łokcie na dole 87°”).

## 3. Zakresy i skąd pochodzą

Kąty to kąty **wewnętrzne** stawu (180° = prosto). **Pewność**: wysoka = zmierzona w badaniu lub formalna definicja, średnia = definicja plus nasza tolerancja, niska = wartość inżynierska do sprawdzenia na nagraniach.

| Ćwiczenie | Co oceniamy | Wartość w `scoring.json` | Źródło i uwagi | Pewność |
|---|---|---|---|---|
| Przysiad | głębokość: biodro nie wyżej niż kolano (`squatDepthTolerance` 0,02 wysokości obrazu) | reguła | Reguła boczna przyjęta w trójboju: nie wyżej niż kolano. Dokładnie „równolegle” = fałd pachwiny tuż poniżej rzepki ([Cotter i in. 2013](https://pmc.ncbi.nlm.nih.gov/articles/PMC4064719/)). | średnia |
| Przysiad | kąt kolana na dole, równolegle | `squatKneeParallelMax` **70°** (zgięcie 110°) | Zgięcie kolana: powyżej równoległej 99°, równolegle **124°**, poniżej równoległej **141°** ([Cotter i in. 2013](https://pmc.ncbi.nlm.nih.gov/articles/PMC4064719/)). Kąt wewnętrzny to 180° minus zgięcie, czyli ok. 81°, **56°**, **39°**. Granica 70° jest luźniejsza o błąd 2D (ok. 14°). | średnia |
| Przysiad | kąt kolana, wyraźnie poniżej równoległej | `squatKneeDeepMax` **50°** | jw. (39° + tolerancja) | średnia |
| Przysiad | pochylenie tułowia od pionu na dole | `squatTorsoLeanMax` **45°** | Wartość inżynierska zespołu. Pochylenie zależy od ułożenia sztangi i proporcji ciała (przysiad ze sztangą z tyłu pochyla bardziej, goblet mniej). Do sprawdzenia na nagraniach. | niska |
| Pompka | łokieć na dole | `pushupElbowBottomMax` **100°**, cel `pushupElbowIdeal` **90°** | Standard testu pompek (np. Fitnessgram): zejście do **90° w łokciach**, ramię równolegle do podłogi, ciało w linii od głowy do stóp ([przegląd standardów](https://www.topendsports.com/testing/tests/pushup.htm)). Granica 100° to 90° plus tolerancja błędu 2D. | wysoka (definicja), średnia (tolerancja) |
| Pompka | wyprost łokcia na górze | `pushupElbowTopMin` **155°** | Pełne wyprostowanie to cel standardu; 155° to tolerancja błędu 2D i naturalnego niedoprostu. Informacja, nie wpływa na wynik. | średnia |
| Pompka | linia ciała (bark – biodro – kostka) | `pushupBodyLineMin` **160°** | Standard wymaga prostej linii (180°). Kąt 160° to zapadnięcie biodra o ok. 13 cm przy odległości bark – kostka 1,5 m, czyli widoczne gołym okiem. Wartość inżynierska. | niska |
| Podciąganie | łokieć na górze | `pullupElbowTopMax` **100°** | W pełnym podciągnięciu łokieć jest mocno zgięty (opisy ruchu: ok. 30–55° przy brodzie nad drążkiem). 100° jest świadomie luźne, bo w widoku z przodu łokcie uciekają na boki i kąt z obrazu 2D jest zaniżany. | niska–średnia |
| Podciąganie | zwis na początku | `pullupElbowHangMin` **155°** | Definicja pełnego powtórzenia: start z wyprostowanych ramion (pomiary pokazują wyprost ok. 170–190°). Informacja, nie wpływa na wynik. | średnia |
| Podciąganie | broda nad drążkiem | nos nad nadgarstkami o `pullupNoseMargin` **0,02** wysokości obrazu | Drążka nie wykrywamy; ręce trzymają drążek, więc głowa nad rękami przybliża „brodę nad drążkiem”. | średnia |

| Dipy (poręcze) | łokieć na dole | `dipElbowBottomMax` **100°** | Standard techniki: zejście, aż ramię jest mniej więcej **równolegle do podłogi** (barki na wysokości łokci), czyli ok. 90° w łokciu ([StrongLifts](https://stronglifts.com/dips/), [Gravitus](https://gravitus.com/guides/exercises/dip/)). W badaniu z kątami łokcia 75°, 85° i 95° ([Kinesiologia Slovenica](https://journals.uni-lj.si/kinsi/article/view/29659), 10 mężczyzn) mięsień trójgłowy pracował najmocniej przy najgłębszym kącie (75°), klatka podobnie przy każdym. 100° to 90° plus tolerancja błędu 2D. | średnia |
| Dipy | wyprost łokcia na górze | `dipElbowTopMin` **155°** | Pełne powtórzenie zaczyna się i kończy w podporze na wyprostowanych ramionach. Wpływa na wynik (40%), bo bez wyprostu zakres jest niepełny. W nagraniach z lekkim niedoprostem kąt wynosił 170–179°, więc 155° ma zapas na błąd 2D. | średnia |
| Dipy | bardzo głębokie zejście | `dipElbowDeepMin` **45°** | Tylko informacja, bez wpływu na wynik. Opisy techniki i artykuł o kinematyce dipów ([McKenzie i in. 2022, „Bench, Bar, and Ring Dips”](https://pdfs.semanticscholar.org/1640/606e956e51163d4c92b648e13327b87b3d03.pdf)) wskazują, że głębokie zejście i duży wyprost w barku mocniej obciążają przód barku, szczególnie u osób z bólem lub urazem barku. 45° to wartość inżynierska, **niska** pewność. W trzech nagraniach dna miały 52–73°, więc nikt jej nie przekroczył. | niska |
| Dipy | pochylenie tułowia | bez progu | Tylko informacja: pochylenie do przodu (ok. 30°) przesuwa pracę na klatkę, pionowo mocniej pracują triceps (opisy techniki). To styl, nie błąd, więc nie oceniamy. W nagraniach 29–35° od pionu na dole. | – |

Zastrzeżenia do źródeł podciągania: liczby pochodzą z opisów ruchu i prac uczelnianych znalezionych w wyszukiwaniu ([przykład](https://public.websites.umich.edu/~mvs330/w97/pullups/results2.html)), nie zweryfikowaliśmy ich w pełnych tekstach badań (np. Youdas i in. 2010, *J Strength Cond Res* 24(12): 3404–3414). Dlatego przy podciąganiu mamy luźne progi i mocny nacisk na regułę „głowa nad rękami”.

**Czego nie robimy:** nie stawiamy diagnoz ani nie oceniamy ryzyka urazu. Mówimy „sygnał”, „zakres ruchu poza zalecanym”, „warto rozważyć konsultację” (PROJECT.md 3.6). Kąty są wskazówką techniczną, nie badaniem.

## 4. Jak dokładne są kąty z Vision

- Oszacowanie pozy z jednej kamery 2D ma błąd rzędu kilku do kilkunastu stopni i jest najlepsze z boku, w płaszczyźnie ruchu. Rzut perspektywiczny (telefon nie dokładnie z boku, blisko, pod kątem) zniekształca kąty. Zasłonięta kończyna (przysiad z boku zasłania jedną nogę) obniża pewność.
- Jedyne niezależne porównanie, które znaleźliśmy, dotyczy **3D ARKit** względem systemu Vicon: średni błąd bezwzględny **18,8° ± 12,1°** (od 3,8° do 47,1° zależnie od stawu i ćwiczenia), silnie zależny od widoczności stawów ([Reimer i in. 2022](https://portal.fis.tum.de/en/publications/evaluating-3d-human-motion-capture-on-mobile-devices/)). To nie ten sam model co `VNDetectHumanBodyPoseRequest`, ale pokazuje, że nie wolno obiecywać dokładności, której nie zmierzyliśmy. W aplikacji piszemy wprost, że kąt z 2D to szacunek z błędem rzędu kilku stopni, a pasmo na wykresie to zakres oczekiwany, nie wyrok.
- Dlatego progi mają **tolerancję**, a decyzje (głębokość przysiadu, głowa nad rękami) opierają się na regułach geometrycznych odpornych na błąd kąta, nie tylko na kącie.

## 5. Gotowe modele: porównanie i rekomendacja

| Model | Co daje | Za | Przeciw |
|---|---|---|---|
| **Apple Vision 2D** (`VNDetectHumanBodyPoseRequest`), **używamy** | 19 punktów 2D, na telefonie, bez kosztów | działa offline, wideo nie opuszcza telefonu, zero zależności, pasuje do iOS 17 | brak stóp (palce, pięty), tylko 2D, błąd przy zasłonięciu |
| **Apple Vision 3D** (`VNDetectHumanBodyPose3DRequest`, iOS 17) | 17 punktów w metrach względem biodra, jedna osoba | kąty w 3D nie zależą od ustawienia kamery względem ciała, ten sam framework, na telefonie | nowszy i mniej przetestowany, błąd rośnie bez głębi, tylko jedna osoba; wymaga własnej walidacji (patrz wyżej) |
| **MediaPipe Pose Landmarker** (Google, Apache-2.0) | 33 punkty, w tym pięty i palce stóp, współrzędne „świata” | stopy (unoszenie pięt w przysiadzie, linia pompki do stóp), dobre dokumentacje | wchodzi przez CocoaPods (`MediaPipeTasksVision`), nie przez SwiftPM: tarcie z XcodeGen i buildem; większa paczka; trzeba przepiąć ekstraktor i LiveSet |
| **Modele ocen techniki** (np. Fitness-AQA, [Parmar i in. 2022](https://arxiv.org/abs/2202.14019)) | wynik jakości wykonania z wideo uczony na danych | pokazują kierunek badań | zbiory badawcze, brak gotowego modelu do iOS, trudne do wyjaśnienia użytkownikowi, ryzyko twierdzeń bez pokrycia |

**Rekomendacja:** zostajemy przy **Vision 2D + jawny model kątów z uzasadnionymi zakresami** (to, co jest w kodzie): jest wyjaśnialny („kolano 55°, cel poniżej 70°”), działa na telefonie i pasuje do zasad produktu (bez diagnoz, wideo na telefonie). Kolejne kroki, w kolejności opłacalności: (1) skalibrować progi na prawdziwych nagraniach (sekcja 6), (2) porównać na tych samych nagraniach kąty z `VNDetectHumanBodyPose3DRequest` i wybrać lepszy dla widoków pod kątem, (3) MediaPipe dopiero, jeśli okaże się, że bez stóp nie da się ocenić np. unoszenia pięt.

## 6. Jak to skalibrować na prawdziwych nagraniach

1. Nagraj na każde ćwiczenie 3 filmy: dobre, płytkie/niepełne, ze złą linią ciała (3–5 powtórzeń, telefon z boku na wysokości bioder, 2–3 m, cała sylwetka w kadrze; podciąganie z przodu albo z boku).
2. Dla jednego powtórzenia w każdym filmie zmierz kąt na zatrzymanym obrazie w najniższym punkcie (linijka kątowa w Zdjęciach, Kinovea albo kątomierz na ekranie) i porównaj z kątem w aplikacji (karta powtórzenia pod wykresem, albo „Wyślij pozy (JSON)” z testu na żywo).
3. Cel: średni błąd kąta ≤ 10° i poprawny werdykt (głębokość, linia, głowa nad rękami) w ≥ 90% powtórzeń. Jeśli błąd jest systematyczny, popraw tolerancje w `scoring.json` → `angles`, jeśli powtórzenia są liczone źle, w `clip`. Wartości są w konfiguracji, więc strojenie nie wymaga wydania aplikacji (`python scripts/sync_content.py`, backend `/v1/config`).
4. Zapisz zmierzone pary (kąt z ręki, kąt z aplikacji) w `feat/bartek-fixtures`; to będą testy regresji.

## 7. Dipy: co sprawdziliśmy na prawdziwych nagraniach

Dodane jako czwarte ćwiczenie z analizą (`MovementKind.dip`, katalog: `dip`). Sygnał do liczenia powtórzeń jest taki jak w pompce (szyja i barki idą w dół, start w pełnym wyproście), oceniacz to `BasicDipAssessor`: głębokość (łokieć do ok. 100°) i wyprost na górze, plus informacje o bardzo głębokim zejściu i pochyleniu tułowia.

**Trzy filmy testowe** (iPhone, widok z boku, poręcze na drabince gimnastycznej, trzy różne osoby, jedna strona ciała widoczna, 17–19 s):

| Film | Powtórzenia (liczone ręcznie → aplikacja) | Łokieć na dole | Wyprost na górze | Pochylenie tułowia na dole |
|---|---|---|---|---|
| IMG_3025 | 7 → 7 | 52–68° | 170–174° | 31–37° |
| IMG_3026 | 6 → 6 | 54–64° | 174–179° | 23–33° |
| IMG_3027 | 5 → 5 | 66–73° | 175–179° | 35–36° |

- Vision czytał pozę poprawnie (stawy po widocznej stronie ciała w 100% klatek, druga strona zasłonięta w 30–50%).
- W IMG_3025 pierwsze 5 s to wejście na poręcze (osoba stoi z rękami na poręczy, pochyla się i wskakuje). Samo w sobie ma kształt powtórzenia (łokieć 133° → 88°), ale nie zaczyna się od wyprostu, więc **powtórzenie jest odrzucane regułą „start z łokciem ≥ 145°”** (`minStartElbowForClip`). Bez niej film miał 8 powtórzeń zamiast 7.
- Wszystkie trzy osoby schodzą **głębiej niż 90°** (barki poniżej łokci o 2–6% wysokości kadru), więc próg 100° nikogo nie karze, a próg „bardzo głęboko” (45°) nikogo nie flaguje.
- Filmy zawierają tylko **dobrze wykonane** powtórzenia. Wykrywanie „za płytko” i „bez wyprostu” sprawdzone jest na pozach syntetycznych (`DipTests`), nie na prawdziwym człowieku. Do kalibracji brakuje nagrań płytkich dipów i dipów bez wyprostu.
- Testy regresji: pozy z trzech filmów (10 kl./s) są w `Packages/Core/Tests/AnalysisTests/Fixtures/dips/`, sprawdzamy liczbę powtórzeń, kąty i wynik.

**Nie obsługujemy** (jeszcze): dipów na ławce lub krześle (inna geometria: ręce za plecami, stopy na podłodze), dipów z obciążeniem, widoku z przodu (kąt łokcia z 2D byłby zaniżony), oceny wymachu (kipping) i rozstawu łokci.
