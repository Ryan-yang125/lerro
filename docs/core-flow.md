# 核心链路与状态机

本文件描述真实产品从快捷键或菜单命令到文本交付、回答展示和本地持久化的完整路径。权威实现位于
[`AppSession.swift`](../Sources/Lerro/App/AppSession.swift)，领域状态位于
[`CaptureModels.swift`](../Sources/LerroCore/Models/CaptureModels.swift)。

## 参与组件

| 阶段 | 协议或服务 | 生产实现 |
| --- | --- | --- |
| 命令输入 | `HotkeyMonitoring` | [`GlobalHotkeyMonitor`](../Sources/LerroMac/Hotkeys/GlobalHotkeyMonitor.swift) |
| 权限 | `PermissionChecking` | [`MacPermissionService`](../Sources/LerroMac/System/MacPermissionService.swift) |
| 上下文 | `ContextCapturing` | [`AccessibilityContextService`](../Sources/LerroMac/Accessibility/AccessibilityContextService.swift) |
| 收音与转写 | `SpeechTranscribing` | [`AppleSpeechService`](../Sources/LerroMac/Speech/AppleSpeechService.swift) |
| 智能路由与提示词 | `IntelligenceProcessing` | [`PipelineIntelligenceService`](../Sources/LerroCore/Services/PipelineIntelligenceService.swift) + local/remote runtime |
| 文本交付 | `TextDelivering` | [`AccessibilityTextDeliverer`](../Sources/LerroMac/Accessibility/AccessibilityTextDeliverer.swift) |
| 历史与词典 | Repository protocols | [`Sources/LerroCore/Stores`](../Sources/LerroCore/Stores) |
| 浮层 | `FloatingPanelController` | [`FloatingPanelController.swift`](../Sources/LerroMac/Panels/FloatingPanelController.swift) |

## 快捷键手势

[`HotkeyDefinition`](../Sources/LerroCore/Models/CaptureModels.swift) 保存物理按键、精确
modifier 集合和触发方式。捕获动作支持两种明确语义：

- `hold`：按下产生 `HotkeyTrigger.began`，松开同一 binding 产生 `ended`。
- `toggle`：每次完整点按产生一次 `began`；第一次启动锁定录音，同一 action 的任一
  toggle binding 再次点按均可完成。

`HotkeyTrigger.definitionID` 将松开事件绑定到启动本次捕获的定义。另一个快捷键的
松开无权完成当前 session。旧设置中的 Fn `press` 迁移为 `hold`，普通组合键
`press` 与 `doublePress` 迁移为 `toggle`；旧 hands-free action 迁移为对应基础 action
的 toggle binding。

`HotkeySignature` 先把 Fn 标记与 legacy modifier keyCode 规范化，再执行冲突检测和
迁移去重。左右 Command/Control/Option/Shift 在当前产品语义中等价。

[`GlobalHotkeyMonitor`](../Sources/LerroMac/Hotkeys/GlobalHotkeyMonitor.swift) 使用 active
HID event tap 在 head insert 位置监听 `flagsChanged`、`keyDown` 与 `keyUp`，事件 mask
固定为 `0x1C00`。Fn 63、Globe 179、Control、Option、Shift、Command 等实体 modifier
keyCode 分别进入按下集合，语义匹配使用规范化 flags；aggregate flags 未变化的重复事件
仍进入所有权判断。120 ms 意图确认窗口保护常用系统 chord。候选或已激活的 Fn 前缀
遇到已配置的 Fn+Shift/Fn+Space 时，状态机依次取消前缀 capture、转交物理所有权并启动
更具体 action。命中的普通键 down、repeat 和 up，以及已接管 Fn/Globe 的全部事件，
会持续吞到明确的实体 release；鼠标、滚动、系统媒体键及未命中 chord 继续传给前台应用。

event tap 安装保持幂等。timeout 或 user-input disable 会先取消活动手势并进入 physical
drain，再在 main queue 禁用并 invalidate 旧 tap、移除 run-loop source、创建新 active HID
tap；排队重建受 generation 保护，显式 stop 后不会复活。逻辑 reset 已经吞掉的按键持续
由 Lerro 持有至明确的 key-up 或 modifier release。Secure Input watchdog 在事件流暂停时取消活动
hold，并在安全输入结束后对账物理键状态。文本交付产生的 Command-V 带固定 source
marker，shortcut filter 识别后直接透传。Secure Input 结束后的首个非 repeat key-down
会淘汰同键 stale claim 并重新匹配，旧 repeat 继续完成 drain。watchdog 先观察到退出时，
recovery generation 会保留到旧 claim 释放或新物理 down 得到确认；左右同类 modifier 的
方向由具体 keyCode 的物理状态判定，局部 release 不会生成候选。

