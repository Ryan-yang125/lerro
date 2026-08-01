# Asset Validation Record

## Baseline

- Brand: Lerro
- Pronunciation: `LEH-ro`
- Validation date: 2026-07-30
- Rendering environment: macOS, Apple Swift 6.3.1, AppKit SVG rendering, sRGB
- Source format: deterministic SVG
- App Icon pipeline: SVG → 16/32/64/128/256/512/1024 PNG → `iconutil` ICNS

## Automated gate

Run from the repository root:

```zsh
./Brand/scripts/generate-assets.sh
./Brand/scripts/verify-assets.sh
```

The verifier checks:

- every SVG parses with `xmllint`;
- JSON manifests parse and identify Lerro;
- `LerroTokens.swift` passes `swiftc -typecheck`;
- required SVG, PDF, PNG and ICNS files exist and contain data;
- copied SVG exports remain byte-identical with their editable sources;
- PNG dimensions match their delivery contract;
- ICNS includes 16 px through 1024 px representations;
- menu bar source art remains monochrome template artwork;
- Brand/ distributes zero font binaries;
- retired visual references and prohibited copy patterns remain absent;
- `SHA256SUMS.txt` verifies every tracked Brand Kit file.

## Visual matrix

| Surface | Required sizes | Light | Dark | Result |
| --- | --- | --- | --- | --- |
| Micro Mark | 16 and 24 pt | Ink Black | White | Pass |
| Menu idle | 16/24 px export, 18 pt runtime at 1×/2× | template black | template white | Pass |
| Menu listening | 16/24 px export, 18 pt runtime at 1×/2× | template black | template white | Pass |
| Menu processing | 16/24 px export, 18 pt runtime at 1×/2× | template black | template white | Pass |
| Menu error | 16/24 px export, 18 pt runtime at 1×/2× | template black | template white | Pass |
| App Icon | 16, 32, 64, 128, 256, 512 and 1024 px | fixed artwork | fixed artwork | Pass |

Generated evidence:

- `small-size-light.png`
- `small-size-dark.png`
- `exports/app-icon/Lerro.iconset/`

## Recorded result

- Automated gate: Pass on 2026-07-30.
- Visual review: Pass for App Icon, 16/24/32 px Micro Mark, four menu states, Aqua and Dark Aqua preview boards.
- Repeatability: Pass across two consecutive generation runs; all 90 generated asset hashes were identical.

## Phase 3 human checks

- Verify template tinting in the real `NSStatusItem` for normal, selected, inactive and Increase Contrast states.
- Verify VoiceOver labels update with idle, listening, processing and error.
- Verify App Icon appearance in Finder, Dock, Launchpad, System Settings permissions and the quarantine prompt.
- Verify Reduce Motion behavior in HUD and Ask on the final signed app.
