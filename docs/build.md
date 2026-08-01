# Build Lerro

Lerro is a package-first SwiftPM macOS application. `Package.swift` defines the
supported macOS version, Swift language mode, products, targets, and source
dependencies. The repository carries two patched packages under `Vendor/` and
records every remote revision in `Package.resolved`.

## Requirements

- A Mac and Xcode version that provide the SDK declared in `Package.swift`.
- Apple silicon for the current arm64 release workflow.
- The matching Xcode Metal Toolchain for MLX release builds.

Check the active environment:

```zsh
xcode-select -p
swift --version
xcodebuild -version
xcrun metal --version
```

When the Metal component is unavailable:

```zsh
xcodebuild -downloadComponent MetalToolchain
```

## Tests and app bundle

```zsh
swift package describe --type json
swift test
./script/build_and_run.sh --verify
```

`build_and_run.sh` creates `dist/Lerro.app` with the SwiftPM resource bundles,
privacy manifest, usage documents, app icon, third-party license records, and a
matching arm64 dSYM. Single-architecture arm64 build products are copied
directly; universal products are reduced to their arm64 slice. When SwiftBuild
finishes, the script creates a fresh dSYM from the staged arm64 executable with
`dsymutil` before UUID verification. The app bundle is the canonical GUI
artifact.

Use an inert fixture for deterministic UI work:

```zsh
./script/build_and_run.sh --debug --no-launch
open -F -n --env LERRO_FIXTURE_MODE=1 dist/Lerro.app
```

The fixture uses in-memory repositories and inert macOS adapters. It must remain
free of real disk persistence, microphone capture, TCC prompts, Accessibility,
CGEventTap, clipboard writes, login-item changes, model loading, and network
access.

## Brand resources

```zsh
./Brand/scripts/generate-assets.sh
./Brand/scripts/verify-assets.sh
```

The generator rebuilds the SVG, PDF, PNG, ICNS, templates, validation boards,
and Brand checksums. It also synchronizes the app icon and eight menu-bar
template PNGs into `Sources/Lerro/Resources`. The verifier checks the complete
ICNS representation set and byte identity between Brand exports and runtime
resources.

## Signing modes

| Mode | Intended use | Identity |
| --- | --- | --- |
| `auto` | Local convenience | Resolves Apple Development when available, then ad-hoc |
| `ad-hoc` | Local build and CI | `-` |
| `development` | Stable local TCC and device testing | Apple Development |
| `developer-id` | Public distribution | Developer ID Application |

Select a mode through `LERRO_SIGNING_MODE`. An explicit identity can be supplied
through `LERRO_CODESIGN_IDENTITY`. Keep identity values in the maintainer's
environment; public files and logs must omit certificate email addresses and
Team IDs.

## Release gate

```zsh
./script/verify_release.sh
```

The gate lints scripts and property lists, verifies deterministic Brand assets,
confirms test discovery, runs the full test suite, builds the Release app,
packages archives, verifies hashes and source metadata, extracts through an
isolated path, checks architecture and dSYM UUIDs, validates resources and
signing, then launches the inert fixture.

Developer ID distribution additionally requires a preconfigured notarytool
keychain profile supplied as `LERRO_NOTARY_PROFILE`. See
[`release.md`](release.md) for the notarization and independent quarantine
matrix.
