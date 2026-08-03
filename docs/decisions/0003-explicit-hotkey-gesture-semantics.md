# 0003：显式快捷键手势语义

- 状态：accepted
- 日期：2026-07-31
- 决策人：Lerro maintainers
- 关联任务/PR：本地 Phase 5 核心链路完善
- 替代：无
- 部分替代：[`0008-accessibility-owned-fn-shortcuts.md`](0008-accessibility-owned-fn-shortcuts.md)

## 背景

旧实现将 Fn 按下、松开、双击与锁定录音硬编码在
[`GlobalHotkeyMonitor.swift`](../../Sources/LerroMac/Hotkeys/GlobalHotkeyMonitor.swift)，
`ShortcutActivation` 的持久化值没有参与运行时决策。普通组合键只监听 key-down，
设置录制器也无法录入单修饰键。权限刷新还会重复重建 event tap，并在 Fn 按住期间
清除 down 状态，导致 release 无法完成录音。

产品需要支持可视化按键测试、单修饰键、按住说话和按一下开关，同时保持系统 chord、
安全输入框、原输入焦点和跨应用交付边界。

## 决策驱动因素

- 一次按下与对应松开形成可证明的 capture 生命周期。
- Command-C 等系统 chord 保持原行为。
- 录制器测试不会启动真实麦克风或写入用户应用。
- 旧偏好迁移后保持原 Fn hold 与普通组合键 toggle 行为。
- Core 规则可测试，AppKit 与 CGEventTap 集中在 macOS adapter。
- UI 使用原生 first responder、semantic colors、Reduce Motion 与 VoiceOver。

## 方案

Core 定义两个公开模式：

- `hold`：同一 definition 的 `began` 启动，`ended` 完成。
- `toggle`：第一次 `began` 启动锁定录音；同一 action 的任一 toggle binding 再次
  `began` 均可完成。

`HotkeyTrigger` 携带 action、mode、phase 与 definition ID。`AppSession` 保存启动本次
capture 的 binding 身份，并只接受匹配 release。trigger 通过带 dispatch epoch 的单一
FIFO stream 消费，使快速 down/up 与前缀升级保持确定顺序；monitor 停止后留下的旧
epoch 事件永久失效，已从当前 preferences 删除的 definition 也会在消费前失效。取消清理
期间以 FIFO 保存 hold，以奇偶状态归并同 action toggle；显式 cancel 清空待重放状态。
程序化启动与快捷键启动共享 generation guard。`HotkeySignature` 规范化物理 binding 后
用于冲突检测与迁移去重。

`GlobalHotkeyMonitor` 使用 active event tap 监听 `flagsChanged`、`keyDown`、
`keyUp`。单修饰键先进入 120 ms 候选；候选期间出现其他键时让系统 chord 继续执行。
命中的普通键 down、repeat 与 up 全部吞掉。重复 `start` 与相同 definitions 的
`update` 保持幂等。配置中的更具体 chord 可以接管已激活的 modifier 前缀。逻辑 reset
保留已 claim 的物理键至完整 release；tap disabled 或 Secure Input watchdog 会取消活动
hold 并进入 drain。Secure Input 隐藏旧 release 后出现的首个非 repeat key-down 会清除
同键 stale claim，再进入正常匹配；旧 repeat 继续 drain。独立 recovery generation 覆盖
watchdog 先于新事件完成对账的顺序；左右同类 modifier 通过具体物理 key state 区分 down
与 partial release。自产 Command-V 使用 source marker 绕过 filter。

SwiftUI 录制器 reducer 分开持有 live/peak/validated chord、模式、校验与视觉状态。
一个窄 `NSViewRepresentable` 只转发本窗口键盘事件，并在检测中临时 resign 后异步恢复
first responder。显式开始/停止检测兼顾实时反馈与 Tab/Return 标准导航。进入
Onboarding 或设置录制器时暂停生产 monitor，退出时恢复；
关键变更按 action、物理 signature、activation 与显示名确认写入本地 preferences 后才
关闭或前进；同时排队的其他设置不会造成快捷键保存误报。活动 capture 期间禁用绑定
增删改。

