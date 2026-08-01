# 0005：普通文本写入使用当前键盘焦点

- 状态：accepted
- 日期：2026-07-31
- 决策人：Lerro maintainers
- 关联任务/PR：本地 Phase 5 文本交付兼容修复
- 替代：ADR 0004 中普通插入的 AX 焦点、目标身份与选区折叠规则

## 背景

ADR 0004 建立了事务化剪贴板、Command-V、commit point 与恢复边界，同时要求普通
`.insert` 在提交前读取 AX focused element 和选区。实机运行中，Electron、Chromium
和部分自绘编辑器可以正常接收 Command-V，却不会稳定暴露这些 AX 属性。PID、bundle
和前台应用匹配时，交付仍会在剪贴板写入前停止。

本地原生参考实现的投递调用图确认了一条更兼容的路径：归档剪贴板、写入 transient
文本、向提交瞬间的当前键盘焦点发送 Command-V、等待 500ms、恢复剪贴板。普通文本
写入不依赖 AX 上下文。

## 决策驱动因素

- 原生与自绘文本控件统一消费系统粘贴命令。
- 语音处理期间保留用户对键盘焦点的控制。
- AX 上下文缺失不再阻断普通听写和翻译。
- Rewrite 的选区替换继续验证原始语义与目标。
- 剪贴板恢复、取消和 commit point 保持确定。

## 方案

1. `.insert` 在捕获上下文通过开始阶段隐私检查后，直接进入 current-focus paste。
2. 同一个 MainActor 步骤以 best-effort 方式归档并写入 general pasteboard，创建带 Command flag 的 V
   down/up，发布到 HID event stream 并触发 commit handler。
3. 自动普通插入不读取 focused element、selection、PID 或 bundle，也不重新激活捕获应用。
4. Ask card 的显式普通插入先恢复捕获应用，只等待顶层应用身份成为当前键盘目标。
5. 当前选区遵循目标控件的标准 Command-V 语义；处理期间发生的焦点变化决定最终落点。
6. 临时内容保持 500ms，随后恢复归档的可读取 item/type；期间产生的新剪贴板内容会被归档恢复覆盖。
7. `.replaceSelection` 继续走 ADR 0004 的严格目标身份、安全状态、focused element、
   原选区文本与 fingerprint 检查。

## 后果

### 收益

- Electron、Chromium、自绘编辑器和 AX 信息不完整的输入框可以使用同一写入路径。
- 普通插入的延迟更低，剪贴板写入后立即提交 Command-V。
- 普通链路与上下文读取解耦，AX 失败只影响需要选区语义的 Rewrite。

### 成本与风险

- 用户在处理期间切换焦点时，文本会写入新的当前焦点。
- 当前存在选区时，目标控件通常会用新文本替换该选区。
- CGEvent API 无法确认目标控件已经消费事件，真实输入框仍由用户验收。

## 隐私与安全

开始录音前的 `CapturePrivacyPolicy` 保持不变。普通插入不读取新的 AX 内容，也不增加
网络、数据字段、日志或权限。Rewrite 继续执行交付前安全与选区检查。剪贴板内容不进入
日志或历史元数据。

## 迁移与兼容

该决策不改变 Bundle ID、数据格式、偏好、历史或模型缓存。回滚代码会恢复普通插入的
严格 AX 门禁，并重新出现第三方编辑器兼容问题。

## 验证

- `AccessibilityTextDelivererTests` 覆盖 element unavailable、selection unavailable、
  当前焦点、缺少捕获身份、并发事务与严格 Rewrite。
- `AppSessionCoreFlowTests` 继续覆盖交付 commit、取消和历史状态。
- 用户使用新构建的 Release app 在真实目标输入框验收 Dictate / Translate。

## 文档同步

- `AGENTS.md`
- `docs/core-flow.md`
- `docs/privacy-security.md`
- `docs/testing.md`
- `docs/troubleshooting.md`
