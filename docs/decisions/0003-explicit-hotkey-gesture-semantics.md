# 0003：显式快捷键手势语义

- 状态：accepted
- 日期：2026-07-31
- 决策人：Lerro maintainers
- 部分替代：[`0008`](0008-accessibility-owned-fn-shortcuts.md)（权限前提）
- 补充：[`0019`](0019-microphone-prearm-at-modifier-key-down.md)（`armed` / `disarmed` 与预开麦）

## 背景

早期实现把 Fn 按下、松开、双击和锁定录音硬编码在
[`GlobalHotkeyMonitor.swift`](../../Sources/LerroMac/Hotkeys/GlobalHotkeyMonitor.swift)，持久化的 `ShortcutActivation` 不参与运行时决策。
普通组合键只监听 key-down，设置录制器无法录入单修饰键。权限刷新会重复重建 event tap，并在 Fn 按住期间清除 down 状态，
导致 release 无法结束录音。

## 决策

Core 定义两个公开模式：

- `hold`：同一 definition 的 `began` 启动，`ended` 完成。
- `toggle`：第一次 `began` 启动，同一 action 的任一 toggle binding 再次 `began` 完成。

`HotkeyTrigger` 携带 action、mode、phase 与 definition ID。`AppSession` 保存启动本次 capture 的 binding，只接受匹配的 release。
trigger 通过带 dispatch epoch 的单一 FIFO stream 消费，使快速 down/up 与前缀升级保持确定顺序；monitor 停止后的旧 epoch
事件与已从偏好中删除的 definition 在消费前失效。`HotkeySignature` 规范化物理 binding，用于冲突检测。

`GlobalHotkeyMonitor` 使用 active event tap 监听 `flagsChanged`、`keyDown`、`keyUp`：

- 单修饰键先进入候选：hold 120 ms 后激活，toggle 在松开时确认、按住超过 1 秒作废；期间出现其他键或鼠标点击时让系统 chord 继续执行。
- 命中的普通键 down、repeat 与 up 全部吞掉。
- 重复 `start` 与相同 definitions 的 `update` 保持幂等。
- 更具体的 chord 可以接管已激活的 modifier 前缀。
- 逻辑 reset 保留已 claim 的物理键直到完整 release；tap 被禁用或 Secure Input watchdog 触发时取消活动 hold 并进入 drain。
- Lerro 合成的 Command-V 带 source marker，绕过 filter。

SwiftUI 录制器 reducer 分开保存 live、peak 和已验证的 chord、模式与校验状态；一个窄 `NSViewRepresentable` 转发本窗口键盘事件。
进入 onboarding 或设置录制器时暂停生产 monitor。活动 capture 期间禁用绑定的增删改。

## 备选方案

- 继续为 Fn 编写专用状态机：单修饰键、任意 Fn chord 和持久化模式会形成多套分支。
- 只提供轻触开关：不能满足按住说话。
- SwiftUI `keyboardShortcut`：只在应用窗口内生效，无法覆盖全局 modifier-only、吞键和 key-up。

## 后果

- UI、持久化、event tap 与 `AppSession` 使用同一套模式语义；release 与 definition ID 绑定。
- 单修饰键 hold 有 120 ms 意图确认延迟；按下时已预开麦克风（ADR 0019），这段时间的音频不丢失。
- 外接键盘的 Fn/Globe 固件可能不向 macOS 发送事件，录制器会保持等待。

## 隐私

录制器只处理用户主动测试的键码与 modifier 集合，只保存本地快捷键偏好，不保存按键序列、文本或时间线。secure input 时清理候选并停止活动 hold。

## 验证

`GlobalHotkeyMonitorTests`、`ShortcutRecorderPolicyTests`、`AppSessionCoreFlowTests` 覆盖 hold/toggle、前缀升级、FIFO/epoch、
definition 校验、physical drain、Secure Input 恢复、自产事件与幂等 update。
