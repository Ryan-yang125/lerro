# Intelligence modes and model providers

Apple Speech is the only transcription engine. Lerro then selects one of three modes in this fixed product order:

1. `raw`: Apple transcript goes directly to delivery.
2. `remote`: a user-configured OpenAI-compatible API refines or transforms text.
3. `local`: Qwen through MLX on the current Mac refines or transforms text.

New installations start in `raw`. Remote or local AI enables Dictate refinement,
Translate, automatic correction learning, and per-app tone. Apple-only mode keeps
transcription, live preview, strict delivery, recovery, manual dictionary management,
and Apple Speech dictionary context.

A capture freezes the selected mode, Provider configuration, API key, context
options, target language, and matching app tone when recording starts. Partial
transcripts remain presentation-only. The final Apple Speech result enters the
selected intelligence route.

## Apple Speech and personal vocabulary

[`AppleSpeechService.swift`](../Sources/LerroMac/Speech/AppleSpeechService.swift)
uses `DictationTranscriber(locale:preset:.progressiveLongDictation)`. Before the
capture begins, AppSession selects relevant non-snippet dictionary entries for the
target application. Application-scoped entries rank ahead of global entries, followed
by priority, use count, and recency.

`SpeechVocabularyTerm` carries phrase, replacement, application scope, and priority.
Apple Speech receives at most 100 unique strings through
`AnalysisContext.contextualStrings[.general]`; replacement is preferred, with phrase
used when replacement is empty. Case and diacritic folding removes duplicates.

Quick Dictate installs `SpeechDetector` only for explicitly enabled Dictate sessions.
It starts disabled. Once enabled, detected first speech followed by about 1.2 seconds
of continuous silence requests capture completion. Detector results never enter AI.

## AI tasks

`IntelligenceTask` exposes two production transformations:

- `polish`: refine a Dictate transcript using enabled context, dictionary, and app tone.
- `translate`: translate to the selected target language.

Automatic dictionary learning uses a separate structured classification method on
`IntelligenceProcessing`. It receives a `DictionaryLearningRequest` with the smallest
original/corrected spans, bounded nearby context, app name, and optional Bundle ID.
The local or remote runtime must return exactly one JSON object containing zero to
three candidates. Extra fields, code fences, invalid source spans, or invalid
confidence values reject the full result.

AI Dictate generation failure falls back to the Apple Speech transcript. Translate
and tone preview report an explicit failure. A new capture or cancellation prevents
an old model result from committing.

## Default local model

```text
mlx-community/Qwen3.5-4B-MLX-4bit
```

The repository and model page declare Apache-2.0. The expected download is about
3.03 GB; release evidence and current host metadata remain authoritative. Lerro asks
for explicit consent before the first download.

Onboarding reads chip class, Metal availability, physical memory, and free storage
locally. Apple silicon with Metal, at least 16 GiB memory, and at least 10 GiB free
storage receives the local-AI recommendation. Constrained devices receive the API
recommendation. The user can select any supported path.

## Download and cache boundary

- The public Hugging Face client uses `bearerToken: nil`.
- Model files stay under `~/Library/Application Support/app.lerro.mac/Models/`.
- Progress is monotonic and reports transferred bytes, total bytes, and estimated rate when available.
- Pause persists URLSession resume data and a small checkpoint before cancelling the active request.
- Closing Onboarding or the main window leaves the AppSession-owned download running.
- Relaunch restores the checkpoint and can continue from resume data.
- Stop removes incomplete files, resume data, and the Lerro checkpoint; complete blobs remain.
- Complete blobs are staged and atomically published; cache content is validated before reuse.
- Identity migration moves or reuses an existing model on the same volume to avoid another 3 GB copy.

The vendored download implementation and provenance live under [`Vendor/`](../Vendor/).
[ADR 0001](decisions/0001-vendored-hugging-face-download-stack.md) records the patch boundary.

### Remove the local cache

Quit Lerro. In Finder open
`~/Library/Application Support/app.lerro.mac/Models/`, preserve any desired backup,
and remove only the retired model directory. Keep the parent Application Support
directory, preferences, history, dictionary, migration receipt, and audio. The next
local action returns to download consent.

## Runtime behavior

[`MLXLanguageModelRuntime.swift`](../Sources/LerroIntelligence/MLXLanguageModelRuntime.swift)
owns loading, generation, cancellation, and idle unloading. A shared load commits its
container only after a final cancellation check. Capture generation IDs keep an old
result from updating a new session.

While a selected local model is downloading or paused, current Dictate uses Apple
raw and preserves the local preference. Local refinement, translation, automatic
learning, and tone preview become available when the runtime reports ready. Local
generation content remains on the Mac. Logs exclude prompts, transcript text,
changed spans, output, API keys, and Authorization headers.

## BYOK remote providers

| Provider | API base | Default model |
| --- | --- | --- |
| DeepSeek | `https://api.deepseek.com` | `deepseek-v4-flash` |
| OpenAI | `https://api.openai.com/v1` | entered by the user |
| Gemini | `https://generativelanguage.googleapis.com/v1beta/openai` | entered by the user |
| Custom | entered by the user | entered by the user |

All paths use Chat Completions through
[`OpenAICompatibleRemoteLanguageModelRuntime.swift`](../Sources/LerroIntelligence/OpenAICompatibleRemoteLanguageModelRuntime.swift).
DeepSeek uses temperature zero with thinking disabled. The ephemeral URLSession
accepts HTTPS and loopback HTTP, blocks cross-origin redirects, caps response bodies,
and sanitizes user-facing errors.

The connection test sends one fixed synthetic message with zero capture context.
Normal refinement and translation always include the raw transcript. Optional
categories are application identity, window title, 80/40 caret context, required
selected text, up to 12 dictionary matches, and app tone. Selected text is capped at
4,096 characters.

Correction learning uses a smaller payload: original/corrected spans, up to 80 UTF-16
units before, up to 40 after, app name, and optional Bundle ID. The system prompt
accepts lexical recognition corrections and rejects meaning, fact, date/time, tone,
structure, addition, deletion, and broad rewrite changes.

Provider settings and API key are plaintext fields in
`~/Library/Application Support/app.lerro.mac/preferences.json`. The directory is
`0700`, the file is `0600`, and clearing the key switches to Apple raw.

### Remote runtime verification

Deterministic tests use a URLProtocol fixture. The explicit DeepSeek smoke uses the
product runtime only when the environment flag and key are available:

```zsh
./script/test_live_remote.sh
```

The script reads an ignored mode-`0600` `.env.deepseek.local` or exported
`DEEPSEEK_API_KEY`. It prints latency and pass markers without request or response
content.

## Verification

Normal tests and CI use deterministic adapters. After recording model ID, cache,
network state, hardware, and authorization, run the real local smoke:

```zsh
LERRO_LIVE_MODEL_CACHE="$HOME/Library/Application Support/app.lerro.mac/Models" \
LERRO_LIVE_MODEL_ID='mlx-community/Qwen3.5-4B-MLX-4bit' \
LERRO_LIVE_MODEL_OFFLINE=1 \
./script/test_live_model.sh
```

The Release matrix records first download, background progress, pause, resume, stop,
restart continuation, cache hit, offline load, generation, idle unload, and duplicate
model-copy checks. With `LERRO_LIVE_MODEL_OFFLINE=1`, missing cache data fails inside
a network-denied sandbox.

Model changes require source revision, expected size, license, conversion source,
prompt compatibility, quality checks, privacy review, and release-note updates.
