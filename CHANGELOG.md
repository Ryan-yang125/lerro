# Changelog

All notable changes to Lerro will be documented here. The project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and intends to use
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) for public releases.

## [Unreleased]

## [1.11.1] - 2026-10-25

### Changed

- The main window uses the macOS 26 window style with a toolbar: the corner
  radius matches the built-in apps, and the traffic lights sit on the same line
  as the page title.
- The sidebar, page titles, and page content line up at the same positions on
  every page, so nothing moves sideways when you switch pages.
- Icons, buttons, search fields, spacing, and corner radii use one set of sizes.

### Fixed

- In a narrow window, History details show the full time and status line. The
  Copy button shows only its icon there.

## [1.11.0] - 2026-10-24

### Changed

- A single-modifier shortcut (for example ⌘ alone) opens the microphone as soon
  as the key goes down, so speech right after the release is no longer cut off.
  When the press is part of another shortcut, that audio is dropped from memory.
  Bluetooth microphones keep opening after the release.
- History is stored in a SQLite database with full-text search. On first launch
  Lerro imports the existing history once and removes the old `history.json`.
  Saving a dictation writes one row, however long the history is.
- The capsule closes as soon as the text is pasted. Restoring the clipboard and
  saving history happen in the background.
- The main window has a fixed-width sidebar and switches pages faster. All four
  pages stay loaded, and keyboard focus stays on the visible page.

### Fixed

- Holding the single-modifier shortcut key while clicking the mouse, or for
  longer than one second, no longer starts a dictation on release.

## [1.10.2] - 2026-10-24

### Changed

- Interface text in Chinese and English is shorter and more consistent. For
  example, the Dictionary filters are "自动记住" / "Learned" and "手动添加" /
  "Added Manually", and the balance messages say what to do next.
- The microphone menu in the menu bar panel says "跟随系统" / "Follow System",
  the same as Settings.

### Removed

- The microphone level bars next to the microphone menu in Dictation settings.
- Support for reading preferences and history saved by Lerro 1.5 or earlier
  that still contain the Ask mode.

### Fixed

- Error messages in the capsule, and errors from the AI service, the clipboard,
  audio and CSV import, showed in Chinese while Lerro was set to English.
- Window titles stayed in the system language after changing Lerro's interface
  language.
- English counts read "1 dictations" and "Used 1 times".
- "Paste Last Result" wrapped onto two lines on the last onboarding step.

## [1.10.1] - 2026-10-22

### Changed

- Home has a flat background; the accent glow and the dot grid are gone.

### Fixed

- Shortcut keycaps in the Home toolbar stayed white after macOS switched to
  dark mode while Lerro was running.

## [1.10.0] - 2026-10-22

### Added

- AI cleanup (AI 整理) shows your DeepSeek balance in the sidebar and in
  Settings. When the balance runs out, Dictate writes the raw transcript and the
  capsule says why; Translate reports that the balance ran out.
- A three-step guide for getting a DeepSeek key (open the site, top up, create a
  key) in onboarding, in a sheet opened from Home, and in Settings. Pasting a
  key connects it automatically.
- A Home card that offers to turn on AI cleanup while no key is saved.

### Changed

- AI cleanup supports DeepSeek only. The model is fixed to `deepseek-flash` and
  the address to `https://api.deepseek.com`; the provider, model, address and
  price settings are gone. Saved OpenAI, Gemini and custom provider settings are
  not migrated, and their keys are dropped. A saved DeepSeek key is kept.
- Settings has five tabs: General, Dictation, AI 整理, Privacy, About. Usage
  details moved into the AI 整理 tab and show costs from the built-in CNY prices.
- Onboarding has four steps: welcome and permissions, try it once, AI cleanup,
  start. All user-facing names for the AI features now read "AI 整理".
- Translation has one target language instead of an ordered list.
- Fixtures: `LERRO_FIXTURE_ONBOARDING_STEP` takes `welcome`, `practice`, `ai`,
  `start`; settings presentations are `settings-general`, `settings-dictation`,
  `settings-ai`, `settings-ai-usage`, `settings-privacy`, `settings-about`; the
  new `LERRO_FIXTURE_AI` takes `connected`, `no-balance`, `off`.

### Removed

- The microphone level test and the correction-learning exercise in onboarding.

## [1.9.3] - 2026-10-22

### Added

