# 架构

Lerro 是 package-first 的原生 macOS GUI 应用，没有 Xcode project。平台、target 和依赖以
[`Package.swift`](../Package.swift) 为准：Swift tools 6.2、Swift 6 language mode、macOS 26.0+、
Apple silicon arm64，唯一的 SwiftPM 第三方依赖是 Sparkle。标准 `.app` 由
[`script/build_and_run.sh`](../script/build_and_run.sh) 组装。

## Target 与依赖方向

```text
Lerro -> LerroIntelligence -> LerroCore
   |                           ^
   +----------> LerroMac ------+
```

| Target | 职责 |
| --- | --- |
| [`LerroCore`](../Sources/LerroCore) | 只依赖 Foundation：模型、协议、提示词、规则、文件仓库与路径 |
| [`LerroIntelligence`](../Sources/LerroIntelligence) | OpenAI-compatible 远程运行时（`OpenAICompatibleRemoteLanguageModelRuntime`） |
| [`LerroMac`](../Sources/LerroMac) | AppKit、Accessibility、AVFoundation、Core Audio、Speech、CGEventTap、ServiceManagement 适配 |
| [`Lerro`](../Sources/Lerro) | SwiftUI 场景、设计系统、页面、依赖组合、`AppSession` 编排 |

规则：

- Core 不导入 AppKit、Speech、AVFoundation。系统能力通过 Core 中的窄协议注入
  （[`SystemIntegrating.swift`](../Sources/LerroCore/Protocols/SystemIntegrating.swift)、
  [`SpeechTranscribing.swift`](../Sources/LerroCore/Protocols/SpeechTranscribing.swift)、
  [`Repositories.swift`](../Sources/LerroCore/Protocols/Repositories.swift)）。
- 视图读取状态并转发用户意图，生产 adapter 只在组合根创建。
- [`AppDependencies.live()`](../Sources/Lerro/App/AppDependencies.swift) 是唯一生产组合根；fixture 组合全部使用内存仓库和 inert adapters。
- 新增第三方依赖先确定所属 target，避免传播到 Core 和 UI。

## 状态所有权与并发

[`LerroApp.swift`](../Sources/Lerro/App/LerroApp.swift) 创建单一 [`AppSession`](../Sources/Lerro/App/AppSession.swift)
（`@MainActor`，Observation）。它拥有侧栏目的地、设置标签、onboarding 状态、`CapturePhase`、
generation、历史、词典、偏好、权限快照、HUD controller、恢复卡和异步任务。

- Speech、文本交付、文件仓库使用 actor 或内部同步保护；跨 actor 的值遵循 `Sendable`。
- 每次录音有独立的 capture generation 和 session ID。任务返回 UI 前校验二者仍然匹配，旧结果只能做资源清理。
- 异步功能需要回答：谁拥有任务；新会话如何使旧结果失效；取消和异常如何恢复系统资源。

## 捕获流程

```text
idle -> listening -> transcribing -> enhancing -> inserting -> success -> idle
任意未提交阶段 -> cancelled -> idle        任意错误出口 -> failed
```

主路径：快捷键开始，居中实时预览，同一快捷键结束，严格写入，HUD 在 commit point 淡出，session 同时回到 `idle`。

1. **启动**：忽略设置或 onboarding 录制快捷键期间的触发；`transcribing`、`enhancing`、`inserting`
   阶段忽略重复开始或停止。检查麦克风、辅助功能和安全输入框；冻结目标应用、输入元素、完整文本值、
   选区、安全状态指纹，以及 AI 整理开关、API Key、上下文开关、语气和目标语言。
2. **收音**：等待当前语言的 Apple Speech 资源就绪后立即打开麦克风，HUD 显示。麦克风打开后在后台准备
   `SpeechTranscriber` 与 `SpeechAnalyzer`，音频按顺序缓存在内存，分析器就绪后先送缓存再送实时音频。
   空闲时 `AppleSpeechService` 保留一个已建好但未启动的 `AVAudioEngine`。单修饰键快捷键按下时（`armed`）先预开麦克风，
   音频只缓存在内存；确认后 `start` 接管它，组合键（`disarmed`）直接丢弃；蓝牙输入不预开麦
   （[ADR 0019](decisions/0019-microphone-prearm-at-modifier-key-down.md)）。
3. **转写**：`SpeechTranscriber` 使用 `.progressiveTranscription`（[ADR 0015](decisions/0015-speech-transcriber.md)），
   partial 只用于预览。`TranscriptSpacing.normalize` 去掉中文标点两侧的空格。Apple Speech 不接收词典内容。
