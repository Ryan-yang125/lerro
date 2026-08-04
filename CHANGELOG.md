# Changelog

All notable changes to Lerro will be documented here. The project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and intends to use
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) for public releases.

## [Unreleased]

## [1.2.0] - 2026-08-04

### Added

- English and Simplified Chinese App interfaces with a system-following default
  and an explicit display-language setting.
- English and Simplified Chinese website routes, changelogs, metadata, and
  language-specific product screenshots served from the Cloudflare site.
- A Simplified Chinese product README paired with the English GitHub landing
  page and matching localized App screenshots.

### Changed

- Separated the App interface language from Speech recognition and Translation
  language choices.
- Reworked public product copy across the App, website, and GitHub around native
  macOS 26 Speech, local-first privacy, optional local MLX processing, and BYOK.
- Moved every public product screenshot onto version-controlled website assets
  so the website and GitHub README share stable Cloudflare URLs.

## [1.1.1] - 2026-08-04

### Fixed

- Aligned Fn and Globe interception with a physical-key state model: built-in
  Fn and external Globe key codes are tracked independently, every owned event
  is consumed through release, and unchanged aggregate modifier flags can no
  longer leak to the macOS Emoji and Symbols action.
- Limited the global event tap to keyboard down, keyboard up, and modifier
  changes so pointer, scroll, and system-defined events stay outside shortcut
  recognition.
- Kept owned key sequences intact across shortcut resets, Secure Input
  recovery, full event-tap reconstruction, and Fn-prefix upgrades.
- Excluded the private Cloudflare Wrangler configuration from clean public
  exports and made the public scanner reject it explicitly.
- Skipped R2 Data Catalog prompting for binary release archives after Wrangler
  4.118.0 produced empty successful uploads, while retaining mandatory
  SHA-256 readback before the stable channel can advance.

## [1.1.0] - 2026-08-04

### Added

- Traditional Apple Translation for device-side Translate sessions on macOS
  26, with explicit Speech and Translation resource preparation states.
- A visible blue download affordance when Sparkle discovers an update.
- A concise website changelog with immutable downloads for every published
  version.
- A product-focused website and README with current v1.1 screenshots, an
  animated web recreation of the native HUD, and a GitHub Release mirror.

### Changed

- Reduced the core permission flow to Microphone and Accessibility.
- Made Fn and Fn-Shift toggle shortcuts the clean defaults, with an active HID
  event tap that owns configured modifier gestures through release.
- Refined onboarding and shortcut settings around Dictate and Translate action
  cards, tap-or-hold selection, physical press feedback, and conflict guidance.
- Translation now bypasses local and remote language models in every
  intelligence mode.
- The idle capture HUD is fully hidden and no longer exposes a hover target.
- Strengthened Apple Speech handling for live range replacement, CJK and Latin
  spacing, audio-buffer ownership, overflow failures, and converter tail flush.
- Aligned the website with Motion Lexicon's Interior material, typography,
  interaction, contrast, transparency, and reduced-motion system.

### Fixed

- Kept standard R2 validation enabled during immutable archive uploads; the
  publication script continues only after a SHA-256 readback matches the
  packaged release manifest.
- Re-checks Accessibility immediately before Command-V so revoked access
  restores the clipboard and records a recoverable delivery failure.

## [1.0.3] - 2026-08-02

### Changed

- Advanced the public macOS release to build 5 and completed the first
  production Sparkle update path from Lerro 1.0.2 (build 4).

## [1.0.2] - 2026-08-02

### Added

- Sparkle 2 automatic updates with a signed HTTPS appcast, a daily background
  check, automatic download, install on quit, and immediate in-app checks from
  Home and Settings.
- Cloudflare Worker distribution at `lerroapp.com` and `updates.lerroapp.com`,
  backed by private R2 release archives and a private D1 stable-release index.
- Release packaging and verification for embedded Sparkle helpers, arm64
  linkage, Ed25519 archive signatures, and public release metadata.
- Controlled Cloudflare publication script with ZIP readback, D1 release batch,
  and public appcast/download verification.

### Changed

- Official website and direct macOS download now use `https://lerroapp.com` and
  `https://updates.lerroapp.com/download/macos/latest`.
- The Home and Settings update actions now open Sparkle's native updater flow.

### Security

- Public ZIPs are Developer ID signed, notarized, stapled, Gatekeeper-validated,
  and signed with the Sparkle Ed25519 archive key held only in the maintainer
  Keychain.
- Update checks and downloads contain no speech, transcript, focused text,
  dictionary, prompt, model answer, or provider API key data.

## [1.0.1-preview.1] - 2026-08-01

### Added

- Independent Lerro product, target, bundle, data-path, logging, and release
  identities.
- Apple-native visual system, app icon, menu-bar states, and product copy.
- Idempotent migration for compatible local settings, history, dictionary,
  recordings, and model cache data.
- Apache-2.0 project license, governance files, public documentation, issue and
  pull-request templates, and an allowlist-driven clean export workflow.
- Local Release gates for signing, checksums, source manifests, architecture,
  resources, licenses, and isolated launch verification; the public-distribution
  checklist records the remaining Developer ID, notarization, SBOM, and
  artifact-attestation gates.
- Live shortcut recording for Fn, Control, Option, Shift, Command and supported
  chords, with explicit hold-to-talk and tap-to-toggle modes in onboarding and
  settings, repeatable press/release feedback, and up to four editable bindings
  per action.