`AppSession` 使用带 dispatch epoch 的单一 FIFO consumer 保持 began/ended 顺序，停止
monitor 后的旧队列事件无法跨越配置窗口，消费前还会确认 definition 仍存在于当前设置。
toggle 在 Speech 启动期间收到同 action 的第二次点按会取消当前 generation；HUD 将 hold
capture 锁定后忽略原 release，同 action 的下一次按下或 HUD 完成按钮结束录音。取消清理
期间的 hold 使用 FIFO 配对，toggle 使用奇偶归并；显式 cancel 会清空全部待重放触发。
菜单与 HUD 的程序化启动共享同一 generation guard，启动期快捷键无法创建第二个 session。

设置和 Onboarding 的录制器进入独占配置状态时暂停生产 monitor，并在界面出现后自动开始
检测。本录制窗口通过 AppKit local event monitor 读取 `flagsChanged`、`keyDown` 与
`keyUp`，因此按钮、sheet 或其他控件持有 first responder 时仍能实时显示 peak chord、
按下和松开；停止检测后 Tab/Return 恢复标准键盘导航。已验证候选与当前按键状态分离，
无效 chord 无法覆盖或保存旧的半成品。快捷键变更按候选 binding 确认写入本地
preferences 后页面才继续，并允许无关设置在同一保存队列中继续更新。活动 capture 期间
禁用 binding 增删改。检测期间麦克风、Speech、HUD、历史与文本交付保持关闭。

## CapturePhase

| Phase | 含义 | 可接受的主要动作 |
| --- | --- | --- |
| `idle` | 无活动捕获 | 开始任意模式 |
| `listening` | Speech 已成功启动 | hold 的匹配 release 或 toggle 的第二次点按结束；Escape 取消；HUD 可锁定 |
| `transcribing` | 停止收音并等待最终转写 | Escape 取消；重复 toggle 被忽略 |
| `enhancing` | 规则或模型处理 | Escape 取消；重复 toggle 被忽略 |
| `inserting` | clipboard transaction + Command-V 交付 | Command-V 提交前允许 Escape 取消；提交后完成恢复并忽略取消；重复 toggle 始终忽略 |
| `success` | 兼容完成状态，HUD 保持隐藏 | 新捕获可启动 |
| `failed` | 短暂失败反馈并显示可读错误 | 新捕获可启动 |
| `cancelled` | 短暂取消反馈 | 新捕获可启动 |

捕获开始还有 `isStartingCapture` 状态，用于覆盖权限、上下文和 Speech 启动期间。快捷键
被接受的同一轮 MainActor 事件会同步展开 HUD。hold 使用 waiting 声线；toggle 直接展开最终
116×34 hands-free 外壳，麦克风准备留在内部状态，Speech 就绪时只激活同一个波形实例，
外壳尺寸全程保持稳定。此时再次 toggle 会执行取消，防止延迟启动形成幽灵录音。
`CaptureSession.startedAt` 在 Speech 和麦克风就绪后创建，录音计时不包含资源准备耗时。
波形以 50 ms cadence 消费真实音量，使用独立柱状态、脉冲游走、邻柱扩散和非同步衰减；
开始、完成和失败均保持静音，状态反馈由 HUD 与 VoiceOver 公告提供。
结束收音后，`transcribing`、`enhancing` 和提交前的 `inserting` 共用同一个三点 processing
指示。指示首帧已有完整静态轮廓，并以 30 Hz 上限驱动 opacity/scale，快速模型结果不会
等待动画结束；Reduce Motion 使用中央点高亮的静态三点状态。

## 共用启动序列

```text
用户命令
  -> intelligenceMode 与对应配置授权检查
  -> 创建 capture generation
  -> HUD 同步展开（hold: waiting；toggle: hands-free 最终外壳）
  -> 请求麦克风、Accessibility
  -> 捕获目标 app、PID/bundle、选区、焦点文本、role、安全状态
  -> 安全输入框 fail closed
  -> AppleSpeechService.start
  -> 验证 generation 仍有效
  -> 创建 CaptureSession UUID
  -> listening waveform + 计时器 + partial stream
```