- Terms the AI corrects in two separate dictations are added to the dictionary
  automatically. Each one shows where it came from and what it was misheard as,
  and can be removed. The Home page shows what Lerro learned this week, and
  dictionary words are counted as they are used.

### Removed

- Dictionary snippets (快捷语). Saying a short phrase no longer pastes a stored
  text; existing entries with a different replacement are sent to the AI as word
  mappings.
- “Find Words in History” and the Suggestions tab on the Dictionary page. It sent
  one AI request per difference in your history and produced noisy suggestions,
  such as single characters and changes that reversed the meaning. Words you
  correct after dictation are still learned automatically.

## [1.9.2] - 2026-10-21

### Fixed

- The start sound no longer goes missing after the Mac has been idle. With
  lowering other audio enabled, Lerro now waits for the start sound to finish
  before muting the output; the microphone still opens right away.

### Removed

- Dictionary snippets (快捷语). Saying a short phrase no longer pastes a stored
  text; existing entries with a different replacement are sent to the AI as word
  mappings.
- The “Stop automatically when you finish speaking” setting. It relied on Apple's
  speech detector, which reports nothing in practice, so it never ended a capture.

## [1.9.1] - 2026-10-20

### Changed

- New versions are easier to notice. Lerro checks every 4 hours. When you are
  using Lerro, the update window opens; when Lerro is in the background, the menu
  bar icon gets a dot, the menu bar panel starts with “Update to …”, and the main
  window sidebar shows a new-version card. Downloading still starts only when you
  click.

## [1.9.0] - 2026-10-20

### Added

- History shows what the AI did for each dictation: the words it corrected and the
  fragments it removed, what it was sent (your words, app, dictionary terms, tone,
  and which context was not sent), and what the call cost with the calculation.
  The exact request and reply are one click away.
- Settings › Usage lists every AI call with its cost; selecting one opens the
  matching history entry.
- Settings › Intelligence › Prompts shows the dictation, translation and
  dictionary-learning prompts section by section, with the examples as cards. The
  prompts are read-only.

### Fixed

- A collapsed sidebar can be shown again: the main window has the standard
  sidebar button next to the window controls, and View › Show Sidebar (⌃⌘S).

## [1.8.0] - 2026-10-19

### Changed

- Sidebar, Settings and menu bar icons use SF Symbols.
- Home is a usage dashboard: total characters, time saved, speaking speed,
  dictation time and count with today's increase, a year of activity as a
  heatmap with streaks, most-used apps, and the hours you dictate most. Recent
  dictations and learned terms stay on the History and Dictionary pages. Daily
  totals are kept in `usage-days.json`, so the heatmap does not depend on how
  long history is kept; existing history seeds it once.

### Added

- Short start and stop sounds mark the beginning and end of a capture. Turn them
  off in Settings › General › Sounds. With lowering other audio enabled, output
  audio now returns when the microphone closes, before the final transcript.

## [1.7.2] - 2026-10-19

### Added

- The website download is a signed and notarized disk image. Opening it shows
  Lerro next to the Applications folder on a branded background; drag Lerro
  across to install. In-app updates keep using the ZIP archive.

## [1.7.1] - 2026-10-19

### Removed

- Dictionary snippets (快捷语). Saying a short phrase no longer pastes a stored
  text; existing entries with a different replacement are sent to the AI as word
  mappings.
- The local AI mode (Qwen through MLX), its 3.03 GB model download, device-aware
  recommendations, and the vendored Hugging Face packages. AI polish and
  translation use the API you configure. A saved local mode loads as Apple-only.
- The data migration from the pre-Lerro app identity and the unused rule-based
  text pipeline.

### Changed

- The app archive is about 4 MB, down from 11.7 MB.
- Development happens in the public repository; the private mirror, export and
  scan scripts are gone. CI is one Linux job for scripts, documentation links,
  Python tests and the website; Swift builds, tests and packaging run locally in
  `script/verify_release.sh`.
- Documentation is reduced to `docs/architecture.md`, `docs/development.md` and
  the current decision records.

## [1.7.0] - 2026-10-19

### Added

- The Dictionary page has a 建议 view. 从历史找词 compares the raw and AI-polished
  text of past dictations, asks the selected AI which changes are recognition
  corrections, and lists them with how often they occurred. Each suggestion can
  be added to the dictionary or ignored; nothing is added automatically.

