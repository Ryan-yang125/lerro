# Architecture Decision Records

An ADR records a decision that shapes modules, data, permissions, distribution, or the UI baseline, together with the context and trade-offs at the time. The code is the source of truth for current behavior.

| ADR | Decision |
| --- | --- |
| [0002](0002-lerro-product-identity.md) | Product name, targets, Bundle ID, data root |
| [0003](0003-explicit-hotkey-gesture-semantics.md) | `hold` and `toggle`, modifier-only keys, active event tap |
| [0004](0004-transactional-command-v-delivery.md) | Clipboard transaction and Command-V commit point |
| [0006](0006-byok-openai-compatible-providers.md) | Bring-your-own-key OpenAI-compatible runtime, plaintext key in `preferences.json` (provider scope superseded by 0016) |
| [0007](0007-cloudflare-distribution-and-sparkle-updates.md) | Cloudflare Worker, R2, D1 distribution and Sparkle updates |
| [0008](0008-accessibility-owned-fn-shortcuts.md) | Two system permissions and physical ownership of Fn/Globe |
| [0012](0012-strict-delivery-ai-dictionary-learning.md) | Capture-bound strict delivery, recovery, AI dictionary learning |
| [0013](0013-brand-capsule-hud.md) | Single-capsule ink HUD |
| [0014](0014-main-window-rebuild.md) | Native main window, separate Settings window, ink-blue accent |
| [0015](0015-speech-transcriber.md) | `SpeechTranscriber` for live recognition |
| [0016](0016-deepseek-only.md) | DeepSeek is the only AI service; balance from the official endpoint |
| [0017](0017-fixed-sidebar.md) | Fixed-width custom sidebar, hidden title bar, per-page headers (replaces the split view in 0014) |
| [0018](0018-sqlite-history-store.md) | History in SQLite with FTS5 search; one-time import of `history.json` |
| [0019](0019-microphone-prearm-at-modifier-key-down.md) | Microphone prearm at modifier key-down, discarded on combos |

Numbers only increase and are never reused. Gaps are decisions that were superseded or removed together with the feature they covered (local MLX models, delivery receipts, voice edits, the vendored Hugging Face stack).

## When an ADR is needed

Adding or removing a production target or reversing a dependency; replacing the Speech engine or adding an inference backend; adding a network service, account, or sync; adding or removing a TCC permission or entitlement; changing signing, notarization, update, or artifact policy; splitting `AppSession` state ownership; changing audio, history, or secure-input boundaries; changing the visual baseline. Local bug fixes and single-page visual changes do not need one.

## Format

ADRs are written in Chinese. File name `NNNN-short-kebab-title.md`.

- Header list under the title: `- 状态：` with `proposed`, `accepted`, `superseded`, or `rejected` (a superseded ADR names its replacement after the value), `- 日期：`, `- 决策人：`, and when they apply `- 替代：` and `- 关联任务/PR：`.
- Required sections: `## 背景`, `## 决策`, `## 后果`.
- Sections when they apply: `## 备选方案`, `## 隐私与安全`, `## 验证`, `## 迁移与兼容`.

[`validate_agent_workspace.sh`](../../script/validate_agent_workspace.sh) checks the status line and the required sections. When a direction changes, add a new ADR that names the one it replaces and delete the old file if nothing in it is still in effect.