4. **处理**：AI 整理关闭（`raw`）或没有 API Key 时，Dictate 把 Apple transcript 直接交付，Translate 在开始前失败并提示开启 AI 整理。
   `remote` 模式下 Dictate 由 `PipelineIntelligenceService` 整理，Translate 翻译。Dictate 的模型失败回退原始 transcript，
   Translate 保持明确失败。DeepSeek 返回余额不足（HTTP 402）时，Dictate 回退原文，HUD 显示「DeepSeek 余额用完了，这次写的是原文」，
   Translate 以「DeepSeek 余额用完了」失败。
5. **交付**：见下节。交付返回后启动词典学习观察，清空 session，回到 `idle`。随后在后台按提交顺序串行保存历史
   （`historyRetention == .never` 时跳过），更新用量和词典使用次数，累计 AI 标出的专有名词；这些保存出错时使用 app 级提示。
6. **取消**：取消信号贯穿启动、Speech、模型任务和 Command-V 提交前检查。统一清理：停止音频、释放 Core Audio
   静音快照并恢复输出音频、取消各类任务、删除未持久化录音、重置热键临时状态。

**提示音**：`playsCaptureSounds`（默认开启）控制开始与结束提示音。[`CaptureSoundPlayer`](../Sources/LerroMac/Audio/CaptureSoundPlayer.swift)
启动时加载 `Contents/Resources/Sounds` 下的两个 `.caf` 并 `prepareToPlay()`，播放时不再读盘。`CaptureSoundPlaying.play` 在声音播放结束（或 1.5 秒安全超时）后才返回。
开始音在 capture 被接受时播放，麦克风照常立即打开；`AppSession` 等开始音播完，且 capture 仍在 `listening` 时，
才调用 `SpeechTranscribing.lowerOtherAudio()` 降低其他声音，避免休眠后唤醒较慢的输出设备吞掉开始音。
结束音在用户完成 capture 时播放，取消和失败不播放。`finishCapture` 先 `await speech.endAudioCapture()`（关闭麦克风并立即恢复输出音频），
再不阻塞地播放结束音并调用 `speech.stop()` 等待最终转写，因此“录音时降低其他声音”不会静音结束音。fixture 使用 inert 播放器。

每次 capture 有一个 [`CaptureTrace`](../Sources/LerroCore/Models/CaptureTrace.swift)（起点为物理按键时刻，
`ContinuousClock` 里程碑）。结果写入 os.Logger `app.lerro.mac` / `capture-trace`、Points of Interest signpost 和历史的
`phaseTimings`；[`script/capture_latency_report.py`](../script/capture_latency_report.py) 只读打开本机 `history.sqlite`
输出各区段 p50 / p90；`microphoneLive`（按键到麦克风开始收音）用于比较预开麦前后，`--prearm yes|no` 按是否预开麦筛选。

## 快捷键

- Core 的 `HotkeyDefinition` 保存物理 binding 与 `hold` / `toggle` 语义；冲突按规范化物理 `HotkeySignature` 判断。
- `hold`：began 启动，同一 definition ID 的 ended 完成。`toggle`：第一次 began 启动，第二次 began 完成。
- `GlobalHotkeyMonitor` 独占 active HID CGEventTap：监听 `flagsChanged`、`keyDown`、`keyUp`，单修饰键先成为候选
  （hold 120 ms 后激活；toggle 松开时确认，按住超过 1 秒或期间点击鼠标则作废；Dictate / Translate 的候选发 `armed`，
  作废时发 `disarmed`），命中的普通键吞掉 down、repeat 与 up，未命中的系统 chord 透传。Fn 63 与 Globe 179 映射到同一语义。
  Lerro 合成的 Command-V 带 source marker 并始终透传。tap 被禁用时先取消活动手势，再在 main queue 重建。
- trigger 通过单一 FIFO stream 进入 `AppSession`。Fn 前缀升级为更具体的 chord 时，依次取消旧 capture、
  转交物理按键所有权并启动新 action。决策见 [ADR 0003](decisions/0003-explicit-hotkey-gesture-semantics.md) 与
  [ADR 0008](decisions/0008-accessibility-owned-fn-shortcuts.md)。
- 设置和 onboarding 录制快捷键时暂停生产 dispatch。

## 严格交付

[ADR 0004](decisions/0004-transactional-command-v-delivery.md) 与
[ADR 0012](decisions/0012-strict-delivery-ai-dictionary-learning.md) 定义交付：