- Every capture records a monotonic timeline from the physical key press through
  permissions, context capture, Speech resource wait, each Apple Speech startup
  step, listening, first audio, first partial, transcription, AI processing,
  Command-V commit, clipboard restore, and history save. Cancelled, failed, and
  raw-fallback captures record the outcome and the last step reached.
- The timeline is logged to `app.lerro.mac` / `capture-trace` in milliseconds with
  signpost intervals for Instruments, and completed or delivery-failed history
  entries store it in `phaseTimings.milestones`. Logs carry step names and
  numbers only.
- History detail shows the time from key press until speech is captured.
- `script/capture_latency_report.py` reads history read-only and prints p50, p90,
  and max per step plus the slowest captures.
- Settings → 用量 shows remote AI tokens, requests, and estimated cost for today,
  7 days, and 30 days, a daily chart, and breakdowns by feature and model. Each
  remote call stores time, feature, provider, model, token counts, latency, and
  success in `ai-usage.json` for 90 days. Prices are built in for DeepSeek with
  off-peak discounts and can be edited per model.

### Fixed

- In dark mode the Home toolbar no longer keeps a lighter background after launch.
  Home uses one scroll view for its empty and loaded states, so the toolbar sees
  the same content from the first frame.

- Dictation no longer fails with 语音资源暂未就绪 until the app restarts. Apple's
  asset status could report the installed language as missing while transcription
  still worked; the check now relies on `SpeechTranscriber.installedLocales`.

- The app picker for app tones lists only real apps: background agents and helper
  processes are gone. Apps are grouped into 常用 (most dictated, from history),
  正在运行, and 全部应用, and each row shows the icon and name.

- The microphone opens before the speech analyzer is prepared, so the first words
  of a dictation are no longer cut off. Audio captured while the analyzer prepares
  is buffered and transcribed in order. An idle audio engine is kept ready between
  captures without starting the microphone.

- Apple Speech resources prepare automatically at launch, on language changes,
  and before capture. Onboarding can be closed at any step, preserves completed
  setup when reopened, and recognizes existing learned dictionary entries.
- Dictionary onboarding shows progress only during an AI request, reports rejected
  corrections and failures, supports cancellation and practice reset, and accepts
  an already learned term without creating a duplicate.

### Changed

- Product icons are a Lerro glyph set: thin rounded strokes on a 16 pt grid, with
  the ink-blue cursor from the logo in 听写, 智能润色, 首页, 词典 and 关于. The
  AI icon is a wavy line becoming a straight line with a cursor instead of
  sparkles. Generic SF Symbols are outline only, except status icons and media
  controls.

- The menu bar icon opens a branded panel: status with a recording timer, 听写
  and 翻译 buttons with their shortcuts, the last result with copy and paste,
  today's dictations, words and AI cost, and native pickers to switch the
  microphone and intelligence mode. Actions return focus to the previous app
  first. 重新查看引导 moved to Settings → 关于.

- The remote Dictate prompt (`J_input_method_fixes_json_v1`) treats the transcript
  as a phonetic draft and, like an input method, replaces words that are not real
  or do not fit the sentence with same- or similar-sounding words. The model lists
  its word fixes before the final text in a JSON reply. On recent dictations it
  fixed 6 of 8 misrecognitions versus 2 of 8, with the same benchmark formatting
  and about 0.05 s more latency; thinking mode stays off.

- Automatically learned dictionary entries are saved globally instead of being
  scoped to the app where they were learned.

- Live transcription uses Apple SpeechTranscriber instead of DictationTranscriber.
  On 40 real recordings it recognized 62% of English words in mixed
  Chinese–English speech versus 39%, and it no longer drops whole phrases. Spaces
  around Chinese punctuation are removed. SpeechTranscriber ignores contextual
  strings, so dictionary terms are no longer sent to Apple Speech; they still reach
  AI polish.

- The remote Dictate prompt treats the transcript as speech recognition output and
  corrects misheard words and phrases when context or the dictionary makes the
  intended wording clear. Remote requests also send up to 40 dictionary terms as
  `personalization.known_terms` while the dictionary context toggle is on, even when
  the terms do not appear in the transcript. The prompt version is
  `M_balanced_eight_shot_asr_v1` with eight examples.
- Remote model calls no longer use streaming; the unused streaming path was removed.
- The DeepSeek preset model is `deepseek-flash`. DeepSeek retired `deepseek-v4-flash`
  and routes it to `deepseek-flash` at the same price.
