# hackGym: branding (v2)

Podgląd: `brand-board.png`.

**Znak:** kettlebell jako szklana bryła z „skanowaną" siatką 3D (motyw computer vision, czyli nasza analiza techniki), przecięty glitchem (hack) i obwiedziony niebieską i pomarańczową poświatą z aplikacji. Narożniki w ikonie to celownik kamery.

**Logotyp:** „hack" Inter 400 + „Gym" Inter 800, litery zamienione na krzywe.

**Kolory:** volt `#C8FF2E`, ink `#0B0F14`, granat `#121B28`, lód `#F4F7FB`, błękit `#306EFF`, żar `#FF6A1F`. Volt nigdy na białym: na jasnym tle używamy wersji czarnej.

| Folder | Zawartość |
|---|---|
| `mark/` | sam znak: kolor, czarny, biały (SVG + PNG) |
| `logo/` | lockup poziomy i pionowy (SVG + PNG) |
| `app-icon/` | ikona iOS 1024: domyślna, ciemna, barwiona, volt; `AppIcon.appiconset` gotowy do Xcode; `layers/` (tło i znak osobno, do Icon Composer) |
| `social/` | awatar, favicon, apple-touch-icon, grafika linków 1200×630 |
| `_concepts/` | odrzucone i zapasowe kierunki (hantla szklana, hantla z punktami CV) |

**Podpięcie ikony w aplikacji (nie zrobione):** skopiować `app-icon/AppIcon.appiconset` do `App/Assets.xcassets/`, w `project.yml` ustawić `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`, `xcodegen generate`. `App/` i `project.yml` należą do Michała, więc osobny mały PR.
