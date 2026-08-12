<p align="center">
  <img src="site/public/lerro-logo.svg" width="176" alt="Lerro">
</p>

<h1 align="center">Voice to text, native to Mac.</h1>

<p align="center">
  English · <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  Press your shortcut, speak with a live centered preview, then press it again to write.<br>
  Apple Speech works immediately; optional local or BYOK AI adds refinement and personalization.
</p>

<p align="center">
  <a href="https://updates.lerroapp.com/download/macos/latest"><strong>Download for macOS</strong></a>
  · <a href="https://lerroapp.com">Website</a>
  · <a href="https://lerroapp.com/changelog">Changelog</a>
</p>

<p align="center">
  Apple silicon · macOS 26+ · No account · No subscription
</p>

![Lerro home screen](https://lerroapp.com/screenshots/en/lerro-home-light.png)

## One shortcut. One complete writing flow.

1. Press your configured shortcut.
2. Speak while the centered HUD previews the live transcript.
3. Press the same shortcut again.
4. Lerro writes to the captured field and the HUD disappears.

The HUD grows smoothly from a compact waveform capsule to a two-line transcript.
If focus or the target field changes before delivery, Lerro stops the write,
keeps the final text on the clipboard, and offers **Copy again**.

| Capability | Runtime |
| --- | --- |
| **Transcription** | Apple Speech on your Mac |
| **Dictionary-aware recognition** | Apple Speech with up to 100 relevant terms |
| **Refinement and translation** | Optional local MLX model or your API |
| **Automatic correction learning** | Optional local MLX model or your API |
| **Per-app tone** | Optional local MLX model or your API |

Quick Dictate is an optional setting. It ends a recording after about 1.2 seconds
of continuous silence and starts disabled.

![Lerro shortcut setup](https://lerroapp.com/screenshots/en/lerro-onboarding-shortcuts-light.png)

## A dictionary that learns from real corrections

After AI-processed Dictate writes text, Lerro can observe edits to that exact
field for up to 60 seconds. A stable edit is reduced to the smallest changed
span and classified by the selected local or remote AI. Names, brands,
technical terms, spelling, homophones, transliterations, and mixed-language
proper nouns can become app-scoped dictionary entries. Semantic changes and
large rewrites are ignored.

The same dictionary supports Apple Speech recognition, local and remote AI
prompts, manual editing, CSV import, app filtering, and promotion to global
scope. Learned entries show a lightweight undoable notification.

## Personalization at the top level

Home, History, Dictionary, and Personalization are first-level destinations.
Personalization presents installed and running apps in a searchable grid with
real app icons. Each app can have an AI tone instruction and a real preview
before saving.

## Private by default

- Raw Dictate uses Apple Speech. Audio saving starts off.
- History can be disabled; “never save” prevents new history and recordings.
- Lerro has no account, analytics, advertising SDK, or transcript service.
- Local AI downloads only after explicit consent and runs on the Mac.
- BYOK traffic goes directly to the provider and endpoint you configure.
- Automatic correction learning ends quietly when AI, Accessibility, the target
  field, or the observation window is unavailable.

Read the exact data, permission, clipboard, update, and provider boundaries in
the [Privacy Policy](PRIVACY.md).

![Lerro settings](https://lerroapp.com/screenshots/en/lerro-settings-light.png)

## Guided setup through real actions

Onboarding walks through privacy choices, Apple Speech resources and microphone
testing, AI selection, shortcut recording, a real Dictate insertion, clipboard
recovery, correction learning, and per-app tone. Apple-only users finish after
the recovery exercise. A local-model download can continue in the background
and supports pause, resume, stop, and restart continuation.

## Install

1. [Download the latest signed and Apple-notarized build](https://updates.lerroapp.com/download/macos/latest).
2. Move **Lerro.app** to Applications.
3. Complete the guided Microphone, Accessibility, shortcut, and Dictate tasks.
4. Add local or BYOK AI when you want refinement, translation, automatic
   learning, and per-app tone.

Requirements: Apple silicon and macOS 26 or later. The default optional local
model needs about 3.03 GB of storage.

## Open source and documentation

Lerro is open source under [Apache-2.0](LICENSE).

- [Architecture](docs/architecture.md)
- [Core flow](docs/core-flow.md)
- [Models and BYOK](docs/models.md)
- [Privacy and security](docs/privacy-security.md)
- [Build and testing](docs/build.md)
- [Contextual benchmark](benchmarks/README.md)
- [Contributing](CONTRIBUTING.md)

See [TRADEMARKS.md](TRADEMARKS.md), [NOTICE](NOTICE), and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for brand and third-party
notices. First-party documentation and screenshots use
[CC BY 4.0](LICENSES/CC-BY-4.0.txt).
