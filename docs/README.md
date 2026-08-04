# Lerro engineering documentation

This directory explains the public architecture, product flow, system
boundaries, validation, and release process. Current code and generated release
evidence remain authoritative when implementation and prose diverge.

## Reading path

1. [`AGENTS.md`](../AGENTS.md) for repository rules and completion gates.
2. [`handoff/README.md`](handoff/README.md) for a zero-history development,
   validation, publication, and evidence workflow.
3. [`architecture.md`](architecture.md) for targets, dependency direction, data
   ownership, and code routing.
4. [`core-flow.md`](core-flow.md) for session states, cancellation, delivery,
   persistence, and recovery.
5. Select the relevant boundary:
   - [`permissions.md`](permissions.md)
   - [`models.md`](models.md)
   - [`privacy-security.md`](privacy-security.md)
   - [`build.md`](build.md)
   - [`testing.md`](testing.md)
   - [`release.md`](release.md)
   - [`troubleshooting.md`](troubleshooting.md)
6. Read [`identity.md`](identity.md) before changing product, bundle, data,
   permission, or release identity.
7. Read [`open-source/README.md`](open-source/README.md) before publishing source
   or release assets.
8. Add an ADR under [`decisions/`](decisions/README.md) for a long-lived
   architecture change.

Brand and interface rules live in [`Brand/`](../Brand/), including the
Apple-native visual language, logo and icon sources, motion, copy, tokens, asset
licenses, and deterministic validation assets.

## Document responsibilities

| Document | Boundary |
| --- | --- |
| [`handoff/`](handoff/README.md) | Fresh-agent bootstrap, current release state, maintainer readiness, full-chain workflow, and evidence template |
| [`architecture.md`](architecture.md) | Targets, dependencies, composition, concurrency, storage, and build shape |
| [`core-flow.md`](core-flow.md) | Dictate, Translate, Ask, Rewrite, Hands-free, failure, cancellation, and cleanup |
| [`permissions.md`](permissions.md) | Microphone, Accessibility, TCC, and manual checks |
| [`models.md`](models.md) | Consent, model source, download, cache, runtime, offline behavior, and smoke test |
| [`privacy-security.md`](privacy-security.md) | Data map, secure input, clipboard, audio, network, logs, and deletion |
| [`build.md`](build.md) | Toolchain, app bundle, fixtures, signing modes, and build commands |
| [`testing.md`](testing.md) | Focused tests, full gates, fixtures, real-device matrix, and evidence template |
| [`release.md`](release.md) | Local archives and manifests, plus Phase 6 signing, notarization, Gatekeeper, quarantine, SBOM, and attestation gates |
| [`identity.md`](identity.md) | Product, targets, Bundle ID, storage root, compatibility, and migration |
| [`open-source/`](open-source/README.md) | Licenses, allowlist export, secret and history scans, and publication steps |
| [`troubleshooting.md`](troubleshooting.md) | Build, resource, permission, Speech, hotkey, delivery, model, and signing diagnosis |

## Sources of truth

| Fact | Source |
| --- | --- |
| Swift, platform, products, targets, dependencies | [`Package.swift`](../Package.swift), [`Package.resolved`](../Package.resolved) |
| Production dependency graph | [`AppDependencies.live()`](../Sources/Lerro/App/AppDependencies.swift) |
| Session state and orchestration | [`CaptureModels.swift`](../Sources/LerroCore/Models/CaptureModels.swift), [`AppSession.swift`](../Sources/Lerro/App/AppSession.swift) |
| System adapters | [`Sources/LerroMac`](../Sources/LerroMac) |
| Model runtimes | [`MLXLanguageModelRuntime.swift`](../Sources/LerroIntelligence/MLXLanguageModelRuntime.swift), [`OpenAICompatibleRemoteLanguageModelRuntime.swift`](../Sources/LerroIntelligence/OpenAICompatibleRemoteLanguageModelRuntime.swift) |
| Data paths and migration | [`ApplicationPaths.swift`](../Sources/LerroCore/Support/ApplicationPaths.swift), [`ApplicationDataMigrator.swift`](../Sources/LerroCore/Support/ApplicationDataMigrator.swift) |
| Build and release | [`script/`](../script), [`config/`](../config) |
| Automated coverage | [`Tests/`](../Tests), [CI](../.github/workflows/ci.yml) |
| Brand assets and license | [`Brand/README.md`](../Brand/README.md), [`ASSET-LICENSES.json`](../Brand/licenses/ASSET-LICENSES.json) |
| Public source boundary | [`public_repo_allowlist.txt`](../script/public_repo_allowlist.txt), [`scan_public_repo.sh`](../script/scan_public_repo.sh) |

Read current test and target counts from commands:

```zsh
swift package describe --type json
swift test
```

## Evidence levels

- Focused tests establish a narrow deterministic contract.
- Full `swift test` establishes the discovered package test suite.
- `build_and_run.sh` establishes app-bundle assembly and a launch smoke.
- Fixture rendering establishes deterministic UI states with inert adapters.
- A signed Release app on the target Mac establishes permission, hardware,
  global shortcut, Accessibility, focus, clipboard, and window behavior.
- The explicit live-model smoke establishes real cache load and generation.
- Developer ID, notarization, staple, Gatekeeper, and quarantine checks establish
  the distribution boundary.

Every delivery report identifies completed levels and lists the remaining
manual boundaries.

## Documentation maintenance

- Use repository-relative links.
- Match paths, product names, environment variables, and commands to current
  implementation.
- Attach a commit or release to fixed measurements; derive changing counts from
  commands.
- Update behavior, tests, privacy statements, release notes, and ADRs together.
- Keep research captures, third-party screenshots, private evidence, and
  generated Release artifacts outside the public allowlist.
- Run the Markdown link check in [`testing.md`](testing.md) and the clean export
  scan before publication.