关键实现：

- `AppSession.startCapture(_:handsFree:)`
- `AppSession.beginCapture(_:generation:)`
- `AppSession.ensureCapturePermissions()`
- `CapturePrivacyPolicy.permitsCapture(in:)`

capture 需要麦克风与 Accessibility 全部可用。Accessibility 可用后幂等安装 global
event tap；麦克风缺失会阻止 capture，同时保留快捷键监听以便后续重试。活动 capture
期间撤销任一权限会先取消 capture；Accessibility 撤销后停止 event tap。相同 definitions
的刷新保留当前按键手势。最长录音时间为九分钟，计时器到点后自动完成。

## 原始听写

前提：`preferences.intelligenceMode == .raw`。

```text
SpeechTranscription
  -> 保留 Apple Speech 原始 transcript
  -> IntelligenceResult(disposition: .insert, source: raw)
  -> AccessibilityTextDeliverer
  -> completed HistoryEntry
  -> retention / audio reconciliation
```

原始听写不加载 Qwen，也不调用远程 API。普通听写使用系统 Command-V 的标准语义：文本写入提交瞬间的当前键盘焦点，当前选区存在时由目标控件完成替换。

只有全空白 transcript 会触发 `LerroError.emptyTranscription` 并进入失败清理。口头填充词、
重复、错别字和首尾空白都按 Apple Speech 原值交付。该模式不运行词典替换或自动学习。

自动化入口：

- [`AppSessionCoreFlowTests.swift`](../Tests/LerroTests/AppSessionCoreFlowTests.swift) 的基础听写、选区语义和取消测试。
- [`PipelineIntelligenceServiceTests.swift`](../Tests/LerroCoreTests/PipelineIntelligenceServiceTests.swift) 的 raw byte-preservation 测试。

## 智能听写

前提：`intelligenceMode` 为 `.local` 或 `.remote`。capture 启动时冻结模式、Provider、
Model ID、API Key 与上下文开关，本次会话不受随后设置变化影响。

```text
SpeechTranscription
  -> 原始 transcript 直接进入 IntelligenceRequest
  -> local: PromptComposer + MLX runtime
     remote: CloudPromptComposer + OpenAI-compatible runtime
  -> sanitize
  -> disposition .insert
  -> text delivery
```

本地 AI 需要用户确认约 3.03 GB 下载。API 模型需要完整 Base URL、Model ID 和 API Key；
用户可分别控制应用、窗口标题、光标附近文字、选中文字、词典和语气六类上下文。

Dictate 的模型调用异常或空结果会回退到 Apple Speech 原始 transcript，并把历史标记为
未增强。任务取消继续作为取消传播。Command 与 Rewrite 保留明确失败，避免把原文当作对应任务
的有效结果。

Dictate 在模型路由前检查本机手动词典。完整 transcript 与快捷语触发词精确匹配时，直接展开
replacement 并交付；应用级快捷语优先于全局快捷语。该路径不调用 MLX 或远程 Provider。

远程 Dictate 使用版本化的七个 few-shot 提示词和结构化 JSON payload。payload 包含原始
transcript、规范化规则、用户允许的工作区上下文、应用语气与最多 12 个命中词典条目。
光标上下文上限为前 80、后 40 个字符单元。

## 翻译

翻译使用偏好数组中的第一个目标语言，最多三个语言选项由 `UserPreferences` 限制。

```text
SpeechTranscription
  -> freeze transcription locale + targetLanguage
  -> AppleTranslationService
  -> installed Apple Translation resource
  -> disposition .insert
  -> text delivery
  -> translation HistoryEntry
```

Apple Translation 资源通过 SwiftUI `translationTask` 与
`prepareTranslation()` 在引导或设置中准备。快捷键运行时只使用
`TranslationSession(installedSource:target:)`，缺少资源时显示错误并停止交付。
翻译全程不调用 MLX、BYOK 或网络 provider，也不使用原 transcript 充当翻译结果。

## Command

Command 根据捕获选区选择任务：

- 选区存在：`.rewriteSelection`，完整 transcript 作为指令。
- 无选区：`.answer`。

### 回答

```text
context + transcript
  -> selected prompt composer
  -> local MLX 或 remote API stream
  -> progressive IntelligenceResult(.showAnswer)
  -> Command panel 更新
  -> final answer 保存到 HistoryEntry.answerText
```

