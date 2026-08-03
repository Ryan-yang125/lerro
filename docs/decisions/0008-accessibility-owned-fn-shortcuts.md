# 0008：辅助功能权限与 Fn 快捷键物理所有权

- 状态：accepted
- 日期：2026-08-04
- 决策人：Lerro
- 关联任务/PR：下一版本快捷键与权限改造
- 替代：0003 的权限前提说明

## 背景

Lerro 使用 `SpeechAnalyzer` 和 `SpeechTranscriber` 进行设备端转写，无需
`SFSpeechRecognizer` 的 Speech Recognition TCC。全局快捷键和 Command-V 都依赖
辅助功能权限。Fn 默认快捷键在 session event tap 下会把 Emoji/Globe 的最终事件交给系统。

## 方案

- 生产权限只请求麦克风与辅助功能。
- 全局快捷键使用 active HID event tap。
- 命中的 Fn modifier sequence 从首次 `flagsChanged` 到最终 release 均由 Lerro 吞键；
  physical drain、timeout 和 definitions 更新继续保留该所有权。
- 普通插入与 Rewrite 的 Command-V 提交前均检查 `CGPreflightPostEventAccess()`。
- 空闲 HUD 直接 `orderOut`，不建立鼠标追踪热区。

## 后果

### 收益

- Onboarding 只呈现用户实际需要授权的两项系统权限。
- Fn 听写和 Fn+Shift 翻译完整隔离 Emoji/Globe 行为。
- 空闲 HUD 不会遮挡下层应用。

### 成本与风险

- 外接键盘 Fn 固件可能不发送可观察事件，仍需在最终 Release app 实机确认。
- 真实 TCC、跨应用粘贴和 event tap timeout 属于实机验收边界。

## 隐私与安全

删除 Speech Recognition 与 Input Monitoring 请求和 usage description。音频、文本、日志和
剪贴板边界保持现有策略。

## 验证

- `GlobalHotkeyMonitorTests` 覆盖 Fn 按下、Fn+Shift、physical drain 与最终 release。
- `AccessibilityTextDelivererTests` 覆盖普通插入和 Rewrite 的辅助功能提交检查。
- Release app 复验 TextEdit、Emoji/Globe、内置/外接键盘和辅助功能撤权。

## 文档同步

同步 `permissions.md`、`core-flow.md`、`privacy-security.md`、`PRIVACY.md` 与测试矩阵。
