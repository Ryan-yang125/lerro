# Security Policy

## Supported versions

Security fixes target the current stable release and the current development
branch. A report affecting an older release is evaluated using reachability,
impact, and the feasibility of a safe backport.

## Reporting a vulnerability

After the public repository enables GitHub Private Vulnerability Reporting,
open the repository's **Security** tab, choose **Advisories**, then select
**Report a vulnerability**. This is the preferred channel and keeps the report
inside a private GitHub Security Advisory.

If that control is temporarily unavailable, open a minimal public issue asking
the maintainers to enable a private reporting channel. Leave vulnerability
details, logs, personal data, credentials, and proof-of-concept material out of
that issue.

A useful private report includes the affected commit or release, macOS version,
attack prerequisites, trust boundary crossed, realistic impact, reproduction
steps using synthetic data, and a proposed mitigation when available.
Maintainers will coordinate status and disclosure through the private advisory.

## System and scope

Lerro is a local-first macOS voice-writing application. This policy covers:

- `LerroCore` domain rules, persistence, migration, and text-processing code.
- `LerroIntelligence` model download, cache, loading, and generation paths.
- `LerroMac` audio, Speech, Accessibility, clipboard, global-hotkey,
  permission, login-item, panel, and lifecycle adapters.
- The `Lerro` SwiftUI app, dependency composition, resources, and session
  orchestration.
- Build, signing, notarization, packaging, release, and public-export scripts.
- First-party release artifacts distributed by the project.

The security boundary includes local user text and audio, macOS permission
identity, focused application identity, clipboard contents, model artifacts,
release credentials supplied by the maintainer's environment, and the integrity
of published archives.

## Threat model and trust boundaries

Potentially untrusted inputs include microphone samples, recognized text,
focused-element content, clipboard types, CSV imports, stored JSON documents,
model responses, downloaded model files and metadata, environment variables,
filesystem state, and archive contents.

macOS frameworks, the active user's explicit actions, and release credentials
provided through an authorized maintainer environment form distinct trust
boundaries. A permission grant is scoped to the final signed bundle identity.
Entitlements and usage descriptions declare capabilities; they do not establish
user consent by themselves.

## Security invariants

- Secure capture targets fail closed before recording. Selection-aware Rewrite
  revalidates the target, focused element, secure state, and original selection
  before text delivery.
- Plain insertion sends Command-V to the keyboard focus present at commit time.
- Plain insertion restores its best-effort clipboard archive after the 500 ms
  consumption window. Selection-aware Rewrite preserves every readable item and
  type and restores only while the active session still owns its marker.
- Cancellation reaches activation, pre-commit clipboard waits, key-event checks,
  speech, output-audio restoration, temporary recording cleanup, and model loading.
  A committed Command-V finishes its consumption wait and clipboard restoration.
- A stale session or generation cannot update a newer capture.
- Logs exclude transcripts, focused or selected text, prompts, answers, audio,
  credentials, personal paths, email addresses, and invitation codes.
- User-supplied provider API keys are plaintext fields in the local
  `preferences.json`. The Application Support root uses mode `0700`, the file
  uses mode `0600`, and every atomic replacement reapplies the file mode.
- Remote-provider requests use an ephemeral URL session, HTTPS endpoint policy,
  bounded responses, cancellation, and credential-safe errors. Connection tests
  carry only fixed synthetic content.
- Raw-audio retention stays opt-in. A “never save” history policy prevents new
  history and recording writes.
- Public Hugging Face downloads use `bearerToken: nil` and do not inherit local
  CLI credentials.
- Model installation validates expected metadata and uses same-directory
  staging with atomic publication where the filesystem supports it.
- Legacy-data migration runs before repositories and the model runtime open the
  new data root, remains idempotent, records a receipt, and preserves rollback
  information.
- Release credentials stay outside the repository. Developer ID artifacts use
  Hardened Runtime, secure timestamping, notarization, stapling, and Gatekeeper
  validation.
- A public export contains only allowlisted files and starts with an independent
  Git object database and no configured remote.

## Reportable findings and severity context

Reports are especially useful when they demonstrate a reachable path to:

- Capture or persistence of voice or text without the expected user action.
- Text delivery into a secure, wrong, or stale target application.
- Loss, disclosure, or corruption of clipboard, history, dictionary, audio, or
  model-cache data across users or sessions.
- Credential exposure, signing bypass, malicious release substitution, or
  public-export leakage.
- Executing untrusted content through imported data, model metadata, archives,
  update paths, or system integration.
- Permission escalation or meaningful evasion of a fail-closed control.

Severity depends on attacker control, required user interaction, data
sensitivity, affected scope, persistence, and whether the issue reaches an
official release configuration.

## Scope boundaries

The following reports generally belong in another channel:

- Product bugs without a security boundary or confidentiality, integrity, or
  availability impact.
- Social engineering, phishing, physical access, or compromise of a user's
  Apple ID, GitHub account, keychain, or operating system.
- Denial-of-service tests against public services or resource exhaustion that
  requires the user to intentionally import an extreme local fixture.
- Vulnerabilities confined to an unchanged upstream dependency with no
  demonstrated reachability through Lerro. Report those upstream and link the
  advisory privately when Lerro may still be affected.
- Results from modified binaries, disabled platform protections, or unsupported
  macOS versions unless they reveal a flaw that also reaches a supported build.

Do not access another person's data, degrade a service, retain unnecessary
data, or publish details before a coordinated fix is available.
