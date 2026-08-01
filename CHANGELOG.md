# Changelog

All notable changes to Lerro will be documented here. The project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and intends to use
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) for public releases.

## [Unreleased]

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

[Unreleased]: https://github.com/Ryan-yang125/lerro/compare/v1.0.1-preview.1...HEAD
[1.0.1-preview.1]: https://github.com/Ryan-yang125/lerro/releases/tag/v1.0.1-preview.1
