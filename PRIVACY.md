# Privacy

Lerro is a local-first macOS voice-writing application with optional BYOK cloud
text processing. This document describes the behavior of official source builds
and release artifacts.

## Data stored on the Mac

Lerro stores preferences, history, personal dictionary entries, optional audio,
and local-model files below its Application Support directory. Provider settings
and user-supplied API keys are stored as plaintext inside `preferences.json`.
The Application Support directory is restricted to mode `0700`, and the
preferences file is restricted to mode `0600`. Software running as the same
macOS user can still read this file. Raw-audio retention is disabled by default.
Selecting “never save” for history prevents new history and recording files from
being persisted.

History and dictionary records can be deleted from the app. When a history item
owns an audio file, Lerro removes the audio before removing its index entry.
Model files can be removed by following the documented cache-removal procedure.

## System permissions

Lerro can request two macOS permissions:

- Microphone, to capture speech after an explicit user action.
- Accessibility, to inspect a limited focused-element context, deliver text,
  and suppress a configured shortcut key before it reaches the focused app.

The app checks secure input fields before capture. Selection-aware Rewrite also
verifies the secure-input state, target application, focused element, and original
selection immediately before delivery. Ordinary insertion follows the keyboard
focus present when Command-V is committed, so a focus change during processing
changes the destination. Permissions can be reviewed or revoked in System Settings
at any time.

## Network access

Lerro has no account requirement, advertising SDK, or analytics pipeline.
Network access is limited to these product paths:

- macOS may obtain Speech language resources through Apple-managed services.
- After explicit consent, Lerro downloads the selected MLX model from its
  public Hugging Face repository. The public client is configured without an
  account bearer token. Hugging Face receives ordinary connection metadata
  such as IP address, User-Agent, and request time.
- When the user selects API processing, Lerro sends a Chat Completions request
  directly to the configured DeepSeek, OpenAI, Gemini, or custom compatible
  endpoint using the user's API key. A connection test sends only a fixed
  synthetic message.
- Lerro checks the signed Sparkle release feed at `updates.lerroapp.com` on app
  launch, every 24 hours while running, and on an explicit user check. When a
  newer release is available, clicking the update control starts the signed ZIP
  download from the same domain. Cloudflare receives ordinary
  connection metadata and update-selection information such as app version and
  platform. Its private R2 and D1 resources retain release ZIPs and release
  metadata only.

Voice audio, transcripts, focused text, dictionary entries, and prompts are not
sent to Hugging Face. Local language-model generation runs on the Mac after the
model is available. An enabled API-processing request can include the current
raw transcript, application name and type, window title, up to 80 UTF-16 units
before the caret, up to 40 after it, task-relevant selected text, the user's tone,
and up to 12 matching dictionary entries. The configured provider receives this
content plus ordinary connection and billing metadata under its own terms and
privacy policy.

The update service does not receive voice audio, transcripts, focused text,
selected text, dictionary entries, prompts, model answers, or provider API keys.
The app verifies each downloaded update archive with its embedded Sparkle
Ed25519 public key before installation.

## Clipboard and focused text

Lerro delivers ordinary text to the keyboard focus present at commit time through
a best-effort clipboard archive and Command-V, then restores the archive after a
500 ms consumption window. Selection-aware Rewrite validates the captured target,
focused element, selection, and secure-input state through Accessibility before
delivery and uses a session-owned strict clipboard transaction.

Focused text and selections are held only for the active operation. Application
logs exclude transcripts, selected text, focused text, prompts, answers, API
keys, authorization headers, invitation codes, and personal identifiers.

## Legacy data migration

An upgrade can migrate compatible data from an earlier local application
identity. Migration runs before repositories and the model runtime initialize,
uses a lock and receipt, and keeps rollback information. Model files are moved
or reused on the same volume to avoid a second multi-gigabyte copy. No migrated
data leaves the Mac.

## Backups and removal

macOS backup software can include Application Support data according to the
user's backup configuration, including plaintext API keys in `preferences.json`.
Removing the app bundle leaves local data in place. Users who want complete local
removal should also remove Lerro's Application Support directory after preserving
any desired exports. The “clear saved key” action removes the API key from the
JSON configuration and returns Lerro to raw Dictate.

Material changes to data collection, networking, permissions, or retention must
update this file, `PrivacyInfo.xcprivacy`, usage descriptions, entitlements,
tests, and release notes in the same change.