回答阶段不自动写入原应用。Command panel 会成为可交互的 key window，同时保持非 main window，
避免夺取 SwiftUI 主窗口的 Scene 所有权。用户执行插入时，`reactivateCaptured` 先恢复捕获应用，
再向恢复后的当前键盘焦点发送 Command-V。该路径不依赖 AX 文本元素或选区。

### 选区改写

```text
captured selectedText + spoken instruction
  -> PromptComposer.rewriteSelection
  -> MLX generate
  -> disposition .replaceSelection
  -> 确认原 app 仍是当前键盘目标
  -> 验证 PID/bundle、当前安全状态、原选区文本
  -> clipboard transaction + synthetic Command-V
```

原应用关闭、焦点切换、选区变化或安全状态无法确认时，交付失败。生成结果保存在失败历史和 `lastResult`，便于用户恢复。

## 完成与交付

`AppSession.complete(session:transcription:)` 先构造结果与 HistoryEntry，再执行 disposition：

- `.showAnswer`：展示 Ask panel。
- `.insert`：向提交瞬间的当前键盘焦点发送 Command-V。
- `.replaceSelection`：替换经过二次确认的原选区。
- `.openURL`：交给 `NSWorkspace`。

交付成功后：

1. Command-V down/up 到达 commit point 后立即收起 HUD 并恢复面板点击透传；剪贴板等待与恢复继续完成。
2. 按 history retention 保存历史或删除录音。
3. 本地模型结果学习符合边界的词典替换；remote/raw 结果跳过自动学习。
4. 应用 retention 并删除过期音频。
5. 更新 `lastResult`、历史第一页、词典和统计；历史页按当前查询继续分页加载。
6. 清除 active session/generation 并回到 idle。

## 交付事务

[`AccessibilityTextDeliverer.swift`](../Sources/LerroMac/Accessibility/AccessibilityTextDeliverer.swift) 按 disposition 使用两条原生路径：

1. `.insert` 以 best-effort 方式归档 general pasteboard 当前可读取的 item/type，使用 `currentHostOnly` 写入文本与 transient type，随后向提交瞬间的当前键盘焦点发送 Command-V。
2. Dictate、Translate 与“粘贴上次结果”的普通插入不读取 AX focused element、选区、PID 或 bundle，也不激活捕获时的应用。处理期间发生的焦点变化会自然决定最终落点。
3. Ask card 的显式插入先有界恢复捕获应用，只等待应用身份成为前台键盘目标，不要求 AX 文本元素或选区。
4. `.replaceSelection` 继续绑定捕获时的 PID/bundle，验证当前安全状态、AX focused element、原选区文本与 fingerprint，再发送 Command-V。
5. V keyDown/keyUp 使用当前键盘布局解析出的键码，通过 `CGEvent.post(tap: .cghidEventTap)` 连续提交，并携带 Lerro source marker 供全局快捷键过滤器透传。
6. `inserting` 从剪贴板准备开始；Command-V down/up 构成交付 commit point，并同步触发 `TextDeliveryCommitHandler`。提交前允许取消，提交后完成 500ms 消费等待。
7. 普通插入在等待结束后恢复归档剪贴板；严格 Rewrite 仅在 change count、唯一临时 item、marker、transient type 与文本仍属于当前 session 时恢复，期间产生的新剪贴板内容会保留。
8. 同一 deliverer 同时只允许一个事务，避免两个异步交付互相覆盖临时剪贴板。

捕获时已标记为安全输入的上下文不会进入交付。剪贴板准备、事件创建或严格选区改写检查失败时，最终文本保留在失败历史中。

## 失败与取消

### 取消

`AppSession.cancelCapture()`：

- 只处理真实活动捕获；idle 取消无副作用。
- 立即使 generation 和 active session 失效。
- 取消 completion task。
- `inserting` 在 Command-V 提交前继续执行上述取消；提交回调触发后保持会话，等待剪贴板恢复与历史落盘完成。
- 重置热键瞬态状态。
- 调用 `speech.cancel()`。
- 取消 event/timer tasks。
- 清理孤儿录音并短暂显示 cancelled。

`AppleSpeechService.cancel()` 负责移除 audio tap、停止 engine、结束 analyzer、恢复输出静音、删除当前录音并清空内部 session。

### 失败

`AppSession.fail(_:)`：

