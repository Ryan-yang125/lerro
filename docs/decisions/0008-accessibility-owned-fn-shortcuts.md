# 0008：辅助功能权限与 Fn 快捷键物理所有权

- 状态：accepted
- 日期：2026-08-04
- 决策人：Lerro
- 部分替代：0003 的权限前提说明

## 背景

Lerro 使用 `SpeechAnalyzer` 和 `SpeechTranscriber` 进行设备端转写，不需要 `SFSpeechRecognizer` 的 Speech Recognition
授权。全局快捷键和 Command-V 都依赖辅助功能权限。Fn 快捷键若只依赖 aggregate flags，重复 flags、Globe keyCode
与尾随 release 事件可能脱离同一物理手势，系统随后会执行「表情与符号」动作。

## 决策

- 生产权限只请求麦克风与辅助功能。
- 全局快捷键使用 HID/head-insert active event tap，mask 为 keyboard down、keyboard up 与 modifier changes（`0x1C00`）。
- 实体 modifier keyCode 进入独立 pressed 集合；Fn 63 与 Globe 179 映射到同一语义，左右同类 modifier 保留各自状态。
- 命中的 Fn/Globe 序列从首个事件到明确 key-up 或 flags-clear release 均由 Lerro 吞键；physical drain 和 definitions
  更新保持该所有权。tap 被禁用时先取消逻辑手势，再在 main queue 完整重建。
- Command-V 提交前检查 `CGPreflightPostEventAccess()`。
- 空闲 HUD 直接 `orderOut`，不建立鼠标追踪热区。

## 后果

- onboarding 只呈现用户需要授权的两项权限。
- Fn 听写与 Fn+Shift 翻译隔离系统 Emoji/Globe 行为。
- 外接键盘的 Fn 固件可能不发送可观察事件，需要在目标键盘上确认。

## 验证

`GlobalHotkeyMonitorTests` 覆盖 Fn 63、Globe 179、flags-only、key-only、重复 flags、physical drain、tap 重建与最终 release。
`AccessibilityTextDelivererTests` 覆盖提交前的辅助功能检查。
