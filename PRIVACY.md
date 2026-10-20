# Privacy

Lerro is a local-first macOS voice-writing application with optional bring-your-own-key
(BYOK) AI text processing. This document describes official source builds and
release artifacts.

## Data stored on the Mac

Lerro stores preferences, history, personal dictionary entries, per-app tone
profiles, optional audio, and AI usage records below its Application Support
directory. Provider settings and user-supplied API keys are plaintext fields in
`preferences.json`. The directory uses mode `0700`; the preferences file uses
mode `0600`. Software running as the same macOS user can read this file.

Raw-audio retention starts disabled. Selecting “never save” for history prevents
new history and recording files from being persisted. History can contain the
raw transcript, final text, processing route, context-category presence, remote
sharing category names, timings, delivery outcome, and an audio reference when
audio saving is enabled. When a dictation or translation used the API model, the
entry also keeps that call exactly as sent and received: the request content
(transcript and whichever context the sharing switches allowed, such as window
title, nearby text, selected text, dictionary terms and tone), the model's reply,
the prompt version, model ID, token counts and latency. The History page shows
this record, and it is deleted with the entry. It does not store focused-value
fingerprints, the system prompt text (only its version), or the API key.

Dictionary records contain a phrase, replacement, source, optional application
scope, and usage metadata. Learned entries can be reviewed, edited, promoted to
global scope, undone from the learning notification, or deleted.

AI usage records in `ai-usage.json` describe each remote model call: time,
feature, provider, model ID, input, output and cached token counts reported by
the provider, latency, success, and the ID of the history entry the call belongs
to. They contain no transcript, prompt, model output, context text, or API key. Records older than 90 days are removed, and
Settings → 用量 can clear them. Cost estimates are calculated on the Mac from the
built-in or user-edited price table; nothing about usage is sent anywhere.

Daily usage totals in `usage-days.json` power the Home page: for each day, the
number of characters, dictations and seconds, characters per app (name and
bundle identifier), and dictations per hour. They contain no text. Days older
than 400 days are removed. Nothing is recorded while history is set to never
save, and deleting all history also deletes these totals.

## System permissions

Lerro requests two macOS permissions (Apple Speech needs no separate authorization):

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

The configured AI provider receives the original and corrected spans, up
to 80 UTF-16 units before the change, up to 40 after it, the application name,
and optional bundle identifier. It returns zero to three structured candidates.
Only small lexical corrections with confidence at least 0.7 are stored.
Semantic changes, additions, deletions, tone edits, restructuring, and broad
rewrites are excluded.

Application logs exclude audio, transcripts, selected text, focused text,
changed spans, prompts, model output, dictionary contents, API keys,
authorization headers, invitation codes, and personal identifiers.

## Apple Speech

Apple Speech performs transcription from the microphone audio only; Lerro does
not pass dictionary entries to it.

Lerro automatically prepares the selected Speech language resources at launch,
when the recognition language changes, and before capture as needed. macOS
downloads missing resources through Apple-managed services.

## BYOK remote providers

When API processing is selected, Lerro sends Chat Completions requests directly
to the configured DeepSeek, OpenAI, Gemini, or compatible endpoint using the
user's API key. A connection test sends a fixed synthetic message.

Depending on enabled context categories and the action, a request can include
the raw transcript, application name and type, window title, up to 80 UTF-16
units before the caret, up to 40 after it, selected text needed by the action,
the per-app tone, up to 12 matching dictionary entries, and up to 40 dictionary
terms (shared names and vocabulary, each at most 40 characters) even when they do
not appear in the transcript. Dictionary entries and terms are sent only while the
dictionary context category is enabled; application-scoped terms also require the
application category. Correction learning
uses the smaller span-only payload described above. When you choose 从历史找词 on
the Dictionary page, Lerro compares the raw and final text of AI-processed history
entries on the Mac and sends each changed fragment (at most 20 characters per
side) with up to 40 characters of surrounding final text, the application name,
and the optional Bundle ID to the selected AI. Suggestions, ignored suggestions,
and the IDs of scanned entries are stored in `dictionary-suggestions.json`. The provider receives this
content plus normal connection and billing metadata under its terms.

AI is required for refinement, translation, automatic correction learning, and
per-app tone. Without it, Lerro still provides raw transcription, manual dictionary
management, preview, strict delivery, and recovery.

## Updates

Lerro checks the signed Sparkle feed at `updates.lerroapp.com` every 4 hours
while running and on an explicit user check. Cloudflare receives
ordinary HTTPS metadata and update-selection information such as app version and
platform. Private R2 and D1 storage contains release archives and public release
metadata only.

The update service does not receive audio, transcripts, focused text, changed
spans, dictionary entries, prompts, model output, or provider API keys. Sparkle
verifies each update archive with the embedded Ed25519 public key.

## Backups and removal

macOS backup software can include Application Support data, including plaintext
API keys in `preferences.json`. Removing the app bundle leaves local data in
place. For complete local removal, remove Lerro's Application Support directory
after preserving desired exports. “Clear saved key” removes the API key and
returns Lerro to Apple-only (raw) Dictate.

Material changes to data collection, networking, permissions, or retention must
update this file, `PrivacyInfo.xcprivacy`, usage descriptions, entitlements,
tests, and release notes in the same change.
