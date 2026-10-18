# 0014：主窗口重构与独立设置窗口

- 状态：accepted
- 日期：2026-10-16
- 决策人：Lerro maintainers
- 关联任务/PR：Lerro v1.7 主窗口
- 替代：ADR 0012 中「个性化一级页面」的导航与页面形态；V1.6 的设置浮层

## 背景

V1.6 主窗口使用自绘 sidebar、卡片、pill 与窗口内设置浮层。历史页只显示文本，词典是自绘列表，
个性化页是应用 Grid，没有默认语气。设置浮层与主窗口争用同一块内容区，系统控件使用系统蓝，
与 V1.7 品牌（ADR 0013）的墨水蓝不一致。


## 决策驱动因素

- 使用原生组件获得系统一致的行为、键盘导航和 VoiceOver 支持。
- 设置独立成窗口，符合 macOS 的 ⌘, 习惯。
- 品牌强调色进入系统控件。
- 历史需要能回看 AI 改了什么、耗时在哪、发给 AI 的上下文是什么。

## 方案

- 主窗口使用 `NavigationSplitView`。侧栏含 wordmark、首页 / 历史 / 词典 / 应用语气（带数量 badge），
  底部为 AI 状态行（`AppSession.intelligenceStatus`）、设置齿轮与版本号。
  `SidebarDestination` 为 `home`、`history`、`dictionary`、`appTones`；个性化更名为应用语气。
- 首页：今天 / 近 7 天 / 全部三档统计（`UsageStatistics`）、7 天柱状图、快捷键键帽、麦克风菜单、
  最近 6 条记录、最近学到的词、空状态。
- 历史：列表加详情。详情有结果 / 对比原文 / 原文三个视图，对比由 `LerroCore` 的 `TextDiff` 计算；
  显示阶段耗时条、发给 AI 的上下文，以及通过 `LerroMac` 的 `RecordingPlayer` 播放录音。
- 词典：原生 `Table`，7 天内学到的词带「新」标记；CSV 导入导出使用 `phrase,replacement` 两列。
- 应用语气：卡片只用于应用语气对象。新增 `UserPreferences.defaultToneInstruction`，没有匹配到已启用的
  应用语气时使用；编辑器可用自定义示例句运行 AI 预览。
- 设置：标准 `Settings` 场景窗口（⌘,），标签为通用 / 快捷键 / 智能 / 用量 / 隐私 / 关于（`SettingsTab`）。
  打开方式固定为设置 `session.settingsTab` 后调用 `openSettings()`。删除 `SettingsDestination`、
  `SettingsEntryPoint`、`isSettingsPresented`、`presentSettings(_:)`、`dismissSettings()`。
- 强调色：`LerroTheme.accent`（浅 `#2F5BFF`、深 `#4A6BFF`）、`accentButton`（深色 `#3557F0`）、
  `accentSoft`。同一颜色编译进 `Assets.car` 的 `AccentColor`（`Brand/source/app-icon/Accent.xcassets`，
  `Info.plist` 的 `NSAccentColorName`），系统控件继承它。状态色继续使用系统绿、橙、红。
- 字体刻度 `LerroFont`：pageTitle 15 semibold、body 13、detail 16、stat 30、caption 12、footnote 11、
  sectionLabel 11 semibold，tracking 仍为 `-0.15`。
- 共享组件集中到
  [`MainWindowComponents.swift`](../../Sources/Lerro/DesignSystem/MainWindowComponents.swift)：
  `LerroButtonStyle`、`LerroIconButton`、`LerroShortcutKeys`/`LerroKeycap`、`LerroAppIcon`、
  `LerroStatusDot`、`LerroChip`、`LerroEmptyState`、`LerroSectionHeader`。旧的卡片、pill 与自绘导航组件已删除。
- Fixture：`LERRO_FIXTURE_DESTINATION=home|history|dictionary|appTones` 选择主窗口页面；
  `LERRO_FIXTURE_PRESENTATION=settings-general|settings-shortcuts|settings-intelligence|settings-usage|settings-privacy|settings-about`
  打开设置窗口对应标签。HUD fixture 不变。

## 备选方案

- 保留设置浮层：改动小，但与 `Settings` 场景、⌘, 和多窗口习惯不一致，未采用。
- 继续自绘列表和卡片：视觉可控，但键盘、选择、排序和辅助功能需要自行实现，未采用。
- 只在 SwiftUI 层设置 tint：系统控件和 AppKit 弹出层仍使用系统蓝，未采用。

## 后果

### 收益

- 主窗口与设置窗口使用系统标准交互，历史页可以解释一次听写的过程与耗时。
- 强调色在系统控件、品牌和主按钮之间一致。

### 成本与风险

- 旧 fixture 名称失效，截图基线需要重新生成。
- `Assets.car` 随强调色变化，需要在 Release 打包后复验。

## 隐私与安全

历史详情显示的上下文来自已持久化的 `contextReceipt`，不新增采集。录音回放只读取用户已保存的录音，
受 `saveAudio` 与 `historyRetention` 约束。词典 CSV 导出由用户显式触发。日志不新增文本内容。

## 迁移与兼容

`UserPreferences.defaultToneInstruction` 缺省解码为空串，空串表示不加语气。不保留旧导航枚举和设置入口。

## 验证

```zsh
swift test --filter UserPreferencesTests
swift test --filter AppSessionCoreFlowTests
swift test --filter TextDiffTests
swift test
./script/build_and_run.sh --release --no-launch
```

fixture 覆盖四个主窗口页面与六个设置标签，在 1080×750、988×658、浅色、深色、Increase Contrast、
Reduce Transparency、Reduce Motion 下截图，并用 Release app 检查真实窗口、⌘, 和 VoiceOver。

## 文档同步

`AGENTS.md` 的 UI 规则、[`docs/architecture.md`](../architecture.md) 与 [`docs/development.md`](../development.md) 的 fixture 表。