- The capture HUD is one ink-black glass capsule that morphs between states:
  an ink-blue cursor and audio waveform while recording, a single line of live
  text with the target app icon, and "AI 润色中…" or "翻译中…" while processing.
  The capsule looks the same in light and dark appearance.
- Successful insertion fades the HUD at the Command-V commit point. When AI
  processing fails and the raw transcript is written, an orange notice says so.
- Recording shows the microphone name after three seconds without speech, an
  elapsed timer after five seconds, and the stop key during the first twenty
  hands-free captures.
- The HUD appears on the screen that holds the focused text field.
- Recovery and dictionary-learning notices live inside the same capsule; the
  learning notice stays three seconds and pauses while hovered.
- New brand: a cursor standing on a baseline forms the L of Lerro. The app icon
  is a layered macOS 26 Icon Composer icon, the sidebar shows the new wordmark,
  About shows the app icon, and onboarding opens with the mark.
- The menu bar icon blinks its cursor while recording and draws its baseline
  while processing; Reduce Motion keeps it still.
- The main window is rebuilt on a native `NavigationSplitView`. The sidebar lists
  Home, History, Dictionary, and App Tones with count badges, plus the AI status,
  a settings button, and the version. Personalization is renamed App Tones.
- Home shows today, seven-day, and all-time usage, a seven-day bar chart, the
  capture shortcuts, a microphone menu, the six most recent captures, and
  recently learned words.
- History opens a detail view with Result, Compare, and Original tabs (word-level
  diff against the raw transcript), a phase timing bar, the context sent to AI,
  and playback of saved recordings.
- Dictionary uses a native table, marks words learned in the last seven days as
  new, and imports and exports CSV as `phrase,replacement`.
- App Tones adds a default tone that applies when no enabled app tone matches the
  frontmost app, and the editor previews a tone on a custom sample sentence.
- Settings moved from an in-window overlay to a standard Settings window (Command-,)
  with General, Shortcuts, Intelligence, Privacy, and About tabs.
- The accent color is ink blue (`#2F5BFF` light, `#4A6BFF` dark) and is compiled
  into the app's `AccentColor`, so system controls, selection, and toggles use it.
  The main window type scale is 15 / 13 / 16 / 30 / 12 / 11 pt.
- Fixtures select a main window page with `LERRO_FIXTURE_DESTINATION` and open a
  settings tab with `LERRO_FIXTURE_PRESENTATION=settings-<tab>`; the previous
  settings fixture names are removed.

## [1.6.0] - 2026-08-13

### Added

- AI-assisted automatic dictionary learning observes a user's focused correction,
  classifies proper-name or terminology fixes, and saves up to three app-scoped
  terms with an immediate Undo action.
- Apple Dictation receives up to 100 relevant personal-dictionary terms through
  the progressive DictationTranscriber context.
- A first-level Personalization page presents app tones in an icon grid with
  installed-app search and real AI previews.
- An eight-step, action-gated onboarding covers privacy, Apple Speech resources,
  AI setup, shortcuts, real dictation, insertion recovery, dictionary learning,
  and app tones.

### Changed

- The live transcript HUD now grows smoothly from a centered compact capsule to
  a two-line 420-point card while preserving the current waveform transition.
- Successful insertion ends immediately. Focus drift or insertion failure copies
  the final text and presents a recovery card with Copy Again and Close actions.
- New installs begin with Apple Dictation. Remote AI follows it in setup order,
  with local AI last and guided by device capability checks.
- Translate uses the selected remote or local AI runtime. Quick Dictate remains
  optional and is disabled by default.

### Removed

- Dictionary snippets (快捷语). Saying a short phrase no longer pastes a stored
  text; existing entries with a different replacement are sent to the AI as word
  mappings.
- Ask and Rewrite production entry points, shortcuts, cards, and onboarding pages.
- The six-second success receipt, post-delivery Undo and correction controls,
  spoken follow-up editing, redictation, version restore, and voice send.

## [1.5.1] - 2026-08-11

### Added

- A nine-step first-run guide that teaches AI setup, permissions, shortcuts,
  Quick Dictate, delivery receipts, spoken follow-up editing, and the complete
  voice toolkit.
- Device-aware local-AI guidance based on Apple silicon, Metal, memory, and free
  storage, with inline OpenAI-compatible API setup and connection testing.