1. `AccessibilityTextDeliverer` 在写入前确认 secure input 关闭，前台应用、focused element、role/subrole、完整 AX value
   与选区仍与 capture 时的指纹一致。任一漂移都停止写入。
2. 事务保存剪贴板全部 item/type，写入 session marker、transient type 和最终文本，发布 Command-V down/up。
   两个事件发布完成是 commit point；commit 前仍可取消，commit 后交付立即返回并忽略取消。
3. commit 后在后台等待固定 500 ms，session 仍拥有临时内容时恢复剪贴板快照；其他应用已写入新内容时保留新内容。
   下一次交付先等待上一次恢复结束，再保存剪贴板快照。
4. 失败时 `PasteboardRecoveryTextCopier` 把最终文本留在剪贴板，历史保存 failed 记录和最终文本，HUD 显示含「再次复制」
   与「关闭」的恢复卡。

## AI 整理

| 模式 | 行为 |
| --- | --- |
| `raw` | Apple transcript 直接交付，新安装的默认值 |
| `remote` | 用户自己的 DeepSeek API Key，只支持 DeepSeek（[ADR 0016](decisions/0016-deepseek-only.md)） |

- API Key 与上下文开关保存在 `preferences.json`；API Key 为明文字段。地址固定为 `https://api.deepseek.com`，模型固定为
  `deepseek-flash`，使用 temperature 0 并关闭 thinking。用户界面不提供服务商、模型和地址选项。
- [`OpenAICompatibleRemoteLanguageModelRuntime`](../Sources/LerroIntelligence/OpenAICompatibleRemoteLanguageModelRuntime.swift)
  使用 Chat Completions，ephemeral URLSession，阻止跨 origin 重定向，限制响应大小，错误信息经过脱敏。连接测试只发送固定合成消息。
  HTTP 401 与 403 映射为 `LerroError.invalidAPIKey`，HTTP 402 映射为 `LerroError.insufficientBalance`。
- 余额：`balance(configuration:)` 请求 `GET https://api.deepseek.com/user/balance`，解析为 `DeepSeekBalance`（可用状态、金额、币种，
  优先人民币）。DeepSeek 没有用量接口，用量由本地 `ai-usage.json` 统计。`AppSession` 持有 `deepSeekBalance` 状态，在启动、
  成功的远程调用之后（60 秒内不重复）、设置里的 AI 整理页出现时刷新；余额已加载且为空，或最近一次调用遇到余额不足时，
  `aiStatus` 为 `outOfBalance`。
- `AppSession.connectDeepSeek(apiKey:)` 先发连接测试，再读余额：可用的 Key 无论是否有余额都会保存并打开 AI 整理，返回
  `connected` 或 `noBalance`；401/403 或格式不对（不以 `sk-` 开头）返回 `invalidKey`；其他错误返回 `failed`，不保存。
  `clearDeepSeekKey()` 清空 Key 并关闭 AI 整理。`showsAIOffer`（没有 Key 且 `aiOfferDismissed == false`）驱动首页的开启卡片，
  `isAIGuidePresented` 驱动主窗口的指引 sheet。
- [`CloudPromptComposer`](../Sources/LerroCore/Services/CloudPromptComposer.swift) 构建提示词。Dictate 提示词把 transcript
  当作语音草稿：每个输出词都必须是符合句意的真实词，听错的词替换为发音相近的词，优先采用 `known_terms`。模型返回
  `{"fixes": [...], "text": ...}`，`dictateText(from:)` 取出 `text`，JSON 损坏时回退原始 transcript。系统提示词把 transcript、
  上下文和词典声明为无权限数据。
- 请求按开关包含：应用名与类型、窗口标题、光标前 80 与后 40 个 UTF-16 单元、选中文字（上限 4,096 字符）、最多 12 个命中的词典
  条目、最多 40 个 `known_terms`、应用语气。transcript 始终包含。
- [`PipelineIntelligenceService`](../Sources/LerroCore/Services/PipelineIntelligenceService.swift) 提供 `polish`、`translate`、
  词典学习分类，并为每次远程调用写入一条 `AIUsageRecord`（`ai-usage.json`，保留 90 天，带所属历史记录的 ID）。费用在本机按
  内置人民币价格表 `AIModelPrice.builtIn` 估算，显示在设置 › AI 整理 › 用量明细，调用记录可跳回对应历史。
