# 核心链路与状态机

Lerro 1.6 的生产主路径固定为：

```text
按快捷键 → 居中实时预览 → 再按一次 → 严格写入目标 → HUD 消失
```

成功写入结束当前交互。HUD 后处理只承担写入失败恢复和自动词典学习提示。
长期决策见 [ADR 0012](decisions/0012-strict-delivery-ai-dictionary-learning.md)。

## 参与组件

| 组件 | 职责 |
| --- | --- |
| [`AppSession.swift`](../Sources/Lerro/App/AppSession.swift) | 会话 generation、状态机、Speech/AI/交付编排、恢复与自动学习 |
| [`CaptureModels.swift`](../Sources/LerroCore/Models/CaptureModels.swift) | `CapturePhase`、模式、上下文、历史模型 |
| [`GlobalHotkeyMonitor.swift`](../Sources/LerroMac/Hotkeys/GlobalHotkeyMonitor.swift) | 全局手势、吞键、前缀升级与 physical drain |
| [`AppleSpeechService.swift`](../Sources/LerroMac/Speech/AppleSpeechService.swift) | Apple Speech 实时转写、词典上下文与可选静音结束 |
| [`AccessibilityContextService.swift`](../Sources/LerroMac/Accessibility/AccessibilityContextService.swift) | capture 开始时的目标与安全指纹 |
| [`AccessibilityTextDeliverer.swift`](../Sources/LerroMac/Accessibility/AccessibilityTextDeliverer.swift) | 写入前严格校验与 Command-V 事务 |
| [`PasteboardRecoveryTextCopier.swift`](../Sources/LerroMac/Accessibility/PasteboardRecoveryTextCopier.swift) | 写入失败文本的剪贴板恢复 |
| [`AccessibilityDeliveredTextObserver.swift`](../Sources/LerroMac/Accessibility/AccessibilityDeliveredTextObserver.swift) | 同目标 60 秒修正观察与最小差异提取 |
| [`PipelineIntelligenceService.swift`](../Sources/LerroCore/Services/PipelineIntelligenceService.swift) | 润色、翻译与结构化修正分类 |

## 快捷键手势

公开捕获手势只有 `hold` 与 `toggle`：

- `toggle`：第一次 began 启动，第二次 began 完成；ended 只释放物理按键所有权。
- `hold`：began 启动，同一 definition ID 的 ended 完成。
- `transcribing`、`enhancing`、`inserting` 期间忽略重复开始或停止。
- 单修饰键由 `flagsChanged` 识别；普通组合键吞掉匹配的 down、repeat 与 up。
- Fn 前缀升级为更具体 chord 时，FIFO consumer 依次取消旧动作、转交物理按键所有权并启动新动作。
- 设置与 Onboarding 录制快捷键时暂停生产 dispatch；页面内测试不会启动麦克风、HUD、历史或写入。

HUD 始终读取用户实际配置的 shortcut label。默认产品路径采用手动结束。Quick Dictate
由独立开关控制，默认关闭；开启后只有 Dictate toggle session 安装 `SpeechDetector`，在检测到
首声后约 1.2 秒连续静音时完成一次。

## CapturePhase

```text
idle
  -> requestingPermissions
  -> listening
  -> transcribing
  -> enhancing
  -> inserting
  -> idle

任意未提交阶段 -> cancelled -> idle
任意错误出口   -> failed
```

`CaptureSession` 冻结以下事实：

- session ID、capture generation、模式与开始时间；
- Apple raw / remote / local 路由；
- Provider、Base URL、Model ID、API Key 与上下文开关；
- 目标应用、输入元素、完整值、选区和安全状态指纹；
- 语言、应用语气和目标语言。

旧异步任务返回前必须重新确认 generation 与 session ID。新 capture 会取消修正观察、旧 Speech、
模型任务和等待中的 completion task。

## 启动序列

1. 拒绝设置/Onboarding 快捷键录制期间的生产触发。
2. 拒绝已有活动 capture、过渡阶段重复触发和受限旧模式。
3. 停止上一条自动词典观察，清除恢复卡。
4. 检查启动错误、麦克风、辅助功能和安全输入框。
5. 通过 `ContextCapturing` 冻结目标应用、元素、文本、选区和安全指纹。
6. 冻结智能模式与 Provider 配置；本地模型未就绪时当前 Dictate 使用 Apple raw。
7. 从词典选择当前应用相关条目：应用级优先，其次全局，再按优先级、使用次数和最近使用排序。
8. 映射为 `SpeechVocabularyTerm`，单次最多 100 条。
9. 启动 Apple Speech，显示居中波形 HUD，并流式更新 partial transcript。

