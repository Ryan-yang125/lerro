# Development

How to build, test, run, sign, and release Lerro. The architecture is in
[`architecture.md`](architecture.md).

## Requirements

- An Apple silicon Mac with a macOS 26 SDK. `Package.swift` fixes the Swift tools
  version and deployment target.
- Xcode command line tools: `xcode-select -p`, `swift --version`.
- Node.js 22.12 or later for `site/` and `distribution/`.
- For releases: a Developer ID Application certificate, a `notarytool` Keychain
  profile, and the Sparkle Ed25519 private key in the login Keychain.

## Build and run

SwiftPM resource accessors need a standard app bundle, so run the app through the
script. A bare executable under `.build/` lacks Dock identity, resources, and
signing, and is not a supported way to launch Lerro.

```zsh
./script/build_and_run.sh              # release build, assemble dist/Lerro.app, launch
./script/build_and_run.sh --debug      # debug build
./script/build_and_run.sh --no-launch  # build and verify only
./script/build_and_run.sh --verify     # swift test, build, launch, confirm the process stays alive
./script/build_and_run.sh --logs       # stream process logs
./script/build_and_run.sh --telemetry  # stream logs for subsystem app.lerro.mac
```

The script assembles `dist/Lerro.app` (SwiftPM resource bundles, Sparkle framework,
privacy manifest, terms, third-party licenses, app icon, `Assets.car`), checks the
resource accessor, arm64 slices, matching binary and dSYM UUIDs, plists, and the
code signature, then signs according to the signing mode. Running the script
terminates a running `Lerro` process before launching.

## Tests

```zsh
swift test                                   # everything
swift test --filter AppSessionCoreFlowTests  # one suite
swift test --filter LerroCoreTests           # one target
swift test list                              # print the current test names
```

Targets: `LerroCoreTests`, `LerroIntelligenceTests`, `LerroMacTests`, `LerroTests`.
Tests use temporary directories and inert adapters. They never touch the real
Application Support folder, microphone, TCC, Accessibility, event taps, clipboard,
or login items. Swift Testing filters match the generated test names, so run
`swift test list` when a filter selects nothing.

Optional live check of the remote runtime against DeepSeek (reads
`DEEPSEEK_API_KEY` or a mode `0600` `.env.deepseek.local`, prints latency and pass
markers only):

```zsh
./script/test_live_remote.sh
```

Python script tests (also run in CI):

```zsh
python3 script/benchmark_contextual_dictation.py --validate
python3 script/test_contextual_benchmark.py
python3 script/test_capture_latency_report.py
```

## Fixtures

Fixture mode renders deterministic UI with in-memory repositories and inert
adapters. It does not start the microphone, request permissions, write to disk, or
use the network. Environment variables are read in
[`AppSession.swift`](../Sources/Lerro/App/AppSession.swift),
[`AppDependencies.swift`](../Sources/Lerro/App/AppDependencies.swift), and
[`InterfaceLocalization.swift`](../Sources/Lerro/App/InterfaceLocalization.swift).

```zsh
./script/build_and_run.sh --debug --no-launch
open -F -n --env LERRO_FIXTURE_MODE=1 dist/Lerro.app
open -F -n --env LERRO_FIXTURE_MODE=1 --env LERRO_FIXTURE_DESTINATION=history dist/Lerro.app
open -F -n --env LERRO_FIXTURE_MODE=1 --env LERRO_FIXTURE_PRESENTATION=hud-recovery \
  --env LERRO_FIXTURE_PANEL_ONLY=1 dist/Lerro.app
```

| Variable | Values |
| --- | --- |
| `LERRO_FIXTURE_MODE` | `1` enables fixture mode (required for the rest) |
| `LERRO_FIXTURE_DESTINATION` | `home`, `history`, `dictionary`, `appTones` |
| `LERRO_FIXTURE_PRESENTATION` | `settings-general`, `settings-dictation`, `settings-ai`, `settings-ai-usage`, `settings-privacy`, `settings-about`, `prompt-dictate`, `prompt-translate`, `prompt-dictionaryLearning`, `menubar-panel`, `menubar-panel-listening`, `menubar-panel-permission`, and `hud-` states (`waiting`, `preparing-speech`, `recording`, `timer`, `hands-free`, `silent`, `dictating`, `translating`, `processing`, `processing-translation`, `delivered-fallback`, `delivered-fallback-balance`, `error`, `recovery`, `dictionary-learned`) |
| `LERRO_FIXTURE_PANEL_ONLY` | `1` shows only the panel (HUD and menu bar presentations) |
| `LERRO_FIXTURE_ONBOARDING`, `LERRO_FIXTURE_ONBOARDING_STEP` | `1`; step `welcome`, `practice`, `ai`, `start` |
| `LERRO_FIXTURE_AI` | `connected` (Key saved, balance 8.42 CNY), `no-balance` (Key saved, balance 0, account unavailable), `off` (no Key, AI cleanup off, Home shows the enable card). Default `connected`, or `off` when `LERRO_FIXTURE_ONBOARDING=1`. The fixture accepts any Key that starts with `sk-` and has at least 20 characters |
| `LERRO_FIXTURE_UPDATE_AVAILABLE` | `1` shows the update indicator with version 1.9.1 without Sparkle |
| `LERRO_FIXTURE_APPEARANCE` | `light`, `dark` |
| `LERRO_FIXTURE_LANGUAGE` | `en`, `zh-Hans` |
| `LERRO_FIXTURE_REDUCE_MOTION`, `LERRO_FIXTURE_INCREASE_CONTRAST`, `LERRO_FIXTURE_REDUCE_TRANSPARENCY` | `1` |

