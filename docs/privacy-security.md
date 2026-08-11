# 隐私与安全边界

Lerro 是本地优先的语音输入工具，并提供用户主动配置的 BYOK API 模式。默认值、逐项上下文开关、协议边界、fail-closed 交付和可审计资源声明共同约束数据流。

## 数据地图

[`ApplicationPaths.swift`](../Sources/LerroCore/Support/ApplicationPaths.swift) 定义默认根目录：

```text
~/Library/Application Support/app.lerro.mac/
├── preferences.json
├── history.json
├── dictionary.json
├── Audio/
│   └── <uuid>.caf
└── Models/
    ├── Hugging Face / MLX cache
    ├── model-ready markers
    ├── URLSession resume data
    └── .lerro-model-download.json
```

| 数据 | 内容 | 默认写入 | 删除方式 |
| --- | --- | --- | --- |
| Preferences | 语言、设备 UID、外观、热键、本地资料、模型授权、Provider、Base URL、Model ID、明文 API Key、上下文开关、语音发送 app 名称/bundle、引导状态 | 是 | 设置页清除 Key/语音发送 app，或用户删除应用数据目录 |
| History | raw/processed/corrected text、修改版本父链与指令、模式、目标 app 元数据、处理路径、上下文类别、remote 共享类别、阶段耗时、语音发送状态、可选录音相对路径 | retention 非 `never` 时 | 应用内单条/全部删除与 retention |
| Dictionary | 手动词条、自动学习词条、app scope、使用信息 | 有词条时 | 应用内删除 |
| Audio | 原始麦克风 CAF | 默认关闭；明确开启且 retention 非 `never` 时 | 删除历史、retention、取消/错误清理、启动对账 |
| Models | 模型权重、tokenizer、缓存 marker、断点续传数据、无内容的下载进度 checkpoint | 用户确认下载后 | 设置中的“停止”清理未完成断点；用户可删除 Models 目录 |
| Remote request | 原始 transcript 与用户允许的上下文；仅存在于请求生命周期 | 选择并启用 API 模式后 | 依 Provider 条款；Lerro 不建立服务端副本 |

本地邮箱、邀请码和 onboarding 选择存入 preferences；Lerro 没有自建远程账号提交路径。
Application Support 根目录在准备和迁移时强制为 `0700`，`preferences.json` 在读取与原子
替换后强制为 `0600`。同一 macOS 用户权限下运行的软件仍可读取明文 API Key，系统备份和
手动复制也可能携带该字段。

Onboarding 的设备建议只读取芯片类型、Metal 可用性、物理内存和目标卷可用空间。这份快照
只保留在当前进程内，不写入 preferences、history、日志或网络请求。下载 checkpoint 只保存
模型 ID、完成比例和字节数，不包含 transcript、prompt、上下文或凭据。

### 旧数据根迁移