`DictationTranscriber` 使用 `.progressiveLongDictation`。词典 replacement 优先作为
`AnalysisContext.contextualStrings[.general]`；空 replacement 使用 phrase。大小写与音标折叠后去重。

## HUD 实时预览

- 初始宽度约 120 pt，应用名称、实时文本、波形和按钮保持视觉居中。
- 同一 session 只增宽，最大 420 pt，避免 partial 反复修订造成左右抖动。
- 达到最大宽度后显示最多两行，并保留最新内容。
- 左右按钮占对称固定槽位，波形中心不随按钮变化。
- listening 到 processing 复用当前宽度，以 spring/crossfade 过渡。
- Reduce Motion 使用即时尺寸与淡入淡出；VoiceOver partial 播报节流。
- 写入成功立即关闭 HUD；失败进入恢复卡；学习成功显示轻量提示。

## Apple raw Dictate

1. 第二次快捷键或 Quick Dictate endpoint 请求停止 Speech。
2. Speech 完成 remaining analysis，返回最终 raw transcript。
3. 空白结果走失败出口。
4. snippet 可在当前应用范围内解析为手动短语替换。
5. 普通 raw transcript 直接进入严格交付。

Apple-only 用户仍可使用实时预览、手动词典、Apple Speech 词典上下文、写入恢复、历史和 CSV。

## AI Dictate

remote 或 local 模式下，Apple Speech 先产生原始 transcript，再由
`PipelineIntelligenceService` 执行润色。capture 时冻结的应用语气、最小上下文和匹配词典进入
当前请求。AI 成功结果写入目标；Dictate 模型失败时交付原始 transcript 并在历史中保存 raw 路由。

成功写入且自动学习偏好启用时，启动词典学习观察。AI 关闭或本地模型当前不可用时，观察不会启动。

## Translate

Translate 始终需要当前选择的 remote 或 local AI：

1. Apple Speech 产生 raw transcript。
2. Intelligence request 携带目标语言和已授权上下文。
3. AI 输出翻译文本。
4. 严格交付到 capture 目标。

AI 缺失、取消或生成失败会显示明确错误并保留失败历史。生产链路不调用 Apple Translation。

## 应用语气

个性化页面通过 `ApplicationCataloging` 读取已安装与正在运行的应用、Bundle ID 和真实图标。
用户为一个应用输入 tone instruction，选择的 remote/local AI 使用真实示例运行预览；预览成功后
保存 `AppToneProfile`。后续 AI Dictate 和 Translate 只使用当前应用命中的 profile。

## 严格写入事务

写入前 `AccessibilityTextDeliverer` 依次确认：

1. secure input 仍关闭；
2. 前台应用与 capture PID/bundle 一致；
3. focused application 与 focused element 一致；
4. 元素 role/subrole、完整 AX value 与 selection fingerprint 一致；
5. 剪贴板快照与 Command-V 事件可以创建。

随后事务：

1. 保存 pasteboard 全部可读取 item/type 数据。
2. 写入 session marker、transient type 和最终文本。
3. 提交合成 Command-V down/up；该事件对成为 commit point。
4. 等待目标消费。
5. session 仍拥有临时内容时恢复快照；用户或其他应用已经更新剪贴板时保留新内容。

commit point 前取消会阻止粘贴并释放已按下按键。commit point 后完成剪贴板清理与历史收尾。

## 成功结束

写入成功后：

1. 保存 completed history，或按 `historyRetention == .never` 删除本次音频。
2. 更新 usage 和历史列表。
3. 符合 AI 自动学习条件时启动观察任务。
4. 清空 active session、partial transcript 和 capture 状态。
5. phase 回到 `idle`，HUD 立即消失。

成功路径没有写入回执、撤回、重新听写、语音修改、语音发送或版本恢复。

## 写入失败恢复

应用、元素、值、选区、安全状态漂移，或剪贴板/事件提交失败时：

1. 保存最终文本为 `lastResult`。
2. 将 history 标记为 failed，记录最终文本和阶段耗时。
3. `RecoveryTextCopying.copyForRecovery` 把最终文本写入系统剪贴板。
4. HUD 显示：

```text
未能写入 <目标应用>
内容已复制到剪贴板

[再次复制] [关闭]
```

“再次复制”重复写入同一最终文本。恢复卡不抢键盘焦点。用户关闭后回到 idle。

## 自动词典学习

学习只在以下条件同时成立时启动：

- Dictate 使用 remote 或 local AI；
- `automaticDictionaryLearningEnabled` 开启；
- 写入成功并取得严格目标 receipt；
- Accessibility 可持续读取同一 app 与 input element；
- 当前字段不属于 secure input。