For UI changes, check the main window at 1080x750 and 988x658, light and dark
appearance, Increase Contrast, Reduce Transparency, Reduce Motion, and the
affected HUD states and Settings tabs.

## Signing modes

`LERRO_SIGNING_MODE` selects the mode. Resolution rules are in
[`script/signing_support.zsh`](../script/signing_support.zsh).

| Mode | Identity | Use |
| --- | --- | --- |
| `auto` (default) | Explicit `LERRO_CODESIGN_IDENTITY`, otherwise the first Apple Development identity, otherwise ad-hoc | Local default |
| `ad-hoc` | `-` | CI and machines without certificates |
| `development` | `Apple Development: ...` | Stable code identity for repeated TCC testing |
| `developer-id` | `Developer ID Application: ...` | Public releases; requires `LERRO_NOTARY_PROFILE` |

List identities with `security find-identity -v -p codesigning`. The script rejects
mismatched mode and identity combinations. Keep identity names, Team IDs, and
profile names in the maintainer's environment. They stay out of tracked files,
logs, and chat.

## Release

Release requires explicit approval from the maintainer, because it publishes to
Cloudflare and GitHub. Keep the source tree unchanged while it runs;
`package_release.sh` exits with code 75 when the tree changes during the build.

Maintainer labels live in `config/maintainer.local.env` (git-ignored; template in
[`config/maintainer.env.example`](../config/maintainer.env.example)).

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in
   [`config/Info.plist`](../config/Info.plist). Add the entry to
   [`CHANGELOG.md`](../CHANGELOG.md) and to the top of `releases` in
   `site/src/data/releases.ts`, and update `currentVersion` in `site/src/site.ts`.
2. Commit.
3. Verify and package:

   ```zsh
   source config/maintainer.local.env
   LERRO_SIGNING_MODE=developer-id ./script/verify_release.sh
   ```

   This runs script lint, plist lint, the full test suite, the release build,
   Developer ID signing, notarization, stapling, Sparkle Ed25519 signing, ZIP and
   dSYM packaging, the drag-to-install DMG (built with `dmgbuild` from
   [`script/requirements-dmg.txt`](../script/requirements-dmg.txt) in
   `.build/dmgbuild-venv`, then signed, notarized and stapled), the CycloneDX SBOM, the manifest, and checksums. It then unzips
   into a temporary directory and checks layout, resources, licenses,
   architecture, dSYM UUID, code signature, Gatekeeper, an inert fixture
   launch, and the DMG contents, checksum and notarization. Outputs in `outputs/`:

   ```text
   Lerro-macOS-arm64.zip
   Lerro-macOS-arm64.dmg
   Lerro-macOS-arm64.dSYM.zip
   Lerro-macOS-arm64.cdx.json
   Lerro-release-manifest.json
   SHA256SUMS.txt
   ```

4. Deploy the website so the changelog is live before the appcast:

   ```zsh
   (cd site && npm run deploy)
   ```

5. Publish the archive and update feed. The website "latest" download serves the
   DMG; Sparkle updates keep using the ZIP:

   ```zsh
   ./script/publish_cloudflare_release.sh
   ```

   The script re-verifies the ZIP against the manifest, uploads it to an immutable
   R2 key, reads it back and compares SHA-256, advances the D1 stable channel head
   in one batch with a generation check, and fetches the public appcast and
   download URLs to confirm version, length, and signature.
