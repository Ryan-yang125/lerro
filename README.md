<p align="center">
  <img src="site/public/lerro-logo.svg" width="176" alt="Lerro">
</p>

<h1 align="center">Voice to text, native to Mac.</h1>

<p align="center">
  English · <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  Press once, speak, then press again. Lerro writes at your cursor with Apple Speech on macOS 26.<br>
  Fast, accurate voice writing that keeps its core work on your Mac.
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

## One shortcut. A clear path to text.

Press a shortcut to start, speak naturally, then press it again to place the
result in the active app. Configure press-and-hold when releasing the key is the
completion gesture you prefer.

| Mode | What it does | Where it runs |
| --- | --- | --- |
| **Dictate** | Speech → text at the cursor | Apple Speech on your Mac |
| **Translate** | Speech → another language → cursor | Apple Translation on your Mac |
| **Command** | Transform selected text or answer with current app context | Optional local MLX model or your own API |

Lerro 1.3 adds app-specific writing styles, exact spoken snippets, and a
correction loop that learns app-scoped terms. Command uses **Fn Space** by
default. With text selected, the spoken instruction transforms that selection;
without a selection, Lerro streams an answer card.

![Lerro shortcut setup](https://lerroapp.com/screenshots/en/lerro-onboarding-shortcuts-light.png)

Lerro asks for **Microphone** permission to capture speech and
**Accessibility** permission for global shortcuts and text delivery. It checks
secure input before capture. Standard Dictate and Translate paste into the
keyboard focus present when delivery is committed; Rewrite verifies the original
selection again before replacing it.

## Private by default

- **Your voice and text stay local for core workflows.** Raw Dictate uses Apple
  Speech, and Translate uses installed Apple Translation resources. After their
  required language resources are ready, these paths work offline.
- **Audio saving starts off.** Choose whether history is retained; selecting
  “never save” prevents new history and recordings from being written.
- **No telemetry.** Lerro has no account system, subscription, advertising SDK,
  product analytics, or server-side storage for transcripts, prompts, and
  answers.
- **Clear optional network boundaries.** Apple may download language resources;
  Lerro checks signed updates; an optional MLX model downloads only after your
  approval; BYOK requests go directly to the provider you configure.

Read the exact data, permission, clipboard, update, and provider boundaries in
the [Privacy Policy](PRIVACY.md).

![Lerro settings](https://lerroapp.com/screenshots/en/lerro-settings-light.png)

## Start with the native path. Add intelligence when useful.

The core Dictate and on-device Translate workflows carry no Lerro charge and
need no account. An optional Qwen MLX model refines text locally after you
approve its approximately 3.03 GB download. You can also use your own
OpenAI-compatible API configuration for cloud processing. BYOK requests can
include the transcript and only the context fields you enable; provider pricing
and privacy terms apply.

## Install

1. [Download the latest signed and Apple-notarized build](https://updates.lerroapp.com/download/macos/latest).
2. Move **Lerro.app** to Applications.
3. Complete the guided Microphone and Accessibility setup.
4. Choose Dictate first, then add translation resources, a local model, or BYOK
   only when you want those capabilities.

Requirements: Apple silicon and macOS 26 or later. The optional local model
needs about 3.03 GB of storage.

## Open source and documentation

Lerro is open source under [Apache-2.0](LICENSE). Product, release, privacy,
and engineering documentation live in this repository:

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