- 隐藏 Ask、清除回答上下文。
- 将具体原因写入 `captureError`，只驱动 HUD 与辅助功能公告；不创建主窗口 alert、不请求 Dock attention。
- 清除 generation、active session 和 hands-free。
- 取消 event/timer tasks 并重置热键状态。
- 调用 speech cancel 和录音对账。
- 显示短暂 failed 状态，再回到 idle。

空白转写属于这一失败出口。它发生在结果构造、交付和 completed history 写入之前，因此不会产生空文本交付或成功历史。

### 交付失败

模型已经生成结果、交付阶段失败时：

- `lastResult` 保留最终文本。
- HistoryEntry 的 `status` 设为 `.failed`。
- 音频/历史继续遵循 retention。
- UI 进入 failed，禁止显示成功。

### 过期异步结果

开始阶段检查 generation；Speech stream 和完成阶段检查 session ID。过期任务终止后不得交付、写历史或覆盖当前 UI。

## 音频与历史生命周期

原始音频的写入条件：

```text
preferences.saveAudio == true
&& historyRetention != .never
```

[`AppleSpeechService.swift`](../Sources/LerroMac/Speech/AppleSpeechService.swift) 使用 UUID 文件名写 CAF。完成后只把相对文件名写入历史。

清理规则：

- Speech 启动失败、取消、空转写、analyzer 错误：删除当前录音。
- session 过期：删除未持久化录音。
- 交付/持久化错误：先读取历史确认是否已索引，再决定删除。
- 读取历史索引失败：保留文件等待下次对账。
- 删除历史和 retention：先删除录音，随后更新历史索引。
- 启动时只有成功读取历史索引后才清理未引用 CAF。
- `.forever` 与 `.never` 不执行 retention 文件重写；定时策略只有发现过期记录时才提交更新。
- 录音删除与目录对账在独立 actor 上执行，AppSession 等待结果后再推进索引变化。
- 历史查询每页最多 50 条；搜索或模式变化会更换 generation，过期页面无权写回当前列表。

## 模型生命周期

[`MLXLanguageModelRuntime.swift`](../Sources/LerroIntelligence/MLXLanguageModelRuntime.swift) 负责：

- 使用无 bearer token 的 HubClient。
- 从应用 Models 目录检查缓存 marker。
- 合并同模型并发加载。
- 报告 downloading/loading/loaded/failed 状态。
- 流式生成并在终止时取消底层任务。
- 生成结束后延迟卸载内存中的模型，保留磁盘缓存。

用户授权边界与数据网络边界见 [`privacy-security.md`](privacy-security.md)。

[`OpenAICompatibleRemoteLanguageModelRuntime.swift`](../Sources/LerroIntelligence/OpenAICompatibleRemoteLanguageModelRuntime.swift)
负责 BYOK API：每次使用当前 capture 快照创建或复用 ephemeral URLSession client，禁用
cookie、URL cache 和 credential store，限制响应体大小，只允许 HTTPS 与 loopback HTTP，
并将连接、流式生成、取消和脱敏错误映射到 Core 协议。连接测试只发送固定合成消息。

## 自动化证明与实机证明

自动化已覆盖 AppSession 的原始听写、local/remote 路由、Dictate 失败原文回退、翻译、Ask 流、目标策略、secure-field 启动拦截、交付失败、取消、启动竞态、模型取消和重复 toggle；文本交付测试还覆盖普通 current-focus paste、AX element/selection unavailable 兼容、严格 Rewrite、clipboard transaction、多 item/type 精确恢复、外部剪贴板所有权、并发事务、选区变化和应用切换。当前列表以
[`Tests`](../Tests) 实际内容为准。

以下行为依赖目标 Mac：

- 真实麦克风和 Speech 语言资源。
- 默认输出设备静音与恢复。
- TCC 首次授权与撤销。
- CGEventTap 的真实单修饰键、组合键、hold/toggle、吞键与 tap-reset 时序。
- AX 在 TextEdit、浏览器和第三方编辑器中的行为。
- 完整 pasteboard 多类型恢复。
- Qwen 真实下载、加载、生成、内存和离线缓存。
- 用户 Provider 的真实认证、配额、模型可用性、延迟和输出质量。
- HUD/Ask panel 的焦点、多 Space、多显示器行为。

完整命令与 Release 人工矩阵见 [`testing.md`](testing.md)。
