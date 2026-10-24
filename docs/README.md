# Lerro documentation

Current code and `script/` take precedence when they differ from this prose.

| Document | Contents |
| --- | --- |
| [`development.md`](development.md) | Build, run, test, fixtures, signing modes, release steps, website, troubleshooting |
| [`architecture.md`](architecture.md) | Targets, capture flow, delivery, intelligence, storage, privacy boundaries |
| [`performance.md`](performance.md) | Performance budgets, rules for new code, and how to measure |
| [`decisions/`](decisions/README.md) | Architecture decision records |
| [`../AGENTS.md`](../AGENTS.md) | Rules for agents and contributors working in this repository |
| [`../PRIVACY.md`](../PRIVACY.md) | What data Lerro stores and sends |
| [`../SECURITY.md`](../SECURITY.md) | Security policy and invariants |
| [`../CONTRIBUTING.md`](../CONTRIBUTING.md) | Contribution workflow |
| [`../PRODUCT.md`](../PRODUCT.md), [`../DESIGN.md`](../DESIGN.md) | Product positioning and design language |
| [`../Brand/`](../Brand/README.md) | Logo, icon, color, motion, and copy sources and rules |
| [`../site/README.md`](../site/README.md) | Website |
| [`../distribution/README.md`](../distribution/README.md) | Update-feed Worker |

## Sources of truth

| Fact | Source |
| --- | --- |
| Platform, targets, dependencies | [`Package.swift`](../Package.swift), [`Package.resolved`](../Package.resolved) |
| Production composition | [`AppDependencies.swift`](../Sources/Lerro/App/AppDependencies.swift) |
| Session state and orchestration | [`AppSession.swift`](../Sources/Lerro/App/AppSession.swift), [`CaptureModels.swift`](../Sources/LerroCore/Models/CaptureModels.swift) |
| Storage paths | [`ApplicationPaths.swift`](../Sources/LerroCore/Support/ApplicationPaths.swift) |
| App identity and system declarations | [`Info.plist`](../config/Info.plist), [`Lerro.entitlements`](../config/Lerro.entitlements), [`PrivacyInfo.xcprivacy`](../Sources/Lerro/Resources/PrivacyInfo.xcprivacy) |
| Build, signing, release | [`script/`](../script) |
| CI | [`ci.yml`](../.github/workflows/ci.yml) |

Test counts and target lists come from `swift test` and `swift package describe --type json`.
Update the matching document in the same change as a behavior, command, or data-boundary change.
