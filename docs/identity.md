# Product and system identity

Lerro's public name, code targets, bundle identity, storage root, environment
variables, and release artifacts form one versioned system boundary.

## Frozen identity

| Role | Value |
| --- | --- |
| Product and executable | `Lerro` |
| Core target | `LerroCore` |
| Intelligence target | `LerroIntelligence` |
| macOS integration target | `LerroMac` |
| Bundle ID | `app.lerro.mac` |
| Application Support root | `~/Library/Application Support/app.lerro.mac/` |
| Environment prefix | `LERRO_` |
| Public repository name | `lerro` |
| Release app | `Lerro.app` |

Logs use a subsystem derived from `app.lerro.mac`. Pasteboard session marker
types and login-item identity are also derived from the stable Bundle ID. A
change to any value in this table requires a new ADR plus migration, permission,
release, and documentation review.

The naming decision and its remaining commercial-clearance risk are recorded in
[ADR 0002](decisions/0002-lerro-product-identity.md) and
[`name-clearance.md`](name-clearance.md).

## Legacy compatibility boundary

The shipped migration recognizes the previous data root identified by bundle ID
`com.ryanyang.typelessnative`. The previous package name `TypelessNative` and
`TYPELESS_` environment prefix remain scan-only legacy markers; the runtime,
scripts, and CI use the Lerro identity exclusively. Legacy values do not appear
in public product copy, app icon metadata, screenshots, release names, current
logs, or new storage paths.

Migration begins before repositories and `MLXLanguageModelRuntime` initialize.
It uses a lock, transaction journal, receipt, recovery report, and safe rollback
or replay; rerunning it is safe. A single legacy root moves through same-volume
renames. Coexisting roots receive a complete preflight: unique entries move,
byte-identical entries deduplicate, and content conflicts preserve both roots
with a recovery report. Large model files are never copied by this migration.
The release matrix proves that the resulting cache works offline and that a
second model copy was not created.

After the data receipt commits, Lerro asks `SMAppService.mainApp` to unregister
an in-place prior registration and then applies the migrated launch-at-login
preference to the new identity. A separately installed stale registration
requires confirmation in System Settings and is recorded in the receipt as a
user-review state. Lerro suppresses its global hotkey monitor while the legacy
bundle is running.

## Permission effect

macOS treats `app.lerro.mac` as a new privacy identity. Microphone, Speech,
Accessibility, and Input Monitoring are requested again from the final signed
app. Testing uses a stable app path and signing identity so results correspond
to the release candidate.

## Identity checks

```zsh
swift package describe --type json
plutil -p config/Info.plist
codesign -dvvv dist/Lerro.app
rg -n 'TypelessNative|TYPELESS_|com\.ryanyang\.typelessnative' \
  Package.swift Sources Tests config script docs README.md AGENTS.md
```

Every legacy match must be an explicit migration constant, compatibility test,
or the compatibility explanation in this document. The public-repository scan
enforces that boundary.
