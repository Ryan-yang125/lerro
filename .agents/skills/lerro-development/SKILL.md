---
name: lerro-development
description: Develop, diagnose, test, and release the Lerro macOS dictation app. Use for any Lerro Swift, macOS integration, Speech, hotkey, permission, UI, remote AI, website, Cloudflare distribution, packaging, or release task.
---

# Lerro Development

`AGENTS.md` at the repository root holds the project rules. `docs/development.md`
holds the commands. `docs/architecture.md` describes the code.

## Start

1. Change to the Git root (`git rev-parse --show-toplevel`).
2. Run `git status --short` and keep other people's uncommitted changes.
3. Read `AGENTS.md`, `docs/README.md`, and `Package.swift`.
4. Run `./script/validate_agent_workspace.sh`.
5. Locate affected symbols, callers, and tests with `rg`.

## Work

1. Put rules in `LerroCore`, system APIs in `LerroMac`, the remote runtime in
   `LerroIntelligence`, and pages and orchestration in `Lerro`.
2. Run the narrowest related test first (`swift test --filter <Suite>`), then
   `swift test`.
3. For UI, build with `./script/build_and_run.sh --debug --no-launch` and check with
   the inert fixture variables in `docs/development.md`.
   For main-window, page, or `AppSession` changes, follow `docs/performance.md`
   and run `./script/measure_ui_performance.sh` on a release build
   (`./script/build_and_run.sh --no-launch`); debug builds are not comparable.
4. Update the document that describes any behavior, command, data, or permission
   you changed. Add an ADR under `docs/decisions/` for a long-lived architecture
   change.
5. Finish with `git diff --check` and `git status --short`.

## Authorization

- Answering, reviewing, and diagnosing stay read-only.
- Editing the repository and running tests or local builds is allowed for
  implementation tasks.
- `git push`, tags, GitHub Releases, `npm run deploy`, `publish_cloudflare_release.sh`,
  notarization, TCC resets, certificate changes, and real API calls change external
  or user state. Run them only when the user asked for that action.
- Keep API keys, signing identities, Team IDs, notary profiles, and local config
  contents out of output, logs, and tracked files.

## Release

Follow the Release section of `docs/development.md`: version bump in
`config/Info.plist`, `CHANGELOG.md`, and `site/src/data/releases.ts`; commit;
`verify_release.sh` with `LERRO_SIGNING_MODE=developer-id`; website deploy;
`publish_cloudflare_release.sh`; push, tag, and `gh release create` with the six
files from `outputs/`.

## Final report

State what changed, the exact commands run and their results, the signing mode of
any artifact, and the system boundaries not verified (microphone, TCC, specific
target applications, other displays).
