# 0012：严格写入与 AI 自动词典学习

- 状态：accepted
- 日期：2026-08-13
- 决策人：Lerro maintainers
- 替代：早期的 current-focus 写入、写入后回执与撤回、语音跟进编辑和版本链

## 背景

V1.4 至 V1.5 在写入后继续展示回执，并提供撤回、语音修改、版本恢复、重新听写和语音发送。真实使用显示这段后处理破坏了
「按下说话、实时预览、再次按下、写入完成」的心智模型。current-focus paste 还会在用户处理期间切换应用或输入框时，把结果写到新的焦点。

用户修正听写错误的自然动作发生在已写入的文本内，因此 V1.6 把它作为自动词典的来源。

## 决策

### 1. 能力与入口

- 新安装默认 `raw` 模式（Apple Speech 转写）。
- 生产 capture 入口只有 Dictate 与 Translate。AI 提供 Dictate 润色、Translate、自动词典分类和应用语气。

### 2. Capture-bound 严格写入

1. capture 开始时冻结应用 PID/bundle、focused element、role/subrole、完整 value、selection 与 secure state。
2. 写入前重新读取并严格比对。任何漂移都在 Command-V 前停止。
3. 剪贴板事务和 commit point 见 [ADR 0004](0004-transactional-command-v-delivery.md)。
4. 写入成功后 HUD 立即消失，交互结束。
5. 写入失败时把最终文本复制到剪贴板，保存 failed 历史，HUD 显示「再次复制 / 关闭」恢复卡。
6. 成功路径没有回执、撤回、语音修改、版本恢复、重新听写和语音发送。

### 3. 自动词典学习

1. 成功的 AI Dictate 返回进程内的 `TextDeliveryReceipt`，只用于修正观察。
2. `AccessibilityDeliveredTextObserver` 在同一应用和元素最多观察 60 秒，每 100 ms 读取 value，变化稳定 800 ms 后处理。
3. 已写入文本在基线中必须唯一，差异必须与其范围相交；本地 UTF-16 算法输出最小 original/corrected span 与前 80、后 40 的上下文。
4. 当前 AI 以严格 JSON schema 返回 0 至 3 个候选。差异代码只定位变化，学习判断由 AI 负责。
5. phrase 来自 original span，replacement 来自 corrected span，confidence 不低于 0.7 且不重复的候选保存为全局 learned 词条
   （2026-10-18 起，识别纠错与应用无关）。
6. 人名、品牌、术语、拼写、同音词、音译和中英文专名可以学习；语义、事实、日期、语气、增删句、结构和大段改写返回零候选。
7. 学习成功显示 3 秒提示并可撤销。AI 未启用、AX 不可用、secure input、应用或字段漂移、不支持的编辑器、新 capture 和超时都安静结束。

### 4. 词典

同一份词典服务提示词（`known_terms` 与命中条目）、词典页编辑与删除、CSV 和应用筛选。词典内容进入 Apple Speech 的方案已由
[ADR 0015](0015-speech-transcriber.md) 取消。

### 5. 导航与 onboarding

主窗口导航见 [ADR 0014](0014-main-window-rebuild.md)。onboarding 由可检测的真实操作解锁每一步：隐私、Speech、AI、快捷键、
真实听写、失败恢复、AI 词典、AI 语气。仅使用 Apple 转写的用户在恢复步骤后完成。

## 被取代的方案

- current-focus 普通写入：兼容更多自绘编辑器，同时允许处理期间的新焦点接收文本。现在选择 capture-bound 的安全性和可恢复的失败。
- 写入后回执与语音跟进编辑：需要连续 receipt 和历史版本链，与「成功即结束」的心智模型冲突，已删除。

## 后果

- 成功听写在写入后立即结束；目标漂移转化为可恢复的失败。
- AX value 或 element 不可用的自绘编辑器会进入剪贴板恢复。
- 自动学习把最小 span 和有限上下文发送给用户选择的 Provider。

## 隐私与安全

不新增权限、账号、analytics 或服务端存储。严格指纹、receipt 和观察基线只存在于当前进程，不进入历史、偏好和日志。远程学习的 payload
只含最小 spans、80/40 上下文、应用名和可选 Bundle ID。AI 输出按 schema、来源包含、候选数量和 confidence 校验，不合格时整体拒绝。

## 验证

```zsh
swift test --filter PipelineIntelligenceServiceTests
swift test --filter AppleSpeechServiceTests
swift test --filter V16SystemAdapterTests
swift test --filter AppSessionCoreFlowTests
```
