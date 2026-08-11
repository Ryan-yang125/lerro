# 架构与代码路由

## 工程形态

Lerro 是 package-first 的原生 macOS GUI 应用。工程入口为
[`Package.swift`](../Package.swift)，最低平台、Swift language mode、生产 target、测试 target 和第三方依赖均以该文件为准。仓库没有 Xcode project；标准 `.app` 由
[`script/build_and_run.sh`](../script/build_and_run.sh) 组装。

当前平台约束：

- Swift tools 6.2。
- Swift 6 language mode。
- macOS 26.0+。
- Release 产物为 Apple silicon arm64。

以上值发生变化时，以 `Package.swift` 和 Release manifest 为准。

## Target 职责

| Target | 职责 | 入口与关键目录 |
| --- | --- | --- |
| `LerroCore` | 领域模型、协议、规则、提示词、文本处理、文件仓库与路径 | [`Sources/LerroCore`](../Sources/LerroCore) |
| `LerroIntelligence` | MLX 模型加载、Hugging Face 下载与缓存，以及 OpenAI-compatible BYOK 网络运行时 | [`Sources/LerroIntelligence`](../Sources/LerroIntelligence) |
| `LerroMac` | Audio、Speech、Accessibility、文本交付、全局热键、权限、登录项与 panels | [`Sources/LerroMac`](../Sources/LerroMac) |
| `Lerro` | SwiftUI scene、设计系统、页面、依赖组合、AppSession 编排 | [`Sources/Lerro`](../Sources/Lerro) |

## 更新与公开分发

[`AppUpdateController.swift`](../Sources/Lerro/App/AppUpdateController.swift) 在正常应用
生命周期中持有 Sparkle 的 `SPUStandardUpdaterController`。它读取
[`Info.plist`](../config/Info.plist) 中的 HTTPS appcast 与 Ed25519 公钥；应用启动时及每
24 小时执行静默信息探测，有更新时显示蓝色下载入口。Home、设置页和下载入口使用同一个
controller 发起用户主动检查与下载。fixture 与 XCTest 进程通过环境门禁跳过 controller，
因此 fixture 保持零网络访问。

公开数据流位于应用进程之外：

```text
Lerro.app -> updates.lerroapp.com/appcast/stable.xml -> D1 stable head
          -> updates.lerroapp.com/download/macos/latest -> 私有 R2 ZIP
lerroapp.com -> lerro-site Worker
```

`lerro-distribution` Worker 只提供读取路由。发布脚本校验已公证且由 Sparkle 签名的 ZIP，
上传不可变 R2 key，再通过带 generation 比较条件的 D1 batch 推进 stable head。完整的密钥、失败和兼容策略见
[ADR-0007](decisions/0007-cloudflare-distribution-and-sparkle-updates.md)。

测试 target 与 source 的实时清单由以下命令给出：

```zsh
swift package describe --type json
```

测试目录按被测边界分为
[`LerroCoreTests`](../Tests/LerroCoreTests)、
[`LerroIntelligenceTests`](../Tests/LerroIntelligenceTests)、
[`LerroMacTests`](../Tests/LerroMacTests) 和
[`LerroTests`](../Tests/LerroTests)。

## 依赖方向

```text
Lerro -> LerroIntelligence -> LerroCore
   |                           ^
   +----------> LerroMac ------+
```

边界要求：

- Core 只使用 Foundation，不能导入 AppKit、Speech、AVFoundation、MLX 或 Hugging Face。
- Intelligence 通过 Core 的 `LocalLanguageModelRuntime`、`RemoteLanguageModelRuntime` 与 `IntelligenceProcessing` 契约向上提供能力。
- Mac 通过 Core 的 `SpeechTranscribing`、`ContextCapturing`、`TextDelivering`、`HotkeyMonitoring`、`PermissionChecking` 和 `LoginItemManaging` 契约提供系统能力。
- Lerro app target 负责组合与交互，不在 view 中直接创建生产 adapter。
- 新第三方依赖先明确所属 target，避免把大依赖传播到 Core 和 UI。

协议入口：

- [`Repositories.swift`](../Sources/LerroCore/Protocols/Repositories.swift)
- [`SpeechTranscribing.swift`](../Sources/LerroCore/Protocols/SpeechTranscribing.swift)
- [`SystemIntegrating.swift`](../Sources/LerroCore/Protocols/SystemIntegrating.swift)

## 模型依赖与 Vendor 边界

