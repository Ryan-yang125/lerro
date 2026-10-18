# Asset Validation Record

## Baseline

- Brand: Lerro
- Pronunciation: `LEH-ro`
- Mark: cursor 10 × 46, gap 6, baseline 36 × 9, mark 36 × 61 brand units
- Palette: ink `#15161A`, paper `#F6F4EF`, ink blue `#2F5BFF`, ink blue on dark `#4A6BFF`, graphite `#8B8C93`
- Rendering environment: macOS, Apple Swift, AppKit SVG rendering, sRGB
- Source formats: deterministic SVG, Icon Composer bundle `source/app-icon/AppIcon.icon`
- App Icon pipeline: `AppIcon.icon` → `xcrun actool` → `AppIcon.icns` + `Assets.car`; the 1024 px preview PNG is rendered from the same bundle
- Wordmark: `L` is the mark; `erro` is Inter 4.1 SemiBold outlined to paths. No font file is distributed.

## Automated gate

Run from the repository root:

```zsh
./Brand/scripts/generate-assets.sh
./Brand/scripts/verify-assets.sh
```

`verify-assets.sh` checks:

- every SVG parses with `xmllint`;
- `brand.tokens.json` and `ASSET-LICENSES.json` parse and identify Lerro;
- `LerroTokens.swift` passes `swiftc -typecheck`;
- token palette values match the five brand colors above;
- required SVG, PDF, PNG, ICNS and `Assets.car` files exist and contain data;
- `AppIcon.icon` contains the ink fill, cursor layer and baseline layer;
- `AppIcon.icns` includes 16 px through 1024 px representations and `Assets.car` contains the `AppIcon` set;
- PNG dimensions match their delivery contract, including 18 px and 36 px menu bar frames;
- all eight menu bar frames exist (`Idle`, `Listening`, `ListeningDim`, `Processing1` to `Processing4`, `Error`) and are monochrome with an alpha channel;
- logo SVGs contain no `<text>` elements, so the wordmark is outlined paths only;
- Brand/ distributes zero font binaries; `licenses/Inter-OFL.txt` exists;
- runtime copies in `Sources/Lerro/Resources` are byte-identical with `exports/`;
- retired visual references (old mark names, gradients in logo sources) and prohibited copy patterns remain absent;
- `SHA256SUMS.txt` verifies every tracked Brand Kit file.

## Manual visual matrix

Review the generated boards `small-size-light` and `small-size-dark`, then check these surfaces:

| Surface | Sizes | Light | Dark | Check |
| --- | --- | --- | --- | --- |
| Mark | 12, 16, 24, 32, 64 px tall | ink baseline, ink blue cursor | paper baseline, `#4A6BFF` cursor | the gap between cursor and baseline stays open |
| Wordmark and lockups | 24 px and 64 px tall | yes | yes | `L` aligns with `erro`; letter spacing stays even |
| App Icon | 16, 32, 64, 128, 256, 512, 1024 px | default | default, dark, clear, tinted appearances | cursor and baseline stay two separate shapes at 16 px |
| Menu bar, 8 frames | 18 pt at 1× and 2× | template black | template white | each state differs from the others in a still frame |

Evidence is stored as `validation/small-size-light.png`, `validation/small-size-dark.png` and the compiled `AppIcon.icns` previews.

## Human checks on the signed app

- Verify template tinting of the eight frames in the real `NSStatusItem` on a light menu bar, a dark menu bar, selected and inactive states, and Increase Contrast.
- Verify the listening blink (0.525 s per frame) and processing draw (0.15 s per frame) timings, and that Reduce Motion stops both and shows `Listening` and `Processing4`.
- Verify App Icon appearance in Finder (list and icon views), Dock, Launchpad, System Settings permission panes and the quarantine prompt.
- Verify the sidebar wordmark, About page icon and Onboarding mark in light and dark appearance.
- Verify VoiceOver labels update with idle, listening, processing and error.
- Verify white text on the dark-appearance primary button (4.34:1) against the contrast notes in `guidelines/color-accessibility.md`.