- BYOK DeepSeek, OpenAI, Gemini, and custom OpenAI-compatible text processing,
  including connection testing, provider routing, bounded context, and local
  JSON configuration.
- A responsive Lerro product website with privacy, permission, model-mode,
  onboarding, download, and source-code guidance.
- A dedicated Intelligence settings surface with prominent Raw, Local AI, and
  API modes, local-model preparation status, Provider controls, and context
  sharing choices.

### Changed

- Replaced the custom menu-bar window with a native macOS menu, restoring
  full-row hit targets, system highlighting, keyboard navigation, and menu dismissal.
- Refined the capture HUD with an immediate, lightweight three-dot processing
  indicator across transcription, local/API enhancement, and pre-commit text
  delivery, including a static Reduce Motion presentation.
- Main product surfaces use an adaptive monochrome palette with explicit Aqua,
  Dark Aqua, and Increase Contrast values. System colors remain reserved for
  success, warning, and error states.
- Main-window typography now follows a 24/14/13/12-point scale with -0.15
  tracking. Navigation uses 14-point icons and 8-point corners; cards use
  20-point icons and 16-point corners; primary calls to action use pill shapes.
- The capture waveform now uses real audio energy, migrating pulses, neighbor
  diffusion, and independent decay for a more organic response; capture start,
  completion, and error feedback remain silent.
- Main-window controls use 150 ms hover feedback and move down by one point on
  pointer-down. Reduce Motion removes the displacement and preserves clear
  opacity feedback. The capture HUD keeps its existing shell, waveform,
  processing, state transitions, and silent feedback.
- Idle pointer and scroll traffic bypasses global-hotkey system probes; settings
  apply appearance, Dock, and hotkey effects only when their fields change.
- History and dictionary views reuse one derived collection per render, and
  menu-bar template images are decoded once per process.
- History now loads repository-backed 50-entry pages with cancellable search,
  stable ordering, automatic continuation, cached JSON snapshots, compact
  persistence, coordinated multi-instance writes, and no-op retention writes removed.
- Public documentation centers on Lerro's architecture, privacy, permissions,
  local and API models, build, release, and contribution workflows.
- Model-backed paths now receive the original Apple Speech transcript. Raw mode
  delivers that transcript directly, and remote Dictate falls back to it when a
  Provider request fails.

### Fixed

- Ask now opens as an interactive key panel without requesting main-window
  ownership, preventing the AppKit assertion and secondary Swift executor crash
  that occurred immediately after recording stopped. HUD tracking now hops onto
  the main actor instead of using an unchecked executor assumption.
- Capture HUD feedback now appears in the shortcut event turn, keeps a live
  waveform throughout recording, enters processing synchronously on stop, and
  hides as soon as delivery completes; high-frequency audio and timer updates
  no longer reposition the floating panel.
- Shortcut recording now starts as soon as its sheet or onboarding step is
  ready, receives modifier changes through a window-scoped AppKit event monitor
  regardless of first-responder focus, and reads character data only from
  ordinary key events.
- Ordinary cross-application insertion now follows the keyboard focus present at
  the Command-V commit point and restores a best-effort clipboard archive after
  the target app consumes the paste.
- Selection-aware Rewrite binds to the captured app and selection, revalidates
  secure-input and focus state before Command-V, and restores the complete
  ordered pasteboard only while the session still owns its temporary marker.
- Global shortcut refreshes now preserve a held key through permission checks;
  matched regular keys are swallowed through key-up, and hold release is bound
  to the definition that started the capture.
- Modifier candidates preserve their peak chord through progressive release,
  active Fn prefixes upgrade to configured Fn+Shift/Fn+Space actions, and
  generated delivery events bypass the shortcut filter with a source marker.
- Shortcut changes wait for confirmed local persistence before onboarding or
  settings advances, and physical aliases share one conflict signature.
- Shortcut configuration invalidates stale queued triggers, active capture
  blocks binding mutation, alternate toggle bindings can complete the same
  action, and Secure Input recovery reprocesses a fresh first key-down.
- Secure Input recovery now survives watchdog-first ordering and distinguishes
  same-class left/right modifier releases through physical key state.
- Accessibility and Input Monitoring now gate event-tap startup together;
  revoking either permission safely cancels active capture before monitor stop.
- Legacy hands-free bindings migrate to explicit toggle actions, while
  unrelated queued preference changes no longer create a false save error.
- Capture cleanup now preserves hold FIFO and toggle parity, explicit cancel
  clears queued restarts, programmatic startup keeps one generation, and
  removed bindings invalidate their already-queued triggers.

### Security

- Public export scans reject local paths, credentials, signing identities,
  private artifacts, unapproved legacy-brand references, and binary build
  outputs.
- Application Support and preferences use owner-only permissions before storing
  plaintext BYOK credentials; logs, history, errors, fixtures, and public exports
  exclude API keys and Authorization headers.

[Unreleased]: https://github.com/Ryan-yang125/lerro/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/Ryan-yang125/lerro/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/Ryan-yang125/lerro/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/Ryan-yang125/lerro/compare/v1.0.3...v1.1.0
[1.0.3]: https://github.com/Ryan-yang125/lerro/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/Ryan-yang125/lerro/compare/v1.0.1-preview.1...v1.0.2
[1.0.1-preview.1]: https://github.com/Ryan-yang125/lerro/releases/tag/v1.0.1-preview.1
