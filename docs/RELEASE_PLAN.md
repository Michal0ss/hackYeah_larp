# Plan wydania hackGYM w App Store

Stan na 9.10.2026, `main` po #107. Dokument opisuje, co trzeba zrobić, żeby z wersji z hackathonu zrobić aplikację dostępną w App Store, i jakie funkcje warto dodać. Czasy to szacunki dla zespołu 2–4 osób, nie obietnice. Numery wytycznych Apple i ceny są z pamięci: **przed zgłoszeniem sprawdź je w aktualnych App Store Review Guidelines i w App Store Connect**.

Oznaczenia: `[ ]` do zrobienia, `[x]` zrobione. Punkty z **(?)** wymagają decyzji albo sprawdzenia.

## 1. Stan wyjściowy (sprawdzone w repo)

| Obszar | Stan |
|---|---|
| Bundle id | `com.michal0ss.forma` (`Config/Base.xcconfig`). Po utworzeniu rekordu w App Store Connect nie da się go zmienić |
| Platforma | tylko iPhone, tylko pion, iOS 17+ |
| Uwierzytelnienie backendu | **jeden wspólny token** zapisany w `Info.plist` aplikacji (`FormaAPIToken`), więc da się go wyciągnąć z binarki |
| Logowanie użytkownika | Google (PKCE, Supabase), konto opcjonalne („Kontynuuj bez konta"). **Brak Sign in with Apple** |
| Privacy manifest | brak `PrivacyInfo.xcprivacy`, a aplikacja używa `UserDefaults` |
| Szyfrowanie | brak `ITSAppUsesNonExemptEncryption` |
| Release | `NSLocalNetworkUsageDescription` i `NSAllowsLocalNetworking` zostają (potrzebne tylko deweloperom). Zapis do Zdrowia jest usuwany z Release skryptem, a flagi startowe (`-skip-login`, `-reset-onboarding`, `-seed-health`) są objęte `#if DEBUG`. **W Release zostają jednak** karta „Test analizy na żywo" w Profilu i przycisk diagnostyczny (biedronka) w serii na żywo |
| Prawo | brak polityki prywatności, regulaminu i strony wsparcia |
| Awarie i analityka | brak raportowania awarii i analityki |
| Treść | katalog 30 ćwiczeń bez filmów wzorcowych, interfejs i prompty tylko po polsku |
| Testy na urządzeniu | z README: nie sprawdzone m.in. HealthKit z zegarkiem, synchronizacja konta na dwóch telefonach, głos w słuchawkach |

## 2. Plan w fazach

| Faza | Zakres | Szacunek |
|---|---|---|
| 0. Decyzje | konto Apple, nazwa, bundle id, model biznesowy, kraje, status trader | 1–2 dni |
| 1. Fundament techniczny | auth użytkownika, Sign in with Apple, privacy manifest, porządki w Release, raportowanie awarii, testy na telefonach, infrastruktura | 1–2 tyg. |
| 2. Prawo i sklep (równolegle z 1) | polityka prywatności, regulamin, wsparcie, etykiety prywatności, opis i zrzuty, konto demo | 1–2 tyg. |
| 3. TestFlight | wewnętrzny, potem zewnętrzny; zbieranie nagrań i strojenie progów techniki | ok. 2 tyg. |
| 4. App Review | zgłoszenie, zwykle 1–2 dni na decyzję, plan na 1–2 poprawki | ok. 1 tyg. |
| 5. Po wydaniu | monitoring kosztów i awarii, wsparcie, aktualizacje | ciągłe |

### Faza 0: decyzje
- [ ] **Konto Apple Developer (?)**: osoba czy firma. Około 99 USD rocznie, sprawdź cenę lokalną. Firma wymaga numeru D-U-N-S, a osobiste konto jest szybsze.
- [ ] **Status „trader" w UE (?)**: Apple wymaga deklaracji, a trader publikuje adres i telefon w sklepie. Ważne zwłaszcza, jeśli aplikacja ma być płatna lub komercyjna.
- [ ] **Nazwa (?)**: sprawdzić, czy „hackGYM" jest wolna w App Store i nie narusza znaku towarowego.
- [ ] **Bundle id (?)**: zostaje `com.michal0ss.forma` czy zmieniamy na docelowy. Kod, foldery danych na telefonie i zmienne `FORMA_*` zostają bez zmian, zmienia się sam identyfikator.
- [ ] **Model biznesowy (?)**: darmowa, płatna, subskrypcja. Od tego zależy StoreKit, konto bankowe i podatki w App Store Connect.
- [ ] **Konto w aplikacji (?)**: czy czat i plan AI mają działać bez konta (wtedy anonimowe sesje Supabase), czy konto ma być wymagane.

### Faza 1: fundament techniczny
- [ ] **Auth użytkownika w backendzie.** Backend przyjmuje token sesji Supabase (JWT) zamiast wspólnego tokenu, a limity liczy na użytkownika. Wspólny token najwyżej jako dodatkowy klucz aplikacji. Usunąć `FormaAPIToken` z `Info.plist` albo traktować go jako niezaufany.
- [ ] **Sign in with Apple** obok Google (Supabase ma providera Apple). Wytyczna 4.8 wymaga równoważnej opcji logowania, a Google sam jej nie spełnia (nie ukrywa adresu e-mail).
- [ ] **`PrivacyInfo.xcprivacy`**: deklaracja użycia `UserDefaults` i innych API z listy „required reason", brak śledzenia, deklaracja zbieranych danych.
- [ ] **`ITSAppUsesNonExemptEncryption = NO`** (tylko HTTPS).
- [ ] **Porządki w Release**: usunąć `NSLocalNetworkUsageDescription` i `NSAllowsLocalNetworking`. Schować za `#if DEBUG` kartę „Test analizy na żywo" (`ProfileView.liveTestCard`) i przycisk diagnostyczny w `LiveSetView` albo świadomie zostawić je jako funkcję dla użytkownika, z polskim opisem zamiast „ikona biedronki pokazuje liczby". Przejrzeć resztę ekranów pod kątem tekstów i opcji dla deweloperów.
- [ ] **Rotacja sekretów** użytych podczas hackathonu (token aplikacji, ewentualnie klucze Supabase i Gemini).
- [ ] **Raportowanie awarii**: najprościej Xcode Organizer i MetricKit (bez SDK). Jeśli Sentry, to wpisać do etykiet prywatności.
- [ ] **Testy na prawdziwych telefonach**: kamera tylna i selfie, „Nagraj teraz", wczytanie filmu z galerii (także z iCloud), HealthKit z zegarkiem, synchronizacja konta na dwóch telefonach, głos w słuchawkach, dźwięki tempa, różne rozmiary ekranów (m.in. iPhone SE), słaby sygnał, tryb samolotowy.
- [ ] **Infrastruktura**: Vercel Pro (Hobby jest niekomercyjny, sprawdź aktualne warunki), Supabase w planie płatnym, region UE, kopie zapasowe, Gemini w płatnym projekcie z limitem budżetu i alertami.
- [ ] **Monitoring kosztów**: dzienny limit zapytań do modelu na użytkownika, alert przy skoku.

### Faza 2: prawo i sklep
- [ ] **Polityka prywatności i regulamin** pod publicznym adresem, po polsku (angielska wersja, jeśli rynek ma być szerszy). Dane zdrowotne to art. 9 RODO: administrator danych, podstawa prawna (zgoda), okresy przechowywania, podmioty przetwarzające (Supabase, Vercel, Google), prawa użytkownika, kontakt. Najlepiej do przeczytania przez prawnika.
- [ ] **Status medyczny.** Pozycjonujemy się jako wellness („sygnał, nie diagnoza"). Wytyczne 1.4.1 i 5.1.3 patrzą na aplikacje zdrowotne uważnie, więc opis w sklepie nie może obiecywać diagnoz, pomiarów medycznych ani skuteczności. Przed komercyjnym wdrożeniem ocena statusu prawnego (MDR) z prawnikiem.
- [ ] **Zgoda na AI** (wytyczna 5.1.2(i)): jasna informacja, że dane osobowe trafiają do zewnętrznego modelu, i który to dostawca. Mamy zgodę zdrowotną w czacie, trzeba sprawdzić, czy tekst nazywa dostawcę.
- [ ] **Etykiety prywatności** w App Store Connect (dane zdrowotne i fitness, dane kontaktowe, identyfikatory, diagnostyka) muszą zgadzać się z faktycznym ruchem do Supabase i backendu.
- [ ] **Materiały**: ikona 1024 (jest), zrzuty na wymagane rozmiary iPhone'a, opis i słowa kluczowe po polsku, kategoria Zdrowie i fitness, ocena wieku, adres wsparcia, adres polityki prywatności.
- [ ] **Konto demo dla recenzenta**: mamy `smiechufabryka@gmail.com` z danymi testowymi, ale logowanie Google bywa kłopotliwe dla recenzenta. Najlepiej, żeby aplikacja działała bez konta, albo mieć logowanie testowe. W notatkach dla recenzenta opisać, jak uruchomić kamerę i dane przykładowe.
- [ ] **Dane przykładowe** oznaczone wszędzie jako „Dane przykładowe" (jest), żeby recenzent nie uznał ich za wprowadzanie w błąd.
- [ ] **Licencje treści**: baza wiedzy trenera (WHO, PMC z NC/ND, Wikipedia CC BY-SA) i czcionki, zanim aplikacja stanie się komercyjna.

### Faza 3: TestFlight
- [ ] **Wewnętrzny** (do 100 osób, bez przeglądu): zespół i znajomi, 3–5 dni.
- [ ] **Zewnętrzny** (do 10 000 osób, krótki przegląd beta): 20–50 osób, które ćwiczą.
- [ ] **Nagrania do strojenia progów techniki** (tylko za wyraźną zgodą, na początek własne): dziś są trzy nagrania dipów. Progi w `content/config/scoring.json` to wartości startowe.
- [ ] Zebrać awarie, zgłoszenia i koszty modelu na użytkownika, a dopiero potem składać do App Review.

### Faza 4: App Review
- [ ] Zgłoszenie z notatkami dla recenzenta (konto demo, jak uruchomić ćwiczenie z kamerą, gdzie jest usuwanie konta i danych).
- [ ] Zwolnienie ręczne albo etapowe (phased release), żeby móc zatrzymać wydanie.
- [ ] Plan na odrzucenie: poprawka i ponowne zgłoszenie, zwykle w ciągu doby.

### Faza 5: po wydaniu
- [ ] Dashboard kosztów (Gemini, Vercel, Supabase), alerty, dyżur na pierwsze dni.
- [ ] Obsługa zgłoszeń i recenzji, szablony odpowiedzi.
- [ ] Cykl aktualizacji (strojenie progów, nowe ćwiczenia, poprawki).

## 3. Najczęstsze powody odrzucenia, które nas dotyczą

| Wytyczna | Ryzyko u nas |
|---|---|
| 4.8 | brak równoważnej opcji logowania obok Google |
| 2.1 | backend niedostępny, brak konta demo, ekran, który bez klucza nic nie robi |
| 5.1.1, 5.1.2 | etykiety prywatności niezgodne z danymi, brak linku do polityki prywatności, niejasna zgoda na AI |
| 5.1.3, 1.4.1 | język sugerujący diagnozę, pomiar medyczny albo obietnicę skuteczności |
| opisy uprawnień | każdy opis (kamera, mikrofon, rozpoznawanie mowy, lokalizacja, Zdrowie) musi dokładnie odpowiadać użyciu; dziś są poprawne, klucze lokalnej sieci trzeba usunąć |
| 5.1.1(v) | usuwanie konta w aplikacji (jest: Profil, „Usuń konto") |
| 4.2, 2.3 | metadane i zrzuty zgodne z tym, co faktycznie działa; ćwiczenia bez analizy oznaczone „w przygotowaniu" (jest) |

## 4. Opcje do dodania

| Opcja | Po co | Uwagi |
|---|---|---|
| **Sign in with Apple** | wymóg 4.8, mniej tarcia przy logowaniu | do wydania |
| **Przypomnienia o treningu** (powiadomienia lokalne) | retencja, najtańszy zysk | nie wymaga backendu |
| **Zapis treningu do Apple Health** | trening w Zdrowiu i w pierścieniach aktywności | wymaga uprawnienia do zapisu i zmiany opisu (dziś zapis jest celowo usunięty z Release) |
| **Apple Watch** (tętno na żywo, haptyka zamiast dźwięku tempa) | świetnie pasuje do trenera tempa | największy koszt z listy |
| **Widżet i Live Activity** (najbliższa sesja, odpoczynek) | wygoda | średni koszt |
| **Więcej ćwiczeń z analizą** (wykrok, martwy ciąg rumuński, mostek) | wartość produktu | własny oceniacz kątów na ćwiczenie |
| **Filmy wzorcowe** | zamienniki i technika | tylko własne nagrania albo jasna licencja |
| **Eksport i usunięcie danych** | RODO | usuwanie konta już jest |
| **Wersja angielska** | większy rynek | dziś wszystko po polsku, także prompty i teksty |
| **Subskrypcje (StoreKit 2)** | monetyzacja | wytyczne 3.1.x, konto bankowe i podatki w App Store Connect |
| **Skróty Siri** („Zacznij dzisiejszy trening") | wygoda | mały koszt |
| **iPad, Dynamic Type, VoiceOver** | dostępność | dziś tylko iPhone w pionie, dostępność w podstawowym zakresie |
| **Tryb trenera, Garmin, Android** | dalszy rozwój | wizja z PROJECT.md, sekcja 14 |

## 5. Co robić najpierw

1. Jeden mały PR (tylko aplikacja, bez decyzji biznesowych): `PrivacyInfo.xcprivacy`, `ITSAppUsesNonExemptEncryption`, usunięcie kluczy lokalnej sieci z Release, przegląd tego, co deweloperskie w Release.
2. Sign in with Apple i auth użytkownika w backendzie (największa zmiana, dotyka Supabase, backendu i aplikacji).
3. Równolegle: polityka prywatności, regulamin i strona wsparcia.
4. Pierwszy build do TestFlight wewnętrznego, jak tylko punkty 1 i 2 będą w `main`.

Zasady produktu z CLAUDE.md obowiązują bez zmian: żadnych diagnoz, wideo i pozy nie opuszczają telefonu, klucz do modelu tylko na serwerze, uczciwie o tym, co jest symulowane.