首次使用 Lerro 时，`AppDependencies.live()` 在任何文件 repository 或 MLX runtime
创建前检查 [`identity.md`](identity.md#legacy-compatibility-boundary) 记录的兼容数据根。
迁移范围只限该旧根和当前 `app.lerro.mac` 根：

- 单一旧根以同卷 rename 移动，模型权重不会产生复制。
- 两个根并存时先进行完整内容预检；byte-identical 文件只保留一份，独有文件以 rename 移动。
- 同名内容差异保持原位，并在共同父目录写入只含相对路径与冲突类型的 recovery report。
- lock、journal 与 receipt 不记录 transcript、词典内容、音频内容、凭据或用户绝对路径。
- 迁移回执完成后旧根再次出现时启动保持 fail-closed，等待用户确认旧版进程与数据来源。

## 系统权限

| 权限 | 用途 | 声明或检查位置 |
| --- | --- | --- |
| 麦克风 | AVAudioEngine 收音、引导麦克风测试 | [`Info.plist`](../config/Info.plist)、[`MacPermissionService`](../Sources/LerroMac/System/MacPermissionService.swift) |
| Accessibility | 捕获有限上下文、读取并验证焦点与选区、提交 Command-V、运行 active shortcut filter | `MacPermissionService`、Accessibility adapters、`GlobalHotkeyMonitor` |

TCC 授权由用户和 macOS 控制。usage description、entitlement 和代码签名只提供系统声明与身份，不能代替授权。

Apple Speech、SpeechDetector 与传统 Apple Translation 由系统管理语言资源。Lerro 使用 SwiftUI
系统资源准备流程，并在快捷键运行时只调用已安装的本地资源；这两项能力不增加
Speech Recognition、Input Monitoring 或 Translation TCC。

快捷键录制器只在 Lerro 当前窗口内观察用户主动测试的按键并即时显示状态。进入录制器时
生产 global event tap 暂停；候选按键只写入本地偏好，不写入日志、历史或网络请求。

## 上下文最小化

[`AccessibilityContextService.swift`](../Sources/LerroMac/Accessibility/AccessibilityContextService.swift) 捕获：

- 前台 app 名称、PID 和 bundle ID。
- 当前窗口标题。
- 最多 4,096 字符的 selected text。
- 完整选区的进程内 fingerprint，仅用于交付前检测超出 prompt 截断范围的变化。
- 最多 2,048 字符的 focused text。
- 根据完整 AX value 与 selected range 临时计算光标前 80、后 40 个 UTF-16 单元。
- focused element role/subrole 与 secure-field 标志。

安全输入框中 selected/focused/cursor text 保持为空。上下文用于当前处理任务、交付校验、
有限历史元数据和 app tone 匹配。远程模式只组装用户在“智能处理”中开启的字段；原始
transcript 始终作为模型任务输入。

新增上下文字段时需要：

1. 给出具体产品用途。
2. 设置长度或类型边界。
3. 明确是否进入 prompt、历史和日志。
4. 更新测试与隐私说明。

## 安全输入框与焦点绑定

开始录音前，`CapturePrivacyPolicy` 检查捕获上下文。普通 `.insert` 随后使用原生剪贴板与 Command-V 写入提交瞬间的当前键盘焦点，不读取 AX focused element、选区或目标身份。

`.replaceSelection` 的交付事务继续要求：

- 原 PID 优先；缺少 PID 时使用原 bundle ID。
- 目标应用仍存在且可以激活。
- 当前 focused element 安全状态可确认。
- 当前 app 与捕获 app 一致。
- 当前选区与捕获选区一致。

选区改写遇到安全状态 unavailable、secure、目标 app 改变或选区改变时停止交付，结果进入可恢复的失败状态。

普通交付完成后可创建六秒可见回执，并保留最多 60 秒的进程内语音编辑目标。回执保存实际提交目标的 PID/bundle 以及 focused
element 和完整 AX value 的进程内 fingerprint；不保存 focused value 正文。Undo、即时修正
和语音发送执行前再次确认目标、输入框、完整值、安全输入状态和 Accessibility。回执过期、
新 capture、焦点变化、输入变化或权限变化都会停止动作。回执 fingerprint 不写 preferences、
history 或日志。语音跟进编辑的指令与每版结果遵循现有 history retention；选择 `never`
时不会创建可编辑回执或版本链。

对应实现与测试：

- [`AccessibilityTextDeliverer.swift`](../Sources/LerroMac/Accessibility/AccessibilityTextDeliverer.swift)
- [`AccessibilityTextDelivererTests.swift`](../Tests/LerroMacTests/AccessibilityTextDelivererTests.swift)
- [`AppSessionCoreFlowTests.swift`](../Tests/LerroTests/AppSessionCoreFlowTests.swift)

## 剪贴板事务

跨应用文本使用两种 clipboard transaction：

1. 普通插入以 best-effort 方式归档当前可读取的 pasteboard item/type，在同一个 MainActor 步骤写入文本与 transient type，再向当前键盘焦点连续提交带 Command flag 的 V down/up。
2. 普通插入提交后保持临时内容 500ms，随后恢复归档；恢复失败不回滚已经提交的文本。
3. 选区改写严格保存全部 item/type，使用 session marker 和 change count 维护所有权，并在 Command-V 前校验安全焦点、目标 PID/bundle 和选区一致性。
4. 严格事务仅在临时内容仍属于当前 session 时恢复；用户或其他应用已经更新剪贴板时保留新内容。
5. Command-V 提交前允许取消；提交构成交付 commit point，随后完成消费等待和对应恢复流程。
6. 回执 Undo 使用校验后的 Command-Z；即时修正在同一 adapter 事务内连续提交 Command-Z
   与 Command-V；语音发送使用校验后的 Return。合成事件携带 Lerro source marker，
   热键监视器直接透传。

严格 Rewrite 的人工验收需要使用多 item、多 type 数据，包括纯文本、富文本、图片或文件 URL；验证前后类型和字节保持一致。

## 原始音频生命周期

[`UserPreferences.shouldSaveCaptureAudio`](../Sources/LerroCore/Models/UserPreferences.swift) 的条件：

```text
saveAudio == true && historyRetention != .never
```

约束：

- `saveAudio` 默认 `false`。
- 文件名为随机 UUID，只向 history 保存相对文件名。
- 路径校验要求 relative path 等于其 last path component，阻断目录穿越。
- 启动、停止、取消、空转写、分析异常和写入异常均有清理路径。
- 历史索引读取失败时保留 Audio 目录，避免错误删除。
- retention 和手动删除先删除音频，再更新历史索引。
- Speech 层删除失败写本地 OSLog，并由 AppSession 下次 reconciliation 重试。

任何调整都要覆盖成功、取消、Speech 失败、交付失败、history 保存失败、删除失败和索引损坏。

## 网络边界

生产代码包含四类主动网络路径：公开 Hugging Face 模型下载、用户配置的 BYOK 模型请求、
BYOK 连接测试，以及 Sparkle 公开版本检查和 ZIP 下载。

[`MLXLanguageModelRuntime.publicModelHubClient`](../Sources/LerroIntelligence/MLXLanguageModelRuntime.swift) 固定：

```text
host: HubClient.defaultHost
bearerToken: nil
cache: app Models directory
```

因此应用不会继承本机 Hugging Face CLI token。Hugging Face 服务仍会获得常规 HTTP 连接元数据，例如 IP、User-Agent 和请求时间。

Apple Speech 语言资源可能由系统按需下载；下载和安装由 `AssetInventory` 管理。语音 buffer、transcript、词典和 AX 上下文不会发送到 Hugging Face。

用户选择 API 模式后，
[`OpenAICompatibleRemoteLanguageModelRuntime.swift`](../Sources/LerroIntelligence/OpenAICompatibleRemoteLanguageModelRuntime.swift)
直接连接所选 DeepSeek、OpenAI、Gemini 或 custom endpoint。Authorization 使用用户填写的
Bearer API Key。普通请求可以包含：

- 原始 Apple Speech transcript。
- 应用类型与名称。
- 窗口标题。
- 光标前 80、后 40 个 UTF-16 单元。
- 当前任务需要的选中文字。
- 最多 12 个命中词典条目与当前 app tone。

以上六类上下文拥有独立开关。连接测试只发送固定 `Reply exactly OK` 合成消息。ephemeral
URLSession 关闭 cookie、URL cache、credential store 和请求缓存；错误描述排除响应正文、
请求正文、Key 与 Authorization header。第三方 Provider 仍会按自身条款处理请求内容、IP、
时间、账户、用量与计费信息。

[`AppUpdateController.swift`](../Sources/Lerro/App/AppUpdateController.swift) 通过 Sparkle 访问
`https://updates.lerroapp.com/appcast/stable.xml`，在启动时及运行期间每 24 小时静默探测；
用户点击 Home、设置中的“检查更新”或蓝色下载入口会发起交互式检查。appcast 选择较新版本
后，用户点击启动 Sparkle 下载；ZIP 来自 `updates.lerroapp.com`，并以 `SUPublicEDKey`
验证 Ed25519 归档签名。该路径可携带
当前应用版本、平台和常规 HTTPS 连接元数据，例如 IP、User-Agent 与请求时间；它不包含音频、
transcript、焦点文本、选区、词典、prompt、回答或 API Key。

`lerro-distribution` Worker 从私有 R2 读取公开 ZIP，并从私有 D1 读取版本、build、签名、长度、
SHA-256 与发布时间等 release 元数据。服务端不存储 Lerro 用户内容。R2/D1 的写入仅在维护者
受控发布流程中发生；公开 Worker 不提供写入路由。`PrivacyInfo.xcprivacy` 已针对这条网络路径
复核：它没有新增 tracking、收集数据类型或 Required Reason API。

当前产品没有：

- 遥测或产品 analytics。
- 广告 SDK。
- 远程账号同步。
- Lerro 自建服务端 transcript、prompt 或 answer 存储。

Release 构建通过 Swift 与 Clang compiler prefix map 清除构建工作区前缀，并在独立 dSYM 生成后剥离 app binary 的调试与本地符号；发布复验按原始字节拒绝仍包含构建用户 Home 路径的 app binary。dSYM 保持独立产物，不随普通用户下载包分发。

新增网络能力必须先完成 ADR、数据流图、明确授权、失败与撤销路径、隐私说明和自动测试。

## 模型授权

默认模型标识和模式位于
[`UserPreferences.swift`](../Sources/LerroCore/Models/UserPreferences.swift)。行为：

- `hasApprovedModelDownload == false`。
- `raw` Dictate 直接交付原始 transcript。
- `local` 经过模型下载授权并使用 MLX runtime。
- `remote` 要求完整配置和用户主动保存启用。
- 首次需要模型时展示下载大小、来源和本地存储说明。
- Onboarding 在进入权限与练习前提供本地 AI、API 模型和基础听写三条明确路径；API Key
  在引导内完成填写、固定合成消息连接测试和保存启用。
- 本地下载支持暂停、继续和停止。暂停保留断点；停止清除未完成文件、resume data 与进度
  checkpoint，已经完整提交的 blob 保留。
- API 设置页持续展示发送字段与明文 JSON 存储事实。
- 用户在设置中也可主动准备模型。

自动测试只使用 stub runtime 或检查无 token HubClient。真实下载、加载和生成需要用户授权后的 Release 实机测试。

## 日志

当前 OSLog categories：

- `model-cache`
- `audio-cleanup`
- app telemetry/log stream subsystem `app.lerro.mac`

日志允许包含：

- 本地模型状态和无内容错误描述。
- 随机录音相对文件名。
- 系统状态码和清理结果。

日志禁止包含：

- raw/final transcript。
- selected/focused text。
- prompt 和模型 answer。
- 邮箱、邀请码、词典内容和窗口正文。
- access token、cookie、Authorization header。
- API Key、Base URL 中的 query/userinfo、请求/响应正文和 Provider 返回的原始错误正文。

新增日志时在 code review 中逐字段检查 privacy 标记。

## Privacy manifest、Info.plist 与 entitlements

| 文件 | 当前职责 |
| --- | --- |
| [`PrivacyInfo.xcprivacy`](../Sources/Lerro/Resources/PrivacyInfo.xcprivacy) | 无 tracking、无 declared collected data；System Boot Time 使用 reason `35F9.1` |
| [`Info.plist`](../config/Info.plist) | 麦克风 usage description、bundle identity、最低系统；Apple Speech 路径不声明独立 Speech Recognition 权限 |
| [`Lerro.entitlements`](../config/Lerro.entitlements) | audio input 与 network client |
| [`PrivacyPolicy.html`](../Sources/Lerro/Resources/PrivacyPolicy.html) | 用户可读的数据、网络、权限、删除说明 |
| [`TermsOfUse.html`](../Sources/Lerro/Resources/TermsOfUse.html) | 本地学习用途、模型输出、备份和第三方组件 |

当前 entitlement 文件没有 App Sandbox key。文档和 UI 禁止把应用描述为 sandboxed。未来开启 sandbox 时需要重新验证 AX、CGEventTap、MLX cache、Speech assets、登录项和文本交付。

System Boot Time reason 对应全局热键状态机读取 system uptime。移除或新增 Required Reason API 时同步更新 manifest。
BYOK 请求直接发往用户选择的第三方 Provider，Lerro 项目方不接收这些数据，因此当前
privacy manifest 的 collected-data 声明保持为空；隐私政策仍完整披露该第三方传输。

## Fixture 隔离

`LERRO_FIXTURE_MODE=1` 只能组合 inert adapters：

- 内存 history/dictionary/preferences。
- RuleBased intelligence。
- 合成 Speech stream 和 microphone level。
- 固定合成 context。
- no-op delivery、hotkey 和 login item。
- 直接返回授权状态的 permission checker。

Fixture 运行必须满足：

- Application Support 无新增或修改。
- 无真实麦克风访问。
- 无 TCC 弹窗。
- 无 AX/CGEventTap/pasteboard 操作。
- 无模型或网络访问。

该契约的生产组合位于
[`AppDependencies.swift`](../Sources/Lerro/App/AppDependencies.swift)。任何 fixture adapter 回退到 live adapter 都是隐私回归。

## 删除与恢复

- 历史单条删除：音频成功删除后删除索引。
- 全部历史删除：逐条删除关联音频，随后清空索引。
- Retention：删除超时录音，随后应用历史保留策略。
- `never`：停止保存新历史和音频；既有数据保留，等待用户主动删除。
- 损坏 preferences：AppSession 使用安全默认值并保留原文件；后续用户保存会产生新的有效文档，因此修复前应备份损坏文件。
- API Key：设置页“清除已保存的 Key”将字段置空，并把当前模式切换到 raw。
- 模型删除：当前通过 Finder/文件系统删除 Models；后续若增加 UI，需要展示磁盘影响和使用中状态。

## 隐私变更检查表

- [ ] 新数据字段有用途、长度、存储位置和删除路径。
- [ ] 新网络请求有 endpoint、payload、认证、授权和撤销说明。
- [ ] 新日志逐字段排除用户内容和凭据。
- [ ] secure-field 捕获与交付二次检查仍通过。
- [ ] 普通 best-effort 恢复与 Rewrite pasteboard ownership 条件恢复仍通过。
- [ ] raw audio 默认关闭，retention 与对账保持安全。
- [ ] fixture 仍全部使用 inert adapters。
- [ ] `PrivacyInfo.xcprivacy`、Info.plist、entitlements、PrivacyPolicy 同步。
- [ ] 自动测试和 [`testing.md`](testing.md) 实机矩阵已执行。
