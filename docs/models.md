# Intelligence modes and model providers

Lerro always uses Apple Speech for transcription. Dictate, Command, and Rewrite can
then route the raw transcript through one of three user-selected modes:

- `raw`: direct Dictate output with no language-model call.
- `local`: Qwen through MLX on the current Mac.
- `remote`: a user-configured OpenAI-compatible API.

Translate uses Apple Translation directly and does not depend on the selected
intelligence mode. Command and Rewrite require `local` or `remote`. A capture freezes
the selected mode, Provider configuration, API key, context options, and target
language when recording starts. It also freezes the matching app-style instruction
and whether the target app already has permission to perform a voice finish action.

## Live transcription and finish actions

Apple Speech partial and final events remain the source of the live HUD transcript.
Quick Dictate adds `SpeechDetector` only to endpoint-enabled Dictate sessions. Its
speech/silence results control capture completion and never become model input.
Voice follow-up semantic edits use `rewriteSelection`: the prior delivered version
is the selected text and the new spoken instruction is the transcript. AppSession
freezes local/BYOK configuration at follow-up capture start. Raw mode supports the
deterministic editor only and returns an explicit model-required error for semantic
requests.
Partial text is presentation-only: Lerro never runs it through a language model,
persists it, or writes it into the target application. Only the final event enters
the selected intelligence route.

Hands-free Dictate recognizes an exact trailing `send it` or `发送` command after
the final transcript arrives. The suffix is removed before local or remote processing.
The target app is submitted only after the text has been inserted, the post-delivery
receipt still matches the focused element and its complete value, and the app has
been approved. First use in each app requires an explicit confirmation; successful
confirmation stores the app name and bundle identifier in `preferences.json`.

## Default model

The current default is:

```text
mlx-community/Qwen3.5-4B-MLX-4bit
```

The repository and model page declare Apache-2.0. The expected download is
approximately 3.03 GB; the model page and actual download metadata remain the
source of truth for a release. Lerro asks for explicit consent before starting
the first download.

## Download and cache boundary

- The public Hugging Face client uses `bearerToken: nil`.
- Model files stay under `~/Library/Application Support/app.lerro.mac/Models/`.
- Download progress is monotonic and cancellation propagates to the underlying
  request.
- Complete blobs are staged in the cache directory and published atomically.
- Snapshot or ref failures preserve a complete source for a retry.
- Existing cache data is validated before reuse.
- A legacy migration reuses or moves an existing model on the same volume so an
  upgrade does not create a second multi-gigabyte copy.

### Remove the local cache

Quit Lerro before changing its model cache. In Finder, open
`~/Library/Application Support/app.lerro.mac/Models/`, preserve any desired
backup, and remove only the directory for the model being retired. Keep the
parent Application Support directory and its preferences, history, dictionary,
migration receipt, and audio data intact. The next model-backed action will
show the download-consent and preparation flow again.

The vendored download implementation and upstream provenance live under
[`Vendor/`](../Vendor/). Architecture decision
[`0001`](decisions/0001-vendored-hugging-face-download-stack.md) records the
patch boundary and upgrade procedure.

## Runtime behavior

[`MLXLanguageModelRuntime.swift`](../Sources/LerroIntelligence/MLXLanguageModelRuntime.swift)
owns model loading, generation, cancellation, and idle unloading. Shared load
tasks are committed only after a final cancellation check. Session generation
IDs prevent results from an earlier capture from updating the current capture.

Lerro keeps prompts, transcripts, selected text, answers, API keys and
Authorization headers out of logs. Local generation keeps generation content on
the current Mac.

## BYOK remote providers

The settings UI includes these presets:

| Provider | API base | Default model |
| --- | --- | --- |
| DeepSeek | `https://api.deepseek.com` | `deepseek-v4-flash` |
| OpenAI | `https://api.openai.com/v1` | entered by the user |
| Gemini | `https://generativelanguage.googleapis.com/v1beta/openai` | entered by the user |
| Custom | entered by the user | entered by the user |

All four paths use Chat Completions messages through
[`OpenAICompatibleRemoteLanguageModelRuntime.swift`](../Sources/LerroIntelligence/OpenAICompatibleRemoteLanguageModelRuntime.swift).
DeepSeek requests set temperature to zero and explicitly disable thinking. The
client uses an ephemeral URLSession, accepts HTTPS and loopback HTTP, blocks
cross-origin redirects, caps response bodies, and returns sanitized errors.

The connection test sends one fixed synthetic message and no captured app
context. A normal request always includes the raw transcript. Users can
independently enable application identity, window title, 80/40 cursor context,
selected text, up to 12 matching glossary entries, and the app tone. Selection
context is capped at 4,096 characters; API Rewrite also requires selected-text
sharing and stops before generation when the captured selection exceeds that cap.

Dictate uses [`CloudPromptComposer.swift`](../Sources/LerroCore/Services/CloudPromptComposer.swift)
and prompt version `M_balanced_seven_shot`. The user message is a sorted JSON
payload with raw data, normalization rules, workspace context and
personalization. Local and remote model calls both receive the original Apple
Speech transcript without `TextPipeline` preprocessing.

Provider settings and the API key are stored in plaintext in
`~/Library/Application Support/app.lerro.mac/preferences.json`. The containing
directory is `0700` and the preferences file is `0600`. Clearing the saved key
from the settings page also switches the app to raw Dictate.

### Remote runtime verification

Deterministic tests use a URLProtocol fixture. The explicit DeepSeek smoke uses
the product runtime and only runs when both the environment flag and key exist:

```zsh
./script/test_live_remote.sh
```

The script reads `.env.deepseek.local` when present, requires mode `0600`, and
also accepts an already exported `DEEPSEEK_API_KEY`. The env file is ignored and
must stay outside public exports. The smoke calls the fixed connection probe, generates an
English self-correction sample, then runs the production seven-shot prompt on a noisy Chinese
Apple Speech sample. It prints only latency and pass markers.

## Verification

Normal tests and CI exercise deterministic adapters and keep the real model
smoke disabled. After a maintainer confirms the cache, model ID, network state,
memory budget, and permission to use the local model, run:

```zsh
LERRO_LIVE_MODEL_CACHE="$HOME/Library/Application Support/app.lerro.mac/Models" \
LERRO_LIVE_MODEL_ID='mlx-community/Qwen3.5-4B-MLX-4bit' \
LERRO_LIVE_MODEL_OFFLINE=1 \
./script/test_live_model.sh
```

The release matrix records first download, progress, cancellation, cache hit,
offline load, real generation, idle unload, interrupted download behavior, and
the absence of duplicate model copies after migration. This command is
resource-intensive. With `LERRO_LIVE_MODEL_OFFLINE=1`, a missing cache fails
inside a kernel network-denied sandbox. Omitting the flag permits recovery of
missing cache files from the configured public model host.

Model changes require the model ID, immutable source revision when available,
expected size, license, conversion source, prompt-format compatibility, quality
checks, privacy review, and release-note update.
