# Lerro

**Speak freely. Write clearly.**

[Website](https://lerro.pages.dev) ·
[Download the macOS preview](https://github.com/Ryan-yang125/lerro/releases)

Lerro is a local-first voice-writing app for macOS with optional BYOK cloud
processing. Hold a global shortcut, speak naturally, and deliver a clear result
to the current text cursor. Dictate, Translate, Ask, Rewrite, history, personal
dictionary, and Hands-free share one native session pipeline.

## Highlights

- Native SwiftUI and AppKit experience for macOS 26.
- Apple Speech transcription with secure-field and focus checks.
- Optional on-device MLX processing after explicit model-download consent.
- DeepSeek, OpenAI, Gemini, and custom OpenAI-compatible processing with a
  user-supplied API key.
- Transaction-safe current-focus Command-V delivery, with strict Accessibility checks for Rewrite.
- Local history, dictionary, JSON preferences, optional recordings, and model cache.
- Global Fn gestures, non-activating capture HUD, and interactive Ask panel.
- Apple-native visual system using semantic colors, system typography,
  materials, accessibility settings, and standard controls.
- Reproducible local Release gates for signing, checksums, source metadata,
  licenses, architecture, resources, and isolated launch checks.

## Architecture

```text
Lerro -> LerroIntelligence -> LerroCore
   |                           ^
   +----------> LerroMac ------+
```

- `LerroCore` contains domain models, protocols, rules, persistence, and
  deterministic text processing.
- `LerroIntelligence` owns MLX model download, loading, and generation.
- `LerroMac` owns AVFoundation, Speech, Accessibility, CGEventTap, permissions,
  panels, login items, and lifecycle integration.
- `Lerro` owns SwiftUI scenes, the design system, dependency composition, and
  `AppSession` orchestration.

Every capture receives a generation and session identity. Results from an older
operation cannot update a newer capture. Ordinary insertion commits to the
current keyboard focus; selection-aware Rewrite revalidates the original app,
selection, and secure-input state immediately before writing.

## Requirements

The exact platform, Swift version, targets, and dependencies live in
[`Package.swift`](Package.swift). The current release workflow targets macOS 26
on Apple silicon and requires the matching Xcode Metal Toolchain for MLX.

```zsh
xcode-select -p
swift --version
xcrun metal --version
```

Install the matching Metal component when needed:

```zsh
xcodebuild -downloadComponent MetalToolchain
```

## Build and test

```zsh
swift package describe --type json
swift test
./script/build_and_run.sh --verify
```

The app-aware build script creates `dist/Lerro.app` with resources, privacy
metadata, third-party license records, an arm64 executable, and a matching dSYM.
A bare executable under `.build` has a smaller runtime boundary and is not a
Release acceptance artifact.

Create and verify release archives with:

```zsh
./script/package_release.sh
./script/verify_release.sh
```

Signing modes are `auto`, `ad-hoc`, `development`, and `developer-id`. Public
distribution uses a Developer ID Application identity, Hardened Runtime, secure
timestamping, Apple notarization, stapling, Gatekeeper validation, and an
independent quarantine test. The Phase 6 publication pipeline also produces an
SBOM and GitHub artifact attestation. Signing identities and the
`LERRO_NOTARY_PROFILE` value stay in the maintainer environment.

Preview builds use manual updates. Choose **Check for Updates** in Home or
Settings to open the complete [GitHub Releases](https://github.com/Ryan-yang125/lerro/releases)
list, including prereleases, then download the newer signed build. Stable
automatic updates remain a future release capability.

## Permissions and intelligence providers

Lerro can request Microphone, Speech Recognition, Accessibility, and Input
Monitoring. Each permission has a feature-scoped explanation and remains under
the user's control in System Settings. See [macOS permissions](docs/permissions.md).

Basic Dictate can deliver the Apple Speech transcript directly. Intelligent
processing can use the optional MLX model or a user-configured compatible API.
The default local-model download is approximately 3.03 GB and starts only after
explicit consent. API mode sends the enabled context directly to the selected
provider. See [intelligence providers](docs/models.md).

## Privacy

Lerro has no account requirement, advertising SDK, or analytics pipeline.
History, dictionary, preferences, optional audio, and model files remain in the
app's Application Support directory. Provider API keys are plaintext fields in
the local `preferences.json`, protected with owner-only file permissions. Raw-audio
retention is disabled by default. Public model downloads use no Hugging Face
account bearer token. API processing sends only the context enabled in settings
to the provider chosen by the user.

Read [PRIVACY.md](PRIVACY.md) and the engineering
[privacy and security boundary](docs/privacy-security.md) for the complete data
map, clipboard transaction, secure-input, logging, deletion, and migration
rules.

## Documentation

- [Engineering index](docs/README.md)
- [Architecture](docs/architecture.md)
- [Core flow](docs/core-flow.md)
- [Build](docs/build.md)
- [Testing](docs/testing.md)
- [Release and notarization](docs/release.md)
- [Identity and migration](docs/identity.md)
- [Open-source publication](docs/open-source/README.md)
- [Brand Kit](Brand/README.md)

Automated tests, bundle validation, fixture screenshots, real macOS permissions,
physical shortcuts, cross-application delivery, local model generation, and
Developer ID distribution each prove a separate boundary. Release claims list
the exact checks completed and the system-level checks still pending.

## Contributing and security

Start with [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md). Report
suspected vulnerabilities through the private path in [SECURITY.md](SECURITY.md).
Use synthetic content in tests, logs, issues, and screenshots.

Source code is licensed under [Apache-2.0](LICENSE). First-party documentation,
screenshots, and reusable templates use
[CC BY 4.0](LICENSES/CC-BY-4.0.txt). Third-party records are in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The Lerro name and logo follow
[TRADEMARKS.md](TRADEMARKS.md).