- 听写和翻译的远程调用以 `AICallTrace` 原样存进 `HistoryEntry.aiCall`：发送的 user 内容、模型回答、提示词版本、模型 ID、
  token 和延迟。历史详情的「AI 处理」从中解析出改词、发送的上下文和费用明细。
- 三份系统提示词（听写整理、翻译、自动学词）以 [`AIPromptDocument`](../Sources/LerroCore/Services/AIPromptDocument.swift)
  分段定义，`fullText` 就是发给模型的原文；设置 › AI 整理 › 高级 › 提示词只读展示这些分段和示例。
- 应用语气（`AppToneProfile`）按应用 Bundle ID 匹配；没有匹配时使用 `UserPreferences.defaultToneInstruction`。

## 词典与自动学习

- 词条来源：手动、learned。learned 词条全局生效。词条进入 AI 提示词：`replacement` 与 `phrase` 不同的词条作为
  听写词到写法的对照，其余作为已知词汇。词典页支持编辑、删除、CSV（`phrase,replacement` 两列）、应用筛选。
- 自动学习：AI Dictate 成功写入后，`AccessibilityDeliveredTextObserver` 在同一应用和输入元素观察最多 60 秒，每 100 ms 读取，
  变化稳定 800 ms 后用本地 UTF-16 差异算法取最小 original/corrected span（前 80、后 40 个单元的上下文）。AI 返回严格 JSON
  的 0 至 3 个候选，confidence 不低于 0.7 且来源于输入 span 的候选保存为全局 learned 词条，HUD 显示 3 秒提示，可撤销。
  语义、事实、日期、语气、增删句或大段重写返回空候选。离开应用或字段、secure input、AX 不可用、新 capture、超时都会安静结束观察。
- 专有名词学习：Dictate 的 JSON 回复含 `fixes`（听错 → 改对）和 `terms`（其中的专有名词）。历史记录保存成功、带 `aiCall`
  且自动词典学习开关开启时，`AppSession` 调用 `TermLearner.observe` 累计候选；同一个词出现在 2 条不同听写里，就以
  `phrase == replacement`、`source = .learned` 的常用词条加入词典，记录 `heardAs`（曾被听成的样子）和
  `learnedFromEntryIDs`（来源历史记录），HUD 提示可撤销。撤销提示或在词典页删除这类词条会把词加入 `dismissed`，之后不再学习。
  候选和 `dismissed` 由 `TermLearningRepository` 保存在 `term-candidates.json`。
- 使用次数：每次听写写入成功后，`DictionaryUsageCounter` 对最终文字统计词条，变化的词条 `useCount + 1`
  并更新 `lastUsedAt`。首页的本周摘要由 `DictionaryWeek.summary` 从历史和词典计算，随首页统计一起刷新。

## 存储

[`ApplicationPaths`](../Sources/LerroCore/Support/ApplicationPaths.swift) 指向
`~/Library/Application Support/app.lerro.mac/`（目录 `0700`）：

| 文件 | 内容 |
| --- | --- |
| `preferences.json`（`0600`） | 偏好、API Key、上下文开关 |
| `history.sqlite`（`0600`，WAL 模式另有 `-wal`、`-shm`） | 听写记录：raw/final 文本、路由、模型 ID、上下文类别、阶段耗时、交付状态、AI 调用原样记录（`aiCall`） |
| `dictionary.json` | 词典，含每个词条的使用次数、最近使用时间，以及自动学会词条的听错写法和来源历史 ID |
| `term-candidates.json`（`0600`） | 专有名词学习状态：候选词、曾被听成的写法、出现过的历史记录 ID，以及被用户删除而不再学习的词；随全部历史一起删除，`historyRetention == .never` 时不写入 |
| `ai-usage.json` | 远程调用的时间、功能、模型 ID、token 数、延迟、成败、所属历史 ID |
| `usage-days.json` | 首页统计的每日汇总：字数、次数、时长、各应用字数、各小时次数；不含文字，保留 400 天 |
| `Audio/` | 可选录音（CAF），`saveAudio` 默认关闭 |

历史由 [`SQLiteHistoryRepository`](../Sources/LerroCore/Stores/SQLiteHistoryRepository.swift) 存进 SQLite（系统 `libsqlite3`，
WAL）：每条记录一行，`created_at`、`mode`、`status`、文字、应用、录音路径是列，完整记录是 JSON 列；FTS5 trigram 表索引
`final_text` 和 `application_name`。分页、搜索、计数、按 ID 或时间取记录都在数据库里完成，`AppSession` 不读取全部历史；
`entries()` 只用于一次性的每日用量补建。首次打开时若有旧的 `history.json`，导入一次后删除。见 [ADR 0018](decisions/0018-sqlite-history-store.md)。