流程：

1. `DeliveredTextObserving.observe` 绑定刚写入文本和 receipt，观察最多 60 秒。
2. 每 100 ms 读取字段；变化持续稳定 800 ms 后进入差异定位。
3. 原写入文本在字段内必须唯一；差异必须与该范围相交。
4. 本地 UTF-16 差异算法产出 original span、corrected span、前 80/后 40 上下文。
5. 当前 remote/local AI 使用严格 JSON schema 分类，返回 0–3 个候选。
6. phrase 必须来自 original span，replacement 必须来自 corrected span，confidence 范围为 0–1。
7. confidence ≥ 0.7、映射非空且未重复的候选保存为当前应用 scope 的 learned entry。
8. HUD 显示六秒轻量提示 `已学会：A → B · App`，用户可撤销本批词条。

应学习人名、品牌、术语、拼写、同音词、音译和中英文专名。语义变化、事实或日期变化、增删句、
语气修改、结构调整和大段改写返回零候选。AI 输出包含额外字段、代码围栏、超过三条或来源不匹配时
整体拒绝。

同一词典数据进入 Apple Speech 最多 100 条上下文、remote/local AI prompt、词典页编辑与删除、
CSV、应用筛选和全局提升。新 capture、离开 app/field、secure input、AX 失败、编辑器不支持、
文本过大、超时和任务取消都会安静结束观察。

## Onboarding

Onboarding 由八个操作步骤构成：

1. 选择历史和录音保存策略并确认。
2. 完成麦克风、Speech 权限、语言资源检查和麦克风测试。
3. 按 Apple 听写、远端 AI、本地 AI 的固定顺序选择能力；API 必须真实连接测试；本地路径展示芯片、内存、磁盘、约 3.03 GB 和下载控制。
4. 录制快捷键并完成页面内开始/结束测试。
5. 在内置编辑器完成一次真实听写、预览和写入。
6. 模拟焦点丢失，点击“再次复制”并验证剪贴板。
7. AI 用户修正预置专名，等待自动学习条目，再次听写验证。
8. AI 用户选择真实应用，运行 tone 预览并保存。

Apple-only 用户完成第 6 步后进入首页。本地模型下载可在后台继续，模型可用后完成 AI 步骤。

## 失败与取消

### 取消

取消信号贯穿 capture 启动、Speech、local/remote generation 和 Command-V 前校验。统一清理：

- 停止 Speech 与音频输入，释放 tap 和 Core Audio mute snapshot；
- 取消 generation、completion、model status 与自动学习任务；
- 删除未持久化录音；
- 清除 active session 与临时 HUD 文本；
- reset 热键 transient state，同时保留已吞按键直到 physical release。

### 识别与模型失败

- 空白 Speech 结果、权限丢失、资源缺失和音频错误进入 failed HUD。
- AI Dictate 生成失败交付 raw transcript。
- Translate 生成失败进入 failed HUD。
- 所有错误都避免主窗口 alert、Dock attention 和 transcript 日志。

### 过期结果

Speech event、model result、delivery callback 和 observer event 返回 UI 前校验 generation/session。
失配结果只能执行资源清理，无权写入文本、保存完成历史、展示 HUD 或保存词典。

## 音频与历史生命周期

- `saveAudio` 默认 `false`。
- 每次录音创建独立 CAF 相对路径。
- `historyRetention == .never` 时禁止写入新历史和录音。
- 成功历史保存失败时删除未被索引拥有的音频。
- 删除历史先删除音频，再删除索引；音频删除失败时保留历史。
- 启动时只有成功读取历史索引后才清理孤儿 CAF。
- failed delivery history 保留最终恢复文本，不保存 AX fingerprint 或自动学习 spans。

## 模型与下载生命周期

capture 开始时冻结 intelligence route。本地下载由 AppSession 持有，支持后台继续、暂停、恢复、
停止与重启续传。停止只清理未完成文件、resume data 和 checkpoint，完整 blob 保留。下载完成后
下一个 local action 加载模型；闲置 runtime 可以释放容器，缓存继续存在。

## 证明边界

自动测试应覆盖 raw/remote/local 路由、词典注入上限、Quick Dictate、严格目标漂移、恢复剪贴板、
AI 分类结构、修正观察、HUD 单调增宽、Onboarding 三条路径、下载状态机和旧异步结果隔离。

最终 Release app 仍需在 TextEdit、Notes、浏览器/ChatGPT 与 Electron 编辑器完成真实麦克风、
Speech、全局快捷键、AX、剪贴板、多显示器/Space 和失败恢复验证。测试层级与完整矩阵见
[`testing.md`](testing.md)。