6. Push, tag, and create the GitHub release:

   ```zsh
   git push
   git tag -a vX.Y.Z -m "Lerro X.Y.Z"
   git push origin vX.Y.Z
   gh release create vX.Y.Z --title "Lerro X.Y.Z" --notes-file <notes> \
     outputs/Lerro-macOS-arm64.zip outputs/Lerro-macOS-arm64.dmg \
     outputs/Lerro-macOS-arm64.dSYM.zip \
     outputs/Lerro-macOS-arm64.cdx.json outputs/Lerro-release-manifest.json \
     outputs/SHA256SUMS.txt
   ```

If any step fails, the previous published archive and stable channel head stay in
place. Fix the cause, then rerun from a clean tree. Withdrawing a version means
moving the D1 stable head back to an earlier published record. Immutable ZIPs stay
in R2.

`distribution/wrangler.toml` holds private Cloudflare identifiers. It is
git-ignored; copy
[`distribution/wrangler.toml.example`](../distribution/wrangler.toml.example) on a
new machine. Design and failure policy are in
[ADR 0007](decisions/0007-cloudflare-distribution-and-sparkle-updates.md).

## Website

`site/` is an Astro static site served by a Cloudflare Worker (`lerro-site`).
Chinese pages are at `/`, English at `/en`. More detail is in
[`site/README.md`](../site/README.md).

```zsh
cd site
npm ci
npm run dev      # local server
npm run lint     # astro check
npm run build    # static build into dist/
npm test         # reads dist/, build first
npm run deploy   # build, then wrangler deploy
```

The update Worker in `distribution/` has its own checks: `npm run check && npm test`
there.

## CI

[`.github/workflows/ci.yml`](../.github/workflows/ci.yml) runs one Linux job: shell
syntax, `script/validate_agent_workspace.sh` (agent entry points and Markdown link
check), the three Python script tests, and the website lint, build, and tests.
Swift build, tests, signing, and packaging run locally in `verify_release.sh`.

## Troubleshooting

**The window never appears or resources are missing.** The app was launched from
`.build/` directly. Use `./script/build_and_run.sh`.

**Release build fails on a missing resource bundle or dSYM UUID mismatch.** Rebuild
with `./script/build_and_run.sh --release --no-launch`. The script lists bundle
inventory differences and compares binary and dSYM UUIDs.

**`package_release.sh` exits with 75.** The source tree changed during the build.
Check `git status --short`, wait for other writers (editors, formatters, other
agents) to finish, and rerun.

**Permission is granted in System Settings but Lerro reports it missing.** The app
path or signing identity changed, so macOS holds a stale entry. Quit Lerro, remove
the **Lerro** entry under Privacy & Security > Accessibility, launch the current
build from a stable path (for example `/Applications`), and grant it again. Use a
`development` signed build for repeated testing. A single-service TCC reset is
`tccutil reset Accessibility app.lerro.mac` (or `Microphone`). Do not run a
global reset.

**Speech reports that language resources are not ready.** Lerro prepares the
selected locale at launch, on language change, and before capture. If the same
error repeats without a restart, check `SpeechTranscriber.installedLocales`. After
`mobileassetd` restarts, `AssetInventory.status` can report an installed locale as
`.supported` and a reinstall then fails with `Code=4099`, while transcription still
works. The resource check in
[`AppleSpeechService.swift`](../Sources/LerroMac/Speech/AppleSpeechService.swift)
treats `installedLocales` as authoritative.

**System audio stays muted after a recording.** Every exit path (finish, cancel,
Speech failure, analyzer failure, empty transcript) must call
`restoreOutputAudioIfNeeded()` in
[`CoreAudioHardware.swift`](../Sources/LerroMac/Audio/CoreAudioHardware.swift).

**A shortcut does nothing.** Accessibility must be granted. Open the shortcut
recorder in Settings or onboarding and press the key; the keycap shows pressed and
released state, which shows whether macOS delivers the event. Built-in Fn is key
code 63 and an external Globe key is 179; some external keyboards send no event for
Fn. If Fn still opens the emoji picker, set System Settings > Keyboard > "Press Fn
key to" to Do Nothing and retest. Logs: `./script/build_and_run.sh --telemetry`.

**Text is not inserted, and the final text is on the clipboard.** Strict delivery
stopped because the frontmost application, focused element, value, selection, or
secure-input state changed after capture, or Accessibility could not read the
target. This is the designed fallback. The HUD recovery card offers Copy again.

**AI cleanup fails.** Open Settings > AI 整理 and check the key status and the
balance. A rejected key shows "这个 Key 用不了"; an empty account shows
"DeepSeek 余额用完了". Dictate falls back to the Apple transcript when the call
fails, and Translate reports the error.

**A JSON data file is corrupt.** Back up the specific file. Lerro reports the error
and keeps the original file. Do not delete the Application Support folder.
`preferences.json` contains the plaintext API key, so lint it with
`plutil -lint` and avoid printing it.