## 备选方案

### 继续为 Fn 编写专用状态机

改动范围较小，新的单修饰键、任意 Fn chord、普通键 key-up 和持久化模式仍会形成多套
分支，测试矩阵与 UI 容易再次失配。

### 只提供轻触开关

状态机更短，无法满足按住说话的明确产品需求，也无法覆盖习惯使用 push-to-talk 的用户。

### 全部快捷键使用 SwiftUI `keyboardShortcut`

适合应用窗口内命令，无法覆盖跨应用全局 modifier-only、吞键和 key-up 生命周期。

## 后果

### 收益

- UI、持久化、global event tap 与 AppSession 使用同一套模式语义。
- 单修饰键和普通组合键共享数据驱动匹配。
- release 与 definition ID 绑定，过期或其他按键的松开无法结束当前 session。
- 录制器直接证明当前键盘是否送出 down/up。
- 匹配键不会进入前台编辑器，系统 chord 保持透传。

### 成本与风险

- 当前 HID event tap 依赖 Accessibility；权限在 capture 中被撤销时，AppSession 先取消
  capture，再停止 event tap。权限与 tap 位置由 ADR 0008 更新。
- 单修饰键 hold 有 120 ms 意图确认延迟。
- 外接键盘的 Fn/Globe 固件可能不向 macOS 发送事件，录制器会保持等待状态。
- tap 被系统禁用、Secure Input 切换和物理键状态对账仍需要最终 Release 实机矩阵。

## 隐私与安全

录制器只处理用户主动测试的键码与 modifier 集合，并只保存本地快捷键偏好。它不保存
按键序列、文本内容或时间线，也不写入日志或网络。生产 shortcut filter 只吞掉已经
配置且精确匹配的普通键。secure input 时清理候选并停止活动 hold。

## 迁移与兼容

- 旧 capture + Fn `press` → `hold`。
- 旧普通 capture `press` → `toggle`。
- 旧 `doublePress` → `toggle`。
- 旧 `dictateHandsFree`、`translateHandsFree`、`askHandsFree` → 对应基础 action +
  `toggle`。
- 旧 modifier keyCode 54–63 规范化为 modifier-only flags。
- 新文档继续解码 legacy enum case，保存的新设置只写 `hold` 或 `toggle`。

回滚到旧二进制时，新 `toggle` case 无法被旧 enum 解码。发布回滚应同时恢复迁移前设置
备份，或由旧版本使用安全默认快捷键。

## 验证

- `UserPreferencesTests`：默认值、legacy JSON 与新模式 round-trip。
- `GlobalHotkeyMonitorTests`：modifier-only、Fn 前缀升级、hold/toggle、definitions 变更取消、physical drain、Secure Input 恢复、自产事件、系统 chord 与幂等 update。
- `ShortcutRecorderPolicyTests`：peak chord、候选隔离、单修饰键、三键限制、日常输入保护与系统保留组合。
- `AppSessionCoreFlowTests`：FIFO/epoch trigger、当前 definition 校验、清理期 toggle parity、显式 cancel、前缀转交、definition-bound hold、跨 binding toggle、HUD lock、程序化与快捷键启动期、配置态隔离、权限撤销与并发持久化确认。
- fixture：Onboarding shortcut step、hold/toggle、浅色/深色与 Reduce Motion。
- 最终签名 Release：内置/外接键盘、TextEdit、第三方编辑器、权限撤销恢复与 event tap reset。

## 文档同步

- `AGENTS.md`
- `docs/architecture.md`
- `docs/core-flow.md`
- `docs/permissions.md`
- `docs/privacy-security.md`
- `docs/testing.md`
- `docs/ui-parity.md`
- `docs/troubleshooting.md`
- `PRIVACY.md`