根 [`Package.swift`](../Package.swift) 通过本地 path 引入
[`Vendor/swift-huggingface`](../Vendor/swift-huggingface) 和
[`Vendor/swift-transformers`](../Vendor/swift-transformers)。后者的生效 manifest 继续通过 `../swift-huggingface` 使用同一份 patched Hub 实现。这样，`LerroIntelligence` 直接使用的 `HuggingFace` 与 `Tokenizers` 内部使用的 Hub 保持单一 package identity 和单一源码来源。

```text
LerroIntelligence
├── HuggingFace ───────────────> Vendor/swift-huggingface
└── Tokenizers
    └── Vendor/swift-transformers
        └── HuggingFace ───────> ../swift-huggingface
```

当前 Vendor 来源：

| 包 | 上游基线 | 本地增量 | 来源记录 |
| --- | --- | --- | --- |
| `swift-huggingface` | release `0.9.0`，commit `b721959445b617d0bf03910b2b4aced345fd93bf` | 导入 [上游 PR #50](https://github.com/huggingface/swift-huggingface/pull/50) 的进度修复 commit `4abcf1485f3e06456140a1e0d33e72fa0bff273a`；针对 [Issue #52](https://github.com/huggingface/swift-huggingface/issues/52) 增加下载临时文件消费补丁与回归测试 | [`UPSTREAM.md`](../Vendor/swift-huggingface/UPSTREAM.md) |
| `swift-transformers` | release `1.3.3`，commit `2fa33e1f5e7131a7fc64c28e6d161dcec0d24820` | package manifest 接到相邻 patched `swift-huggingface`；其余导入源码保持上游快照 | [`UPSTREAM.md`](../Vendor/swift-transformers/UPSTREAM.md) |

截至 2026-07-30，上游 PR #50 与 Issue #52 状态均为 Open；PR 包含一个进度修复 commit。Vendor 已导入该 commit 并维护临时文件消费增量；升级时需要重新读取 PR、Issue 与最新 release，确认上游是否已经覆盖对应修改。

Release app 会把 resolved checkouts 与 Vendor 中的 `LICENSE*`、`NOTICE*`，以及
Vendor 的 `UPSTREAM.md` 放入 `Contents/Resources/ThirdPartyLicenses`。复验要求
这些记录非空，并与本次构建输入 byte-identical。项目级清单见
[`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md)。

下载与缓存补丁位于
[`HubCache.swift`](../Vendor/swift-huggingface/Sources/HuggingFace/Hub/HubCache.swift) 与
[`HubClient+Files.swift`](../Vendor/swift-huggingface/Sources/HuggingFace/Hub/HubClient+Files.swift)：

- `HubCache.storeFile` 的 `consumeSource` 默认值为 `false`，调用者拥有的普通文件继续保留。
- Apple 下载桥使用锁保护的 `DownloadTaskBox` 记录 task 安装前到达的取消请求；task 安装后会立即取消。delegate 将 `URLError.cancelled` 归一为 `CancellationError`，让上层保持 Swift concurrency 的取消语义。
- ETag-aware 与 generic 下载路径在取得 `tempURL` 后立即设置 `defer` 清理，覆盖随后发生的响应校验、缓存提交、显式 destination 交付、成功返回和抛错出口。
- HEAD 预检的 `FileMetadata` 读取 `X-Linked-Size`。header 提供正数时，ETag blob 的实际 size 若不一致，会在 cached-path 快速返回前删除，随后下载完整 payload。header 缺失或值无效时，该预检保护不生效；size 相同仍依赖 ETag、响应语义和实际模型加载验证内容身份。
- Hub 下载成功后以 `consumeSource: true` 提交 URLSession 临时文件。blob 安装先在 blobs 目录创建唯一 `.partial` staging：同卷优先 hard-link source，无法链接时复制到 staging；校验 staging size 后，通过同目录 rename 或 replace 原子发布最终 blob，并再次校验 installed size。
- 同 ETag blob 已存在且 size 与完整 source 相同时复用；size 不同时用完整 staging 原子替换，避免崩溃遗留的截断 blob 被 snapshot 发布。该保护比较文件大小，内容身份继续由 ETag 与下载响应约束。
- blob 安装完成后提交 snapshot 和可选 ref；metadata 全部成功后才删除临时源。staging 在所有退出路径清理。同 ETag blob 已存在时仍需完成 snapshot/ref 后再消费重复临时源。
- `HubCache.storeFile` 的 snapshot 或 ref 提交失败会向上抛错，并在该调用返回时保持传入 source 完整。`HubClient` 可先执行显式 destination fallback；下载调用最终退出时由 scope cleanup 清理 URLSession temp。已经写入的完整 blob 或 snapshot 可以留在 cache 中，后续重试按内容地址和目标路径完成缺失的元数据。
- [`HubCacheTests.swift`](../Vendor/swift-huggingface/Tests/HuggingFaceTests/HubTests/HubCacheTests.swift) 覆盖首次写入、已有 blob、截断 blob 原子恢复、snapshot commit 故障注入和 ref commit 故障注入；两项失败测试都断言 source 保留，截断恢复测试还断言无 staging 残留。
- `HubClient.downloadFile(..., to: explicitDestination)` 将 cache 写入视为 best effort。snapshot commit 失败导致 cache lookup miss 时，保留的下载临时文件会转移到显式 destination，调用者仍获得完整 payload；未提供 destination 时继续报告 cache path resolution 错误。
- 自动 Range 合并以已经存在的 `<etag>.incomplete` 为入口：请求从文件 size 设置 `Range`，206 响应追加后原子发布 blob。
- ETag-aware Apple 下载把 `cancel(byProducingResumeData:)` 的结果保存为
  `<etag>.resume-data`。下一次请求优先恢复该任务；无效 resume data 会被删除并回到完整下载。
  `MLXLanguageModelRuntime` 同步保存模型 ID 与字节进度，暂停和 app 重启都呈现可继续状态；
  用户选择停止时只清理未完成文件、resume data 与该 checkpoint。

[`MLXLanguageModelRuntime.swift`](../Sources/LerroIntelligence/MLXLanguageModelRuntime.swift) 继续传递该取消语义：等待 load 的调用者取消时会取消底层 load task；await 返回后、`commitLoadedContainer` 前再次执行 `Task.checkCancellation()`。因此已取消的 load 无权提交 container、loaded 状态或 cache marker。

SwiftPM 会按工具链选择 `Package@swift-*.swift`。更新 `swift-transformers` 时必须同时检查
[`Package.swift`](../Vendor/swift-transformers/Package.swift) 与
[`Package@swift-6.1.swift`](../Vendor/swift-transformers/Package@swift-6.1.swift)，并用 `swift package show-dependencies --format json` 确认依赖图中没有第二份远程 `swift-huggingface`。

完整决策、升级与回滚规则见
[ADR 0001](decisions/0001-vendored-hugging-face-download-stack.md)。

## 组合根

[`AppDependencies.swift`](../Sources/Lerro/App/AppDependencies.swift) 是唯一生产组合根。

生产组合先检查旧 bundle 进程，再由
[`ApplicationDataMigrator.swift`](../Sources/LerroCore/Support/ApplicationDataMigrator.swift)
完成旧数据根迁移并准备新目录。文件 repositories、`AppleSpeechService`、
`MLXLanguageModelRuntime` 和 `OpenAICompatibleRemoteLanguageModelRuntime` 只在以上步骤
成功后创建。迁移失败时组合根返回 inert adapters 并向 AppSession 暴露启动错误，捕获与
模型入口保持关闭。

`AppDependencies.live()` 连接：

```text
ApplicationPaths
├── FilePreferencesRepository
├── FileHistoryRepository
├── FileDictionaryRepository
├── AppleSpeechService
├── MLXLanguageModelRuntime
└── OpenAICompatibleRemoteLanguageModelRuntime

macOS adapters
├── MicrophoneLevelTester
├── AccessibilityContextService
├── AccessibilityTextDeliverer
├── GlobalHotkeyMonitor
├── MacPermissionService
├── MacDeviceCapabilityAssessor
└── MacLoginItemManager

PipelineIntelligenceService
├── MLXLanguageModelRuntime
└── OpenAICompatibleRemoteLanguageModelRuntime
```

`AccessibilityTextDeliverer` returns an in-memory `TextDeliveryReceipt` after the
paste consumption window. The receipt binds follow-up Undo, correction, and submit
actions to the actual post-delivery PID, bundle, role/subrole, focused element, and
complete AX value. Core owns the receipt value and finish-action policy; LerroMac
owns AX validation and synthetic key events; AppSession owns the six-second UI state.
The long-lived boundary is recorded in
[ADR 0009](decisions/0009-bound-delivery-receipts.md).

`LERRO_FIXTURE_MODE=1` 选择 fixture 组合。fixture 必须由内存仓库、规则引擎和 inert system adapters 构成；它不能访问磁盘、麦克风、TCC、AX、CGEventTap、剪贴板、登录项或网络。维护时通过
[`AppDependencies.swift`](../Sources/Lerro/App/AppDependencies.swift) 的 fixture adapter 列表核验这一约束。

## App 生命周期与状态所有权

[`LerroApp.swift`](../Sources/Lerro/App/LerroApp.swift) 创建单一
[`AppSession`](../Sources/Lerro/App/AppSession.swift)。`AppSession` 使用 `@MainActor` 和 Observation，拥有：

- 当前 sidebar/settings/onboarding 页面状态。
- `CapturePhase`、`CaptureMode`、generation、active session、设备 AI 建议与异步任务。
- 历史、词典、偏好、模型状态和权限快照。
- HUD 与 Ask panel controller。
- 核心命令：开始、完成、取消、重试、交付、保存和清理。

视图通过 `@Bindable` 读取状态并转发用户意图。跨页面共享状态应继续由 `AppSession` 或 Core store 管理。

Onboarding 的设备策略位于 Core 的 `LocalAIReadiness`，生产硬件读取位于 LerroMac 的
`MacDeviceCapabilityAssessor`。App target 负责呈现本地、API 和基础听写路径。未完成的本地
下载由 AppSession 持有，因此关闭 Onboarding 或主窗口不会取消任务；退出 app 会保留可恢复断点。

设置页把 `UserPreferences` 的旧值与新值一并交给 `AppSession`。持久化仍通过串行合并队列完成；外观、Dock 可见性、全局快捷键和 Login Item 只在各自字段发生变化时访问对应系统服务。启动时完整应用当前外观与 Dock 状态，保存失败时按回滚前后的字段差异恢复对应系统状态。

### 快捷键边界

- Core 的 `HotkeyDefinition` 保存物理 binding 和 `hold` / `toggle` 语义；`HotkeyTrigger` 携带 began/ended 与 definition ID。
- `HotkeySignature` 将 legacy modifier keyCode、Fn 标记和主要 modifier flags 规范化；冲突与迁移去重使用物理 signature。
- `GlobalHotkeyMonitor` 独占 active HID CGEventTap 生命周期、候选、前缀升级、吞键、physical drain、Secure Input watchdog 和 tap restart。tap 只监听 `flagsChanged`、`keyDown` 与 `keyUp`；实体 modifier keyCode 集合区分 Fn 63、Globe 179 和左右同类修饰键，语义匹配继续使用规范化 modifier flags。disabled tap 先取消活动手势，再在 main queue 完整重建；重复 `start` 与相同 definitions 的 `update` 保持当前手势。
- `AppSession` 通过单一 FIFO stream 消费 trigger，将其映射到 capture generation，并校验 hold release 的 definition ID。
- `ShortcutRecorderView` 是一个窄 `NSViewRepresentable` first-responder bridge。SwiftUI reducer 分开维护 live chord、peak chord、已验证候选、模式、校验与视觉状态；AppKit view 只转发本窗口键盘事件，并在检测中被同窗口控件临时抢走焦点后自动恢复 first responder。
- 录制器与生产 monitor 互斥，避免设置按键时触发真实捕获。

## 并发模型

- `AppSession`、窗口和 SwiftUI 状态运行在 `@MainActor`。
- `AppleSpeechService`、`AccessibilityTextDeliverer`、MLX runtime、文件仓库采用 actor 或内部同步保护。
- 跨 actor 的领域值遵循 `Sendable`。
- 捕获启动使用 generation UUID，录音会话使用 session UUID。
- 任务返回 UI 前验证 generation/session 仍然匹配。
- 取消通过 `Task.cancel()`、adapter `cancel()` 和 session 清空共同完成。

任何异步功能都要回答三个问题：

1. 谁拥有任务？
2. 新会话如何使旧结果失效？
3. 取消和异常如何恢复系统资源？

## 数据层

[`ApplicationPaths.swift`](../Sources/LerroCore/Support/ApplicationPaths.swift) 定义 Application Support 目录；
[`JSONDocumentStore.swift`](../Sources/LerroCore/Stores/JSONDocumentStore.swift) 提供 JSON 文档读写；具体 repository 位于
[`Sources/LerroCore/Stores`](../Sources/LerroCore/Stores)。

`preferences.json` 统一保存三种智能处理模式、Provider、Base URL、Model ID、六项上下文
开关、免手发送 app 授权和用户 API Key。API Key 依产品决策以明文 JSON 字段保存；Application Support 根目录
每次准备或迁移时收紧到 `0700`，preferences 文件每次读取或原子替换后收紧到 `0600`。
设置页使用 view-local draft，只有“保存并启用”会提交 Provider 配置。

历史列表通过 `HistoryRepository.page(_:)` 按查询和模式每次读取最多 50 条；
[`FileHistoryRepository.swift`](../Sources/LerroCore/Stores/FileHistoryRepository.swift) 在 actor 内复用稳定排序的
snapshot，分页、统计与连续 mutation 共享同一份解码结果。mutation 以 revision-CAS 提交一次紧凑、确定性的
原子 JSON 写入；磁盘 fingerprint 与 `NSFileCoordinator` 让同一路径的多实例 mutation 保持有序，并让外部更新立即失效缓存。
旧版 pretty-printed JSON 保持可读。历史条目可选保存 raw→processed→corrected 沿袭、
处理路由、模型标识、上下文类别、remote 共享类别、阶段耗时与发送状态；不保存
post-delivery focused value 或 element fingerprint。v1.5 的 `editLineage` 以版本父链保存
原始写入、手动修改、确定性修改、语义修改与重新听写结果。历史视图只渲染已经展示的页面，完整 snapshot 仅用于本地统计、
retention 与录音索引对账。历史和词典搜索先进入视图本地状态，120 ms 可取消延迟后更新缓存结果，避免每次击键重算完整列表。

[`identity.md`](identity.md#legacy-compatibility-boundary) 记录的兼容数据根到
`app.lerro.mac` 的身份迁移位于 Core：

- 单一旧根在同一 Application Support 父目录内经 staging 使用两次同卷 rename 推进，目录与模型 inode 保持不变；receipt 写入完成事务提交。
- 新旧根并存时先完整预检；独有项通过 rename 移动，同名 byte-identical 项去重，内容差异生成 recovery report 并保持零数据变更。
- lock 阻止两个新版本进程同时迁移；journal 支持崩溃后重放；receipt 保证幂等并记录登录项收尾状态。
- receipt 写入前发生错误时整根迁移回滚；并存迁移的每一步均可安全重放，且不执行模型复制。

原则：

- Repository 协议隔离存储形式，后续可以迁移数据库。
- 文件更新保持原子写入和串行化。
- 分页查询保持稳定排序；查询变化使用 generation 隔离过期结果。
- 并发保存、导入与删除必须有竞态测试。
- 偏好 Codable 迁移为新增字段提供旧文档默认值。
- 文件损坏应向上报告；UI 使用安全默认值时保留原文件供恢复。

## UI 与 AppKit 分工

- SwiftUI：主窗口、设置、引导、列表和 panel 内容。
- AppKit：窗口配置、非激活 HUD、可交互 Ask panel、激活策略和系统事件。
- [`FloatingPanelController.swift`](../Sources/LerroMac/Panels/FloatingPanelController.swift) 管理 panel 级别、Space 行为、底部定位和鼠标交互区域。
- [`WindowConfigurator.swift`](../Sources/LerroMac/System/WindowConfigurator.swift) 把 window 配置保持在 Mac target。
- 视觉常量集中在 [`DesignTokens.swift`](../Sources/Lerro/DesignSystem/DesignTokens.swift)。

## 代码放置决策

| 新需求 | 首选位置 |
| --- | --- |
| 可确定性测试的文本、规则、策略 | `LerroCore/Services` |
| 新领域数据或状态 | `LerroCore/Models` |
| 新存储能力 | Core protocol + Core store；组合在 `AppDependencies` |
| 新本地模型或生成策略 | `LerroIntelligence`，通过 Core 协议暴露 |
| 新 macOS API | `LerroMac` adapter，Core 增加窄协议 |
| 新页面 | `Lerro/Features/<Feature>` |
| 跨页面会话编排 | `AppSession`；复杂规则先下沉 Core |
| 通用视觉值或组件 | `DesignSystem` |
| 长期架构改变 | 对应代码 + [`docs/decisions`](decisions/README.md) ADR |

## 构建架构

SwiftPM 依赖生成的 resource accessors 需要标准 app bundle 语义。
[`build_and_run.sh`](../script/build_and_run.sh) 使用 SwiftBuild：

1. 构建指定配置的 `Lerro` product。
2. 取出 arm64 executable 与 dSYM。
3. 创建 `dist/Lerro.app/Contents` 标准布局。
4. 拷贝 SwiftPM bundles、Lerro 图标、隐私文件、条款、第三方许可证和 upstream notices。
5. 校验 resource accessor、架构、binary/dSYM UUID、plist 与签名。
6. 根据 signing mode 签名并选择是否启动。

发布结构和签名模式详见 [`release.md`](release.md)。

## 架构变更要求

以下改动需要 ADR：

- 新生产 target 或反向依赖。
- JSON 存储迁移到数据库。
- Speech provider 或模型 provider 的切换。
- 模型依赖从本地 Vendor 切回远程、变更 Vendor 基线，或调整下载补丁所有权。
- 新网络服务、云同步或账号系统。
- TCC 权限、sandbox、entitlement 或签名策略变化。
- AppSession 状态所有权拆分。
- Apple-native 视觉系统、品牌资产格式或视觉基线策略变化。
