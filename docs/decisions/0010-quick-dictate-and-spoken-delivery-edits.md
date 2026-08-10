# 0010：Quick Dictate 与语音跟进编辑

- 状态：accepted
- 日期：2026-08-10
- 决策人：Lerro maintainers
- 关联任务/PR：Lerro v1.5
- 替代：无

## 背景

v1.4 已通过 ADR 0009 建立焦点绑定交付回执。v1.5 让一次点按 Dictate 在用户说完后自动
结束，并允许用户继续说一句明确指令修改刚写入的内容。端点检测必须保持普通 hold、手动
toggle 与其他动作的既有行为；连续修改必须在每次写回后重新验证实际目标，并保存可恢复
的文本版本。

## 决策驱动因素

- Quick Dictate 使用 Apple 原生 SpeechDetector，并在 SpeechAnalyzer 内与转写共享音频。
- 普通 hold、手动 toggle、Translate、Ask 与 Rewrite 保持原有停止语义。
- 普通新听写与跟进编辑拥有清晰的意图区分。
- 每次修改都绑定刚刚写回的 app、focused element 与内容。
- 历史可以展示版本数量并恢复上一版，保存策略继续覆盖全部编辑数据。
- 本地或 BYOK 语义编辑沿用捕获开始时冻结的模型配置与授权边界。

## 方案

1. `SpeechTranscribing.start` 接收会话级 `detectSpeechEndpoint`。只有快捷键触发的 toggle
   Dictate 传入 `true`；`AppleSpeechService` 此时才把 medium sensitivity 的
   `SpeechDetector` 加入 analyzer。
2. Speech 层发出 `speechStarted` 和 `silenceElapsed`。首段语音后的连续静音达到约
   1.2 秒时，`AppSession` 完成 Quick Dictate；重新检测到语音会取消当前静音窗口。
3. AppSession 在界面回执消失后最多 60 秒保留进程内编辑目标。只有
   `VoiceEditCommandResolver` 识别出的明确编辑意图进入编辑链，普通文本继续成为新听写。
4. 确定性编辑覆盖恢复、删除句子、精确替换和重新听写；缩短、扩写、语气、翻译与通用
   修改交给当前冻结的 Intelligence 配置。
5. `AccessibilityTextDeliverer.correct` 在同一 actor 事务中执行 Command-Z 与 Command-V，
   并返回新的完整 `TextDeliveryReceipt`。每次动作前验证 PID、bundle、secure state、
   focused element 与 value fingerprint；漂移会让后续编辑安全失效。
6. `DeliveryEditLineage` 保存 append-only 版本父链，记录来源、文本、时间以及可选模型与处理
   路径。HistoryEntry 以可选字段持久化 lineage；精确替换沿用 app-scoped 词典学习与删除入口。

## 备选方案

- 对所有录音会话启用 SpeechDetector：会改变 hold 与其他动作的识别门控和停止行为。
- 仅依赖固定录音时长：无法适配长短句与自然停顿。
- 将任何第二段语音当成编辑：普通连续听写会被误判。
- 复用旧 receipt 完成多次修改：旧 value fingerprint 无法证明最新写回目标仍然安全。
- 只保存最终文本：用户无法查看版本数量或逐版恢复。

## 后果

### 收益

- Dictate 形成一次点按、说话、自动写入的完整路径。
- 明确指令可以连续修改并逐版恢复，普通新内容保持独立。
- 每一版都有 fresh receipt 与完整漂移检查，跨 App 或内容变化会停止写回。
- 历史、词典与模型路由保留可审计信息，同时遵守现有保存和隐私策略。

### 成本与风险

- 1.2 秒静音阈值需要在真实麦克风、自然停顿与环境噪声中验收。
- SpeechDetector 依赖 macOS 26 的可用资源；资源与转写错误沿用 HUD 失败路径。
- 语义编辑质量取决于用户选择的本地或 BYOK 模型。
- 进程内 60 秒目标在重启后消失，历史版本仍保留文本 lineage。

## 隐私与安全

不新增权限、entitlement、外部服务或日志内容。SpeechDetector 与 Apple Speech 在设备上共享
当前录音流。recent edit target 和 fingerprints 只存在于进程内；它们不保存 focused value、
prompt 或凭据。历史 lineage 保存用户已交付的文本版本，并由现有 retention 和删除行为统一
管理。远程语义编辑继续遵守当前 Provider、API Key、上下文与 remote sharing 边界。

## 迁移与兼容

v1.5 直接采用带 `detectSpeechEndpoint` 的 Speech 协议并移除旧签名。HistoryEntry 新字段为
可选，已有记录继续解码；不新增偏好迁移。旧 Release 产物继续由各自签名、appcast 与不可变
下载键独立验证。

## 验证

- `AppleSpeechServiceTests` 覆盖首段语音、1.2 秒静音、语音恢复与会话清理。
- `VoiceEditCommandResolverTests` 与 `DeliveryEditLineageTests` 覆盖明确意图、普通文本隔离、
  确定性计划和版本父链。
- `AccessibilityTextDelivererTests` 覆盖连续修改、历史恢复、焦点/内容/element/security 漂移
  与并发拒绝。
- `AppSessionCoreFlowTests` 覆盖 Quick Dictate、确定性/语义/重新听写、冻结模型配置、词典学习
  与普通听写隔离。
- T4 使用 Release app 验收真实麦克风、自然停顿、物理 Fn、跨 App 焦点和 1.4 到 1.5 更新。

## 文档同步

- `README.md` / `README.zh-CN.md`
- `PRIVACY.md` / `PrivacyPolicy.html`
- `docs/architecture.md`
- `docs/core-flow.md`
- `docs/models.md`
- `docs/privacy-security.md`
- `docs/testing.md`
- `docs/releases/v1.5.0.md`
- `docs/releases/v1.3-v1.5-acceptance.md`