- Pause, resume, background progress, transferred bytes, and stop controls for
  the local model download.

### Changed

- Quick Dictate remains immediately usable through Apple Speech while an
  approved local model downloads or stays paused.
- Local model cancellation now preserves URLSession resume data and a restart-
  safe checkpoint; stopping clears only incomplete artifacts.

## [1.5.0] - 2026-08-10

### Added

- Quick Dictate starts from one Fn press and finishes after speech followed by
  about 1.2 seconds of silence.
- A spoken follow-up can modify the most recent focus-bound delivery with local
  Undo, sentence deletion, exact replacement, or a semantic model instruction.
- Delivery edits keep a version chain so repeated changes can restore the prior
  version while preserving the original history entry.

### Changed

- The delivery receipt now introduces spoken follow-up editing alongside the
  existing focus-safe Undo, manual correction, and confirmed voice-send actions.
- History records the delivered text version lineage for review without storing
  additional focused-field content.

## [1.4.0] - 2026-08-10

### Added

- A live two-line transcript HUD with the current target app and stable versus
  progressive Speech state.
- A six-second delivery receipt with focus-safe Undo, immediate correction,
  correction learning, and explicit first-use voice-send confirmation.
- Per-app voice-send approvals for hands-free Dictation ending in “发送” or
  “send it”, with terminal, search, address, secure, and unknown targets denied.
- History receipts for processing route, captured context categories, remote
  context sharing, voice-send state, and recording/transcription/processing/
  delivery timings.

### Changed

- History correction now preserves raw, processed, and corrected text lineage.
- Text delivery now returns a one-time receipt bound to the target process,
  bundle, focused element, focused value, and secure-input state.

## [1.3.0] - 2026-08-10

### Added

- App-specific writing styles selected from running macOS applications and
  frozen with each capture.
- Exact spoken snippets that expand locally from the personal dictionary.
- A correction workflow that updates history and learns app-scoped terms.
- A fixed 60-case contextual-dictation benchmark with repeatable accuracy,
  formatting, protected-span, and latency scoring.
- A zero-history Claude Code and Codex workspace entry with one canonical
  development skill, task-to-document routing, maintainer readiness probes,
  release evidence templates, and an end-to-end local validation and publication
  workflow.

### Changed

- Renamed the user-facing Ask action to Command and assigned `Fn Space` as its
  first-run shortcut.
- Commands now transform any captured selection with the spoken instruction;
  commands without a selection continue to stream an answer card.
- Replaced the synthetic personalization percentage with exact dictionary,
  learned-correction, and enabled app-style counts.
- Extended remote Provider request and resource deadlines to cover measured
  production-generation latency while preserving cancellation.

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

[Unreleased]: https://github.com/Ryan-yang125/lerro/compare/v1.10.1...HEAD
[1.10.1]: https://github.com/Ryan-yang125/lerro/compare/v1.10.0...v1.10.1
[1.10.0]: https://github.com/Ryan-yang125/lerro/compare/v1.9.3...v1.10.0
[1.9.3]: https://github.com/Ryan-yang125/lerro/compare/v1.9.2...v1.9.3
[1.9.2]: https://github.com/Ryan-yang125/lerro/compare/v1.9.1...v1.9.2
[1.9.1]: https://github.com/Ryan-yang125/lerro/compare/v1.9.0...v1.9.1
[1.9.0]: https://github.com/Ryan-yang125/lerro/compare/v1.8.0...v1.9.0
[1.8.0]: https://github.com/Ryan-yang125/lerro/compare/v1.7.2...v1.8.0
[1.7.2]: https://github.com/Ryan-yang125/lerro/compare/v1.7.1...v1.7.2
[1.7.1]: https://github.com/Ryan-yang125/lerro/compare/v1.7.0...v1.7.1
[1.7.0]: https://github.com/Ryan-yang125/lerro/compare/v1.6.0...v1.7.0
[1.2.0]: https://github.com/Ryan-yang125/lerro/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/Ryan-yang125/lerro/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/Ryan-yang125/lerro/compare/v1.0.3...v1.1.0
[1.0.3]: https://github.com/Ryan-yang125/lerro/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/Ryan-yang125/lerro/compare/v1.0.1-preview.1...v1.0.2
[1.0.1-preview.1]: https://github.com/Ryan-yang125/lerro/releases/tag/v1.0.1-preview.1
