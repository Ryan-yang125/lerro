# Lerro design

Lerro uses one visual language across the macOS app, website, screenshots, and
release pages: native, quiet, and precise. Brand sources and usage rules are in
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
  body 13, detail 16, stat 30, caption 12, footnote 11. Tracking -0.15.
- Native `NavigationSplitView`, `List`, `Table`, `Form`, and a separate Settings
  window. Primary actions are pill buttons. Hover fades fill in 150 ms; pointer-down
  drops opacity to 0.8 in 100 ms. Reduce Motion keeps the same opacity feedback.
- Icons: product concepts use `LerroGlyph` (16 pt grid, 1.4 pt round strokes, ink-blue
  cursor), generic actions use outline SF Symbols, status and playback use filled.
- HUD: a fixed ink-black Liquid Glass capsule, 40 pt high and at most 480 pt wide.
  All states morph inside the same capsule; the recording state shows an ink-blue
  cursor and a nine-bar waveform ([ADR 0013](docs/decisions/0013-brand-capsule-hud.md)).
- Tokens live in [`DesignTokens.swift`](Sources/Lerro/DesignSystem/DesignTokens.swift)
  and shared controls in `MainWindowComponents.swift`.

## Website

- Astro static site in [`site/`](site/README.md), Chinese at `/` and English at `/en`.
- Tokens in `site/src/styles/global.css` repeat the app palette: canvas `#FAFAFA`,
  ink `#292929`, accent `#2F5BFF`, with dark-mode equivalents.
- The hero and feature sections recreate the app UI and HUD in HTML using the same
  tokens, so screenshots and live demos stay consistent with the shipped app.
- Pill buttons, 0.5 px hairline borders, soft shadows, and `prefers-reduced-motion`
  and `prefers-color-scheme` support.

## Product truth

Public visuals use current builds with synthetic data. Marketing copy keeps the
network boundaries explicit and matches [`PRIVACY.md`](PRIVACY.md).
