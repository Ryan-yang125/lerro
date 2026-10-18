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

## Apple Speech

[`AppleSpeechService.swift`](../Sources/LerroMac/Speech/AppleSpeechService.swift)
uses `SpeechTranscriber(locale:preset:.progressiveTranscription)`. An offline
comparison on 40 of the maintainer's recordings (28 mixed Chinese–English) found
SpeechTranscriber recognized 62% of spoken English words versus 39% for
`DictationTranscriber`, which also dropped whole phrases; SenseVoice-Small reached
59% without live partials or punctuation. `TranscriptSpacing.normalize` removes
the spaces SpeechTranscriber places around CJK punctuation in partial and final
text.

SpeechTranscriber ignores `AnalysisContext.contextualStrings`, so Lerro sends no
dictionary terms to Apple Speech. The dictionary reaches recognition quality
through the AI prompt (`known_terms` and glossary matches).

Speech language assets are checked and prepared automatically at launch and when
the recognition language changes. Capture checks readiness again before opening
the microphone, reserves the locale, and installs missing assets through Apple's
system service. Setup failures expose a retry in Settings and Onboarding.

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
| DeepSeek | `https://api.deepseek.com` | `deepseek-flash` |
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
selected text, up to 12 dictionary matches, up to 40 `known_terms`, and app tone.
Selected text is capped at 4,096 characters.

`known_terms` holds non-snippet dictionary replacements (phrase when the replacement
is empty), trimmed, de-duplicated case-insensitively, at most 40 characters each,
at most 40 terms, ordered application-scoped first, then use count, recency, and
phrase. They are sent whether or not they appear in the transcript, only while the
dictionary context category is on; application-scoped terms also require the
application category. The Dictate system prompt (`dictatePromptVersion`
`J_input_method_fixes_json_v1`, nine examples) treats the transcript as a phonetic
draft: like an input method, every output word must be a real word that fits its
sentence, and a misheard word is replaced by a same- or similar-sounding word,
preferring `known_terms`. A fix must sound like the recognized word, and real words
that fit stay unchanged. The model returns `{"fixes": [[recognized, corrected]],
"text": ...}`; listing fixes first works as a short check without thinking mode.
`CloudPromptComposer.dictateText(from:)` delivers `text`, keeps plain-text replies,
and falls back to the raw transcript for broken JSON. The transcript is never
treated as a request, and code and terminal apps keep backticks.

Prompt selection, 2026-10-18, DeepSeek without thinking, on 7 recent misrecognition
cases, 6 older real cases, 17 checks over 40 replayed dictations, and the 60-case
benchmark: the shipped prompt fixed 2/8 replay misrecognitions; `J_…_v1` on
deepseek-flash fixed 7/7 recent cases and 6/8 replay misrecognitions with the same
benchmark formatting (0.80) and protected-span accuracy (1.0), at a replay median of
0.93 s versus 0.87 s. deepseek-v4-pro fixed fewer (4/8) at 1.3 s and about 4.5 times
the price. Thinking mode fixed the most but took a median of 3.8 s and up to 42 s on
real dictations, so it stays disabled. The Translate prompt may use
`known_terms` to resolve misheard names and terms.

Correction learning uses a smaller payload: original/corrected spans, up to 80 UTF-16
units before, up to 40 after, app name, and optional Bundle ID. The system prompt
accepts lexical recognition corrections and rejects meaning, fact, date/time, tone,
structure, addition, deletion, and broad rewrite changes.

Dictionary suggestions reuse the same classifier. `CorrectionHunkExtractor` diffs
`rawText` against `finalText` of AI-processed history entries and keeps
substitutions of at most 20 characters per side, dropping pure deletions,
insertions, punctuation, case-only changes, and single-character function-word
swaps. Each fragment is sent with up to 40 characters of final-text context, at
most three requests at a time, and candidates with confidence of at least 0.7 are
aggregated in `DictionarySuggestionState`. The scan runs only when the user starts
it and skips entries that were already scanned.

Provider settings and API key are plaintext fields in
`~/Library/Application Support/app.lerro.mac/preferences.json`. The directory is
`0700`, the file is `0600`, and clearing the key switches to Apple raw.

### Usage statistics

`PipelineIntelligenceService` records one `AIUsageRecord` per remote call
(Dictate, Translate, dictionary learning, tone preview, connection test) into
`ai-usage.json` through `AIUsageRepository`. Token counts come from the response
`usage` object: `prompt_tokens`, `completion_tokens`, and cached input from
`prompt_tokens_details.cached_tokens` or DeepSeek `prompt_cache_hit_tokens`. A
failed call is recorded without tokens; a cancelled call is not recorded. Local
and Apple raw processing record nothing.

Settings → 用量 aggregates today, 7 days, and 30 days with `AIUsageStatistics`.
Cost is an estimate from `AIModelPriceTable`: user overrides in
`UserPreferences.modelPrices` first, then `AIModelPrice.builtIn` (DeepSeek list
prices in CNY per 1M tokens, off-peak at half price outside Monday–Friday
9:00–12:00 and 14:00–18:00 Beijing time; public holidays count as peak). Remote
calls are not streamed.

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
