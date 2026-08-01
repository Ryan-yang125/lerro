# Contributing to Lerro

Thank you for helping improve Lerro. Small, reviewable changes with clear
evidence are easiest to maintain.

## Before starting

1. Read [AGENTS.md](AGENTS.md) and the [documentation index](docs/README.md).
2. Search existing issues and discussions.
3. Open an issue for a substantial behavior, data, permission, dependency, or
   architecture change so the boundary can be agreed before implementation.
4. Use synthetic text, audio, history, and screenshots in every fixture and
   report.

Security reports follow [SECURITY.md](SECURITY.md). Sensitive details stay out
of public issues and pull requests.

## Development environment

The package declares the supported macOS and Swift versions in `Package.swift`.
Use the current Xcode toolchain and install its matching Metal Toolchain when
`xcrun metal --version` reports that the component is unavailable.

```zsh
swift package describe --type json
swift test
./script/build_and_run.sh --verify
```

The canonical GUI artifact is the app bundle produced under `dist/`. A bare
SwiftPM executable does not carry the full resource, privacy, entitlement, and
signing behavior of the app bundle.

## Change design

- Preserve the one-way dependency direction documented in
  [architecture.md](docs/architecture.md).
- Put deterministic rules and storage contracts in `LerroCore`, MLX behavior in
  `LerroIntelligence`, macOS frameworks in `LerroMac`, and app composition or
  presentation in `Lerro`.
- Keep views focused on rendering and forwarding user intent.
- Update tests and user-facing documentation with behavior, permission, data,
  environment-variable, or release changes.
- Record long-lived architecture decisions with an ADR under `docs/decisions/`.
- Reuse the design tokens and system-semantic Apple visual language.

## Repository hygiene

Contributions must exclude:

- Credentials, signing identities, Team IDs, certificate email addresses, and
  local manifest values.
- Absolute local paths, real user content, private logs, recordings, databases,
  model weights, build products, dSYMs, archives, and notarization output.
- Reverse-engineering records, third-party product screenshots, or proprietary
  assets.
- Unlicensed fonts, images, icons, screenshots, data, or generated assets.
- Legacy product identifiers outside the narrowly documented migration and
  compatibility boundary.

Run the public-repository scan before requesting review:

```zsh
./script/scan_public_repo.sh .
```

## Tests and evidence

Start with the narrowest affected test, then run the required gate in
[testing.md](docs/testing.md). Every pull request should report:

- Focused and full test commands with results.
- `git diff --check`.
- Release app, architecture, dSYM, resource, and signing checks when applicable.
- Fixture screenshots and real-window evidence for UI changes.
- Real-device tests completed and system boundaries still awaiting manual
  verification.

Build success, a running process, and fixture behavior each prove a limited
boundary. Describe each result at that level.

## Pull requests

Keep commits focused and use clear messages. Complete the pull request template,
link related issues, explain data and permission effects, and disclose generated
content or dependency updates. Maintainers may ask for a smaller change when it
improves reviewability or rollback.

Unless marked otherwise, intentionally submitted code contributions are
licensed under Apache-2.0. Documentation, screenshots, and reusable project
templates are licensed under CC BY 4.0. A contribution containing third-party
material must preserve its upstream license and attribution.
