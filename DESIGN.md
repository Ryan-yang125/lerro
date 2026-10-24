# Lerro design

Lerro is native, quiet, and precise everywhere. The macOS app uses native
adaptive grays; the website uses a warm paper palette. Both share the cursor-L
mark, the ink-blue accent and the ink-black capsule HUD. Brand sources and usage rules are in
[`Brand/`](Brand/README.md).

## Brand

- Mark: a cursor standing on a text baseline forming an L ("cursor L").
- Colors: ink black `#15161A`, paper white `#F6F4EF`, ink blue `#2F5BFF` (dark
  appearance `#4A6BFF`, filled buttons `#3557F0` for white-text contrast).
- Voice and copy rules: [`Brand/guidelines/voice-and-copy.md`](Brand/guidelines/voice-and-copy.md).

## App

- Adaptive black-and-white-gray palette (`LerroTheme`) plus the ink-blue accent,
  which is also compiled into the asset catalog as `AccentColor` so system controls
  inherit it. Success, warning, and error use macOS system colors.
- Light body text levels: `#292929`, `#5D5D5D`, `#9E9E9E`; 12 pt text that carries
  needed information uses `#6B6B6B`.
- SF Pro, PingFang SC, SF Mono. Scale in `LerroFont`: page title 15 semibold,
  body 13, detail 16, stat 30, caption 12, footnote 11; no fractional sizes. Tracking -0.15.
- Main window: a fixed 220 pt sidebar and the page. The window has an empty
  unified toolbar and no visible title, so macOS draws it with a 26 pt corner
  radius and centres the traffic lights on y = 26 ([ADR 0020](docs/decisions/0020-main-window-alignment.md)).
  The whole window is at least 988 × 658.
  Each page starts with `LerroPageHeader` ([ADR 0017](docs/decisions/0017-fixed-sidebar.md)).
  Lists, tables, and forms use native `List`, `Table`, and `Form`; Settings is a
  separate window. Primary actions are pill buttons. Hover fades fill in 150 ms; pointer-down
  drops opacity to 0.8 in 100 ms. Reduce Motion keeps the same opacity feedback.
- Grid 4 pt; spacing values 2, 4, 6, 8, 10, 12, 16, 20, 24, 28, 32, 40. No subtitles
  or helper text under headings, cards, or settings.
- HUD: a fixed ink-black Liquid Glass capsule, 40 pt high and at most 480 pt wide.
  All states morph inside the same capsule; the recording state shows an ink-blue
  cursor and a nine-bar waveform ([ADR 0013](docs/decisions/0013-brand-capsule-hud.md)).
- Tokens live in [`DesignTokens.swift`](Sources/Lerro/DesignSystem/DesignTokens.swift)
  and shared controls in `MainWindowComponents.swift`.

### Alignment

Points from the main window's top-left corner.

| Line | Position | On the line |
| --- | --- | --- |
| A | y = 26 | Traffic lights, page title, every page-header control (header 52 high, content centred) |
| B | y = 72 | Sidebar wordmark (row 52–92); the first content heading of History and Dictionary (content top padding 8 + heading row 24); the History detail app row (52–92) |
| S | x = 18 | Wordmark, sidebar row icon boxes, AI status dot, settings icon box (sidebar inset 8 + row padding 10); the traffic lights start at 19 |
| P | x = 248 | Page titles and all page content (sidebar 220 + page padding 28); History rows: list inset 16 + row padding 12 |
| D | x = 604 | History detail (list 220–580 + detail padding 24); text inside its AI card at 620 |

### Sizes

- Sidebar: rows 32 high, 2 apart, radius 8, inset 8, padding 10; icon `.large` + 8 + 13 pt
  title; count 11 pt. Footer: AI status 32 high, settings button row 32 high, bottom inset 8.
- Page header: 52 high, padding 28, controls 8 apart and all 28 high (segmented pickers
  `.controlSize(.large)`); keycaps 20 high, display only.
- Page content starts at y = 60, padding 28; section heading rows 24 high; cards radius 16,
  padding 20, 12 apart. Home and App Tones content stays leading-aligned on wide windows.
- History list 360 wide, rows padding 10 × 12, radius 10, app icon 20 + 12; detail padding 24.
- Menu bar panel 304 wide, radius 18, padding 8, inner blocks radius 10, rows 32 high.
- Icons: SF Symbols at four sizes through `.lerroIcon(_:)` — small 10 (box 12, label gap 4),
  medium 12 (box 16, gap 6), large 14 (box 18, gap 8), extra large 20 (box 24). Outline,
  regular weight; status and playback symbols use the filled variant.
- Radii are concentric (inner = outer − distance between edges): window 26 (system),
  menu bar panel 18, cards 16, list rows and panel blocks 10, controls 8, keycaps 6,
  buttons, search fields and chips are capsules.
- Controls: buttons 28 (compact 24), icon buttons 28 × 28, search field 200 × 28 capsule,
  segmented pickers 28 in headers and 24 in content, chips 24.
- Acceptance: measure a fixture build with the Accessibility API (every element's frame);
  traffic lights and header controls on y = 26, the B-line elements on y = 72, sidebar boxes
  on x = 18, page content on x = 248, History detail on x = 604.
## Website

- Astro static site in [`site/`](site/README.md), Chinese at `/` and English at `/en`.
- Warm paper palette in `site/src/styles/global.css`: page `#FAF7F2` (dark
  `#151412`), surfaces `#FFFDF9` (dark `#1D1B18`), ink `#1C1A16` (dark `#F1EDE6`),
  one ink-blue accent `#2F5BFF` (dark `#6B8BFF`). Light and dark follow the system;
  there is no theme toggle.
- Headings use Noto Serif SC; body text uses the system sans. Primary buttons are
  near-black pills (cream in dark mode); secondary actions are underlined text links.
- No gradients, glows or blurred colour spots. Depth comes from hairlines, flat
  surfaces and edge shadows.
- The story and feature sections recreate the app UI and HUD in HTML, so
  screenshots and live demos stay consistent with the shipped app. The demo
  windows (WeChat, Mail, Notes) keep their real app colours.
- `prefers-reduced-motion` support.

## Product truth

Public visuals use current builds with synthetic data. Marketing copy keeps the
network boundaries explicit and matches [`PRIVACY.md`](PRIVACY.md).
