# 0012：严格写入与 AI 自动词典学习

- 状态：accepted
- 日期：2026-08-13
- 决策人：Lerro maintainers
- 关联任务/PR：Lerro v1.6.0 (13)
- 替代：ADR 0005、ADR 0009、ADR 0010；更新 ADR 0011 的 Onboarding 顺序与 Quick Dictate 默认值

## 背景

V1.4–V1.5 在文本写入后继续展示回执，并提供 Undo、语音修改、版本恢复、重新听写和语音发送。
真实用户测试显示这段后处理破坏了“按下说话、实时预览、再次按下、写入完成”的清晰心智模型。
current-focus paste 还会在用户处理期间切换应用或输入框时把结果写到新的焦点。

用户修正听写错误的自然动作发生在已写入文本内。V1.6 将该动作作为自动词典来源：系统观察
原字段的稳定修改，本地代码定位最小差异，用户选择的 AI 判断它是否属于可复用的语音识别
修正。标准词典随后同时服务 Apple Speech 与 local/remote AI。

Onboarding 需要让首次用户通过真实操作完成可用主链路，并针对 Apple-only、remote AI 和 local AI
提供明确完成条件。本地模型约 3.03 GB，下载控制继续沿用 ADR 0011 的 AppSession-owned
后台、暂停、恢复、停止与重启续传边界。

## 决策驱动因素

- 一次快捷键手势完成从语音到目标文本的完整路径。
- 目标漂移时停止写入，并确保最终文本始终可恢复。
- Apple-only 新用户可以立即完成基础听写。
- AI 能力只承载润色、翻译、自动学习和应用语气。
- 自动学习复用用户真实修改，过滤语义变化和大段重写。
- Apple Speech 与两类 AI 共享一个可编辑、可删除、有应用 scope 的词典。
- HUD 保持居中、单调扩宽、非激活和可访问。
- Onboarding 的每一步由可检测的成功操作解锁。

## 方案

### 1. 产品能力与入口

1. 新安装默认 `raw` Apple Speech。能力选择顺序固定为 Apple、remote、local。
2. 生产 capture 入口保留 Dictate 与 Translate；旧 Ask/Rewrite 入口、快捷键、卡片和 Onboarding
   教学删除。旧 Ask history 只读取展示。
3. remote/local AI 提供 Dictate polish、Translate、automatic dictionary learning 和 app tone。
4. Quick Dictate 保留独立设置开关，默认关闭；开启后约 1.2 秒连续静音结束 Dictate。

### 2. Capture-bound 严格写入

1. capture 开始冻结应用 PID/bundle、focused element、role/subrole、完整 value、selection 与 secure state。
2. 写入前重新读取并严格比对上述指纹。任何漂移都会在 Command-V 前停止。
3. 剪贴板 transaction 保存全部可读取 item/type，写入 marker 与 final text，提交 synthetic Command-V，
   并只在 session 仍拥有 transient content 时恢复快照。
4. 写入成功后 HUD 立即消失，当前交互结束。
5. 写入失败把 final text 复制到剪贴板、保存 failed history，并显示“再次复制/关闭”恢复卡。
6. 生产代码移除六秒成功回执、Undo、voice correction、redictate、version restore 和 voice submit。

### 3. 自动词典学习

1. 成功 AI Dictate 返回的进程内 `TextDeliveryReceipt` 只用于修正观察。
2. `AccessibilityDeliveredTextObserver` 在同 app/element 最多观察 60 秒，每 100 ms 读取 value，
   变化稳定 800 ms 后处理。
3. delivered text 必须在 baseline 唯一，diff 必须与其范围相交；本地 UTF-16 算法输出最小
   original/corrected spans 与前 80/后 40 context。
4. local/remote AI 使用严格 JSON schema 返回 0–3 candidates。AI 负责学习判断，diff 代码只定位变化。
5. phrase/replacement 必须来自输入 spans，confidence ≥ 0.7 的非重复 candidate 保存为当前 app scope。
6. names、brands、technical terms、spelling、homophones、transliterations 和 mixed-language proper
   nouns 可学习；meaning/fact/date/time/tone/add/delete/restructure/broad rewrite 返回零 candidates。
7. 学习成功显示六秒轻提示和 Undo；词条保存到标准 `DictionaryEntry`。
8. AI disabled、AX unavailable、secure input、app/field drift、unsupported editor、new capture 或 timeout
   安静结束。

### 4. 统一词典

1. `SpeechTranscribing.start` 接收 `[SpeechVocabularyTerm]`。
2. AppSession 选择当前 app 最相关的 non-snippet entries，app scope 排在 global 前，单次最多 100。
3. `AppleSpeechService` 使用 progressive `DictationTranscriber` 与
   `AnalysisContext.contextualStrings[.general]` 注入去重 replacement/phrase。
4. 同一 dictionary 进入 local/remote prompt、词典页编辑/删除/CSV/scope 管理。

### 5. HUD 与导航

