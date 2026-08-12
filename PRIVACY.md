# Privacy

Lerro is a local-first macOS voice-writing application with optional local and
BYOK AI text processing. This document describes official source builds and
release artifacts.

## Data stored on the Mac

Lerro stores preferences, history, personal dictionary entries, per-app tone
profiles, optional audio, and local-model files below its Application Support
directory. Provider settings and user-supplied API keys are plaintext fields in
`preferences.json`. The directory uses mode `0700`; the preferences file uses
mode `0600`. Software running as the same macOS user can read this file.

Raw-audio retention starts disabled. Selecting “never save” for history prevents
new history and recording files from being persisted. History can contain the
raw transcript, final text, processing route, context-category presence, remote
sharing category names, timings, delivery outcome, and an audio reference when
audio saving is enabled. It does not store focused-value fingerprints or nearby
focused text.

Dictionary records contain a phrase, replacement, source, optional application
scope, and usage metadata. Learned entries can be reviewed, edited, promoted to
global scope, undone from the learning notification, or deleted.

## System permissions

Lerro requests two macOS permissions:

- Microphone, after an explicit Dictate or Translate action.
- Accessibility, for global shortcuts, limited target context, strict text
  delivery, failed-write protection, and observation of edits to the field that
  received the most recent AI-processed Dictate result.

Capture stops at secure input fields. At capture start Lerro records a bounded
fingerprint of the target application, focused element, value, selection, and
secure-input state. Delivery revalidates that fingerprint immediately before
Command-V. A target change stops the write and copies the final text for
recovery. Permissions can be reviewed or revoked in System Settings.

## Clipboard and focused text

Text delivery uses a session-owned clipboard transaction and a synthetic
Command-V. Lerro snapshots available pasteboard item types, installs the final
text, commits the paste, waits for the target to consume it, and restores the
snapshot only while the session still owns the temporary content. A failed write
keeps the final text on the clipboard and displays **Copy again**.

After a successful AI-processed Dictate, Lerro can observe the same application
and focused element for up to 60 seconds. It polls the current value, waits 800 ms
for an edit to stabilize, and extracts the smallest changed span only when the
original delivered text has a unique location. Leaving the app or field, secure
input, unavailable Accessibility data, unsupported editors, oversized values,
new capture, timeout, or disabled AI ends observation quietly.

The selected local or remote AI receives the original and corrected spans, up
to 80 UTF-16 units before the change, up to 40 after it, the application name,
and optional bundle identifier. It returns zero to three structured candidates.
Only small lexical corrections with confidence at least 0.7 are stored.
Semantic changes, additions, deletions, tone edits, restructuring, and broad
rewrites are excluded.

Application logs exclude audio, transcripts, selected text, focused text,
changed spans, prompts, model output, dictionary contents, API keys,
authorization headers, invitation codes, and personal identifiers.

## Apple Speech and dictionary context

Apple Speech performs transcription. Lerro supplies up to 100 relevant personal
dictionary replacements through `AnalysisContext.contextualStrings`. This
context remains inside the Apple Speech framework. Quick Dictate optionally uses
Apple `SpeechDetector` to end after about 1.2 seconds of continuous silence; it
starts disabled and adds no permission.

macOS may obtain Speech language resources through Apple-managed services.

## Local model and Hugging Face

After explicit consent, Lerro downloads the selected MLX model from its public
Hugging Face repository with no account bearer token. Hugging Face receives
ordinary connection metadata such as IP address, User-Agent, and request time.
Audio, transcripts, focused text, changed spans, dictionary entries, and prompts
are not sent to Hugging Face.

The default model is approximately 3.03 GB. Download continues while Lerro runs
and supports pause, resume, stop, and restart continuation. Stop removes only
incomplete data, resume state, and the download checkpoint; complete cached
blobs remain. Local generation runs on the Mac.

## BYOK remote providers

When API processing is selected, Lerro sends Chat Completions requests directly
to the configured DeepSeek, OpenAI, Gemini, or compatible endpoint using the
user's API key. A connection test sends a fixed synthetic message.

Depending on enabled context categories and the action, a request can include
the raw transcript, application name and type, window title, up to 80 UTF-16
units before the caret, up to 40 after it, selected text needed by the action,
the per-app tone, and up to 12 matching dictionary entries. Correction learning
uses the smaller span-only payload described above. The provider receives this
content plus normal connection and billing metadata under its terms.

Remote or local AI is required for refinement, translation, automatic
correction learning, and per-app tone. Apple-only mode still provides raw
transcription, dictionary-aware recognition, manual dictionary management,
preview, strict delivery, and recovery.

## Updates

Lerro checks the signed Sparkle feed at `updates.lerroapp.com` on launch, every
24 hours while running, and on an explicit user check. Cloudflare receives
ordinary HTTPS metadata and update-selection information such as app version and
platform. Private R2 and D1 storage contains release archives and public release
metadata only.

The update service does not receive audio, transcripts, focused text, changed
spans, dictionary entries, prompts, model output, or provider API keys. Sparkle
verifies each update archive with the embedded Ed25519 public key.

## Legacy data migration, backups, and removal

An upgrade can migrate compatible data from an earlier local application
identity. Migration runs before repositories and the model runtime initialize,
uses a lock and receipt, and keeps rollback information. Model files move or are
reused on the same volume to avoid a second multi-gigabyte copy. No migrated data
leaves the Mac.

macOS backup software can include Application Support data, including plaintext
API keys in `preferences.json`. Removing the app bundle leaves local data in
place. For complete local removal, remove Lerro's Application Support directory
after preserving desired exports. “Clear saved key” removes the API key and
returns Lerro to Apple-only Dictate.

Material changes to data collection, networking, permissions, or retention must
update this file, `PrivacyInfo.xcprivacy`, usage descriptions, entitlements,
tests, and release notes in the same change.
