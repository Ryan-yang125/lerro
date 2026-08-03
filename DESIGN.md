# Lerro product design

Lerro shares one product language across the macOS app, website, screenshots,
and release pages: native, decisive, private, and quiet.

## Website system

The website uses the Interior material hierarchy adopted by Motion Lexicon:

- warm bezel `#efeeea`;
- white panel and quiet well surfaces;
- ink `#292929`, secondary `#5d5d5d`, focus blue `#3656df`;
- Apple system typography, including SF Pro and PingFang SC;
- 8–10 px interaction radii, 16–18 px content panels, restrained shadows;
- press, ripple, disclosure, focus, contrast, transparency, and reduced-motion states.

The adapted Interior components live in
[`site/app/components/interior/`](site/app/components/interior/). Attribution and
the MIT license are preserved in [`NOTICE`](NOTICE).

## Product truth

Public visuals use current Lerro fixture builds with synthetic data. The Hero
HUD follows [`CaptureHUDView.swift`](Sources/Lerro/Features/Ask/CaptureHUDView.swift):
70×34 pt shell, ten 2 pt bars at 20 Hz, and the three-dot 0.72 second processing
cycle. Reduced Motion preserves a static, readable state.

Marketing copy keeps offline and network boundaries explicit. Product claims
must match [`PRIVACY.md`](PRIVACY.md), [`docs/permissions.md`](docs/permissions.md),
and [`docs/models.md`](docs/models.md).