其他仓库通过 [`JSONDocumentStore`](../Sources/LerroCore/Stores/JSONDocumentStore.swift) 原子写入并串行化。偏好新增字段为旧文档提供默认值。
文件损坏时向上报告并保留原文件。删除历史先删除音频再移除索引；历史索引读取失败时保留孤儿音频。

## 隐私边界

- 原始音频默认关闭；`historyRetention == .never` 时不写入新历史和录音。
- 日志不含 transcript、选中或焦点文本、提示词、模型回答、词典内容、API Key、Authorization header、邮箱和个人路径。
- 历史不保存 focused value、元素指纹和词典学习的差异片段，这些只存在于进程内。
- 网络只有三类：Apple 管理的 Speech 语言资源下载、`api.deepseek.com`（AI 整理请求和 `/user/balance` 余额读取）、`updates.lerroapp.com` 的 Sparkle 更新检查。
  没有产品遥测。
- 系统权限只有麦克风和辅助功能（`SpeechAnalyzer` 不需要 Speech Recognition 授权）。用户在系统设置中授权，签名身份变化会产生新的 TCC 条目。
- 用户可读的说明见 [`PRIVACY.md`](../PRIVACY.md)。

## 更新与分发

[`AppUpdateController`](../Sources/Lerro/App/AppUpdateController.swift) 持有 Sparkle `SPUStandardUpdaterController`，读取
[`Info.plist`](../config/Info.plist) 中的 appcast 与 Ed25519 公钥，启动时及每 4 小时静默探测。fixture 与 XCTest 进程不创建它。
`updates.lerroapp.com` 是 Cloudflare Worker（D1 + 私有 R2），决策见
[ADR 0007](decisions/0007-cloudflare-distribution-and-sparkle-updates.md)，Worker 说明见
[`distribution/README.md`](../distribution/README.md)。

## UI

- 主窗口为隐藏标题栏的窗口，左侧是 220 pt 固定侧栏（首页、历史、词典、应用语气），每页顶部是 `LerroPageHeader`（[ADR 0017](decisions/0017-fixed-sidebar.md)）；设置位于 `Settings` 场景（⌘,），标签为通用、听写、AI 整理、
  隐私、关于；用量明细是 AI 整理页里的二级页面（`aiSettingsShowsUsage`）。`AppSession.openSettings(_:)` 选中标签并打开设置窗口。菜单栏面板单独呈现。决策见 [ADR 0014](decisions/0014-main-window-rebuild.md)。
- HUD 是 40 pt 高的墨黑玻璃胶囊，宽度最大 480 pt，所有状态在同一胶囊内形变，由
  [`AppSession.currentHUDVisualState`](../Sources/Lerro/App/AppSession.swift) 与
  [`CaptureHUDModel.swift`](../Sources/Lerro/Features/HUD/CaptureHUDModel.swift) 决定，见
  [ADR 0013](decisions/0013-brand-capsule-hud.md)。HUD 面板保持非激活，出现在输入框所在屏幕。
- 颜色、字号、尺寸集中在 [`DesignTokens.swift`](../Sources/Lerro/DesignSystem/DesignTokens.swift)，共享控件在
  [`MainWindowComponents.swift`](../Sources/Lerro/DesignSystem/MainWindowComponents.swift)。品牌资产与规则见 [`Brand/`](../Brand/README.md)。

## 代码放置

| 需求 | 位置 |
| --- | --- |
| 可确定性测试的规则、提示词、策略 | `LerroCore/Services` |
| 领域数据与状态 | `LerroCore/Models` |
| 存储 | Core 协议 + Core store，在 `AppDependencies` 组合 |
| 远程模型协议 | `LerroIntelligence`，通过 Core 协议暴露 |
| macOS API | `LerroMac` adapter + Core 窄协议 |
| 页面 | `Lerro/Features/<Feature>` |
| 跨页面编排 | `AppSession`，复杂规则下沉 Core |
| 视觉常量与共享控件 | `DesignSystem` |

## 需要 ADR 的变化

新增或重组生产 target、反向依赖；JSON 存储换成数据库；替换 Speech 引擎或新增推理后端；新增网络服务、账号或同步；新增或移除
TCC 权限、entitlement；改变签名、公证、更新或产物策略；拆分 `AppSession` 的状态所有权；改变音频、历史或安全输入框边界。
模板与索引见 [`decisions/README.md`](decisions/README.md)。
