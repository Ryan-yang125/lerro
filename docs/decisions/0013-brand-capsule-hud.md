# 0013：品牌 HUD 胶囊

- 状态：accepted
- 日期：2026-10-16
- 决策人：Lerro maintainers
- 关联任务/PR：Lerro v1.7 HUD
- 替代：ADR 0012 中 HUD 实时预览的外观部分（单调增宽、两行文本、卡片形态）

## 背景

V1.6 的 HUD 在不同状态之间切换形状：录音是胶囊，处理中是方块，失败是宽胶囊，恢复和学词是
圆角卡片。外壳是纯黑加灰描边，实时文字是「应用名 / 文本 / 波形」三层堆叠，成功写入后 HUD
直接消失，AI 失败退回原文时没有任何提示。HUD 是每天出现几十次的界面，品牌在其中没有体现。

V1.7 品牌重做选定方向 A「光标 L」：一根光标立在一条文字基线上组成 L。色板为墨黑
`#15161A`、纸白 `#F6F4EF`、墨水蓝 `#2F5BFF`。

## 方案

- 所有状态在同一个 40 pt 高的胶囊内完成，宽度以 spring 变化，最大 480 pt。状态模型位于
  [`CaptureHUDModel.swift`](../../Sources/Lerro/Features/HUD/CaptureHUDModel.swift)，
  `AppSession.currentHUDVisualState` 是唯一来源。
- 胶囊固定为墨黑 Liquid Glass，浅色与深色外观一致；Reduce Transparency 使用不透明墨黑，
  Increase Contrast 增加纸白描边。
- 录音态显示墨水蓝光标与 9 根音量波形；实时文字单行显示，旧文字从左侧淡出，光标跟随文字末尾。
- Command-V commit point 由 `HUDDeliveryFeedback.delivered` 让 HUD 立即淡出，取代 V1.6 的
  `suppressHUD`；AI 失败退回原文时显示橙色圆点和「已写入原文 · AI 未响应」，持续 2 秒。
  实测后决定成功写入不再显示 L 标志，用户看到文字出现在输入框里即可确认。
- 录音中连续 3 秒无人声时显示当前麦克风名称；免按住模式前 20 次显示结束键帽；计时 5 秒后出现。
- 处理中写「AI 润色中…」或「翻译中…」，不显示模型名；raw 听写跳过处理态。
- HUD 出现在捕获时输入框所在的屏幕；读不到输入框位置时使用鼠标所在屏幕。
- 状态色只表达问题：橙色表示退回原文或写入失败，红色表示识别失败。

## 备选方案

- 跟随系统深浅色的系统玻璃：与系统材质一致，但在浅色壁纸上缺少辨识度，品牌无法进入 HUD。
- 保留多形状卡片：恢复和学词信息容量更大，但状态切换像更换窗口，视线需要重新定位。

## 后果

### 收益

- HUD 状态之间连续形变，AI 退回原文有明确反馈。

### 成本与风险

- 胶囊在浅色外观中是唯一深色元素。

## 隐私与安全

捕获上下文新增输入框或窗口的屏幕几何 `focusedElementScreenFrame`，只用于选择 HUD 所在屏幕，
不持久化、不进入日志或远程请求。安全输入框同样只读取几何，不读取内容。

## 迁移与兼容

`UserPreferences` 新增 `handsFreeStopHintUseCount`，缺省解码为 0。

## 验证

```zsh
swift test --filter AppSessionCoreFlowTests
swift test --filter UserPreferencesTests
swift test
./script/build_and_run.sh --release --no-launch
```

HUD fixture 覆盖 `hud-waiting`、`hud-recording`、`hud-timer`、`hud-hands-free`、`hud-silent`、
`hud-dictating`、`hud-translating`、`hud-processing`、`hud-processing-translation`、
`hud-delivered-fallback`、`hud-error`、`hud-recovery`、`hud-dictionary-learned`，在浅色、深色、
Reduce Motion、Reduce Transparency 与 Increase Contrast 下截图。真实听写、翻译、取消、写入失败、
AI 失败与多显示器各走一遍。

## 文档同步

`AGENTS.md` 的 UI 规则与 [`docs/architecture.md`](../architecture.md) 的 UI 一节。