1. HUD 初始约 120 pt，application、transcript、waveform 和 actions 使用居中垂直布局。
2. 同一 capture 宽度只增长到 420 pt；长文本最多两行并保留最新内容。
3. 左右固定对称 slot 保持 waveform 中心；processing 继承中心与当前宽度。
4. Reduce Motion 使用即时尺寸和 fade；VoiceOver partial announcement 节流。
5. 一级导航固定为 Home、History、Dictionary、Personalization。
6. Personalization 使用真实 app icon 的 adaptive grid、installed/running search 与 AI tone preview。

### 6. 操作型 Onboarding

Onboarding 固定八步：privacy、Speech、AI、shortcut、real Dictate、recovery copy、AI dictionary、AI tone。
Apple-only 用户在 recovery 后完成。remote 连接必须通过真实 synthetic probe；local 路径显示设备
快照、建议、3.03 GB consent，并提供 background/pause/resume/stop/restart continuation。

## 被取代方案

### ADR 0005：current-focus 普通写入

它扩大 Electron/Chromium 兼容面，同时允许处理期间的新焦点接收文本。V1.6 选择 capture-bound
安全性和可恢复失败；不完整 AX 编辑器通过 clipboard recovery 完成用户可控交付。

### ADR 0009：写入后回执

它为 Undo、correct 和 submit 提供目标校验。V1.6 删除这些成功后动作，receipt 缩小为修正观察的
进程内 binding，用户界面只在学习成功或写入失败时出现。

### ADR 0010：语音跟进编辑

它引入 edit intent、连续 receipts 和 history version lineage。V1.6 删除该链路。SpeechDetector
继续作为可选 Quick Dictate endpoint，默认关闭。

## 后果

### 收益

- 成功听写在写入后立即结束，交互清晰且可预测。
- target drift 转化为可恢复失败，跨应用误写风险显著降低。
- 自动学习来自真实修正，并通过 AI 过滤语义编辑。
- Apple Speech 与 AI 共享标准词典，Apple-only 用户仍获得手动词典价值。
- 一级 Personalization 与操作型 Onboarding 提高能力发现与首次成功率。

### 成本与风险

- 严格 AX value/element 不可用的自绘编辑器会进入 clipboard recovery。
- 60 秒 AX polling 需要真实编辑器、权限撤销和性能验收。
- remote correction classification 会把最小 spans 和 bounded context 发送给用户选择的 Provider。
- Apple `contextualStrings` 对具体词汇的提升程度取决于语言资源与系统实现。
- 本地 3.03 GB 下载和真实生成仍依赖设备、网络、磁盘和内存。

## 隐私与安全

- 不新增 TCC 权限、entitlement、账号、analytics 或服务端存储。
- strict fingerprint、receipt 和 observer baseline 只存在当前进程，不进入 history/preferences/logs。
- remote learning payload 只含最小 spans、80/40 nearby context、app name 和 optional bundle ID。
- AI 输出按 strict schema、source containment、candidate count 和 confidence 校验。
- secure input、AX failure、focus drift 和 timeout 全部 fail closed 或 quiet stop。
- failed final text 留在系统 clipboard，用户通过恢复卡明确控制后续粘贴。

## 迁移与兼容

V1.6 直接移除旧生产入口和接口，不增加兼容层。`UserPreferences` 新增
`automaticDictionaryLearningEnabled` 与 `quickDictateEnabled`；缺失字段分别采用 `true` 与 `false`。
自动学习运行时还要求 intelligence mode 为 remote/local。默认 hotkey set 移除 Ask，新创建历史
不包含 Ask 或 edit lineage；已有 history 保持可读展示。`DictionaryEntry` 与 `AppToneProfile` 数据结构保持。

## 验证

```zsh
swift test --filter DictionaryLearning
swift test --filter AppleSpeechServiceTests
swift test --filter V16SystemAdapterTests
swift test --filter CaptureHUDVisualStateTests
swift test --filter OnboardingV16FlowTests
swift test --filter AppSessionCoreFlowTests
swift test
./script/build_and_run.sh --release --no-launch
```

T3 覆盖 HUD short/medium/long、monotonic width、center、two-line、Reduce Motion、recovery、learned、
八步 Onboarding 和 Personalization。T4 在 TextEdit、Notes、browser/ChatGPT、Electron 验证快捷键、
preview、strict delivery、focus drift、clipboard recovery、correction learning 和 semantic edit rejection。
T5 分别验证 remote/local polish、Translate、learning、tone，以及 local download control。

## 文档同步

- [`architecture.md`](../architecture.md)
- [`core-flow.md`](../core-flow.md)
- [`models.md`](../models.md)
- [`permissions.md`](../permissions.md)
- [`privacy-security.md`](../privacy-security.md)
- [`testing.md`](../testing.md)
- [`troubleshooting.md`](../troubleshooting.md)
- [`PRIVACY.md`](../../PRIVACY.md)
