# Contributing to Lerro

Lerro is maintained by one person. Small, reviewable changes with clear evidence
are the easiest to merge.

## Before starting

1. Read [AGENTS.md](AGENTS.md) and the [documentation index](docs/README.md).
2. Search existing issues and discussions.
3. Open an issue before a substantial change to behavior, data, permissions,
   dependencies, or architecture.
4. Use synthetic text, audio, history, and screenshots in every fixture and report.

Security reports follow [SECURITY.md](SECURITY.md). Keep sensitive details out of
public issues and pull requests.

## Development

Build, test, fixture, and signing commands are in
[docs/development.md](docs/development.md). In short:

```zsh
swift test
./script/build_and_run.sh --verify
```

The supported GUI artifact is the app bundle under `dist/`. A bare SwiftPM
executable lacks the resources, entitlements, and signing of the bundle.

## Change design

- Keep the dependency direction in [architecture.md](docs/architecture.md).
- Put deterministic rules in `LerroCore`, the remote runtime in
  `LerroIntelligence`, macOS frameworks in `LerroMac`, and composition and
  presentation in `Lerro`.
- Keep views focused on rendering and forwarding user intent.
- Update tests and documentation together with behavior, permission, data, or
  environment-variable changes. Record long-lived architecture decisions under
  `docs/decisions/`.
- Reuse the design tokens and the system-native visual language.

## Repository hygiene

Contributions exclude:

- Credentials, signing identities, Team IDs, certificate email addresses, and
  local configuration values.
- Absolute local paths, real user content, private logs, recordings, databases,
  build products, dSYMs, archives, and notarization output.
- Third-party product screenshots or proprietary assets.
- Unlicensed fonts, images, icons, screenshots, data, or generated assets.

## Evidence

Start with the narrowest affected test, then run `swift test`. A pull request
reports the test commands and results, `git diff --check`, fixture screenshots for
UI changes, and the system boundaries that were not verified (microphone, TCC,
specific target applications, other displays). Build success, a running process,
and fixture behavior each prove a limited boundary.

## Pull requests

Keep commits focused with clear messages. Complete the pull request template, link
related issues, explain data and permission effects, and disclose generated
content and dependency updates.

Unless marked otherwise, intentionally submitted code is licensed under
Apache-2.0. Documentation, screenshots, and reusable templates are licensed under
CC BY 4.0. A contribution containing third-party material preserves its upstream
license and attribution.
