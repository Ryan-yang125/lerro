# Color and Accessibility

## 自适应中性色板

SwiftUI 运行时由 `LerroTheme` 按当前 `NSAppearance` 解析颜色。下表记录主 UI 的
sRGB 合约；品牌资产继续使用后文的固定色。

| Token | Light | Dark | Increase Contrast Light / Dark | 用途 |
| --- | ---: | ---: | ---: | --- |
| Main | `#FAFAFA` | `#161616` | `#FFFFFF` / `#0D0D0D` | 主画布 |
| Main Contrast | `#F2F2F2` | `#202020` | `#EEEEEE` / `#272727` | 次级画布 |
| Top Layer | `#FFFFFF` | `#222222` | `#FFFFFF` / `#1A1A1A` | 卡片与顶层表面 |
| Sidebar | `#F1F1F1` | `#1B1B1B` | 沿普通值解析 | 侧边栏 |
| Elevated | `#FFFFFF` | `#292929` | 沿普通值解析 | hover 卡片表面 |
| Text | `#292929` | `#F2F2F2` | `#111111` / `#FFFFFF` | 主文字 |
| Secondary Text | `#5D5D5D` | `#B8B8B8` | `#444444` / `#D2D2D2` | 正文辅助层级 |
| Tertiary Text | `#9E9E9E` | `#929292` | `#5D5D5D` / `#C4C4C4` | 非必要低强调信息 |
| Metadata Text | `#6B6B6B` | `#BEBEBE` | `#444444` / `#D8D8D8` | 必要的 12 pt 小字 |
| Hover Fill | `#E9E9E9` | `#303030` | `#DEDEDE` / `#3D3D3D` | hover |
| Selected Fill | `#DEDEDE` | `#3A3A3A` | `#CECECE` / `#4A4A4A` | 选中态 |
| Border | `#D6D6D6` | `#444444` | `#858585` / `#787878` | 控件边界 |
| Thin Border | `#E3E3E3` | `#383838` | `#858585` / `#787878` | 卡片细边界 |

## 品牌色板

| 名称 | Token | 值 | 用途 |
| --- | --- | --- | --- |
| 墨黑 | `ink` | `#15161A` | App Icon 底板、HUD、深底背景 |
| 纸白 | `paper` | `#F6F4EF` | 基线、浅底背景、HUD 文字 |
| 墨水蓝 | `inkBlue` | `#2F5BFF` | 光标、浅色外观的主窗口强调色 |
| 深底墨水蓝 | `inkBlueOnDark` | `#4A6BFF` | 深色背景上的光标与强调色 |
| 石墨灰 | `graphite` | `#8B8C93` | 次要信息 |

`accent`、`primaryAction` 与 `focusBorder` 在浅色外观使用 `inkBlue`，在深色外观使用
`inkBlueOnDark`，不再跟随 macOS 系统强调色。主要动作文字使用白色。Success、Warning、
Error 分别继续使用 `systemGreen`、`systemOrange` 与 `systemRed`，墨水蓝不表达状态。

## 品牌色对比度

按 WCAG 2.x 相对亮度公式计算。正文文字阈值 4.5:1，大字与图形阈值 3:1。

| 前景 | 背景 | 比值 | 结论 |
| --- | --- | ---: | --- |
| 墨水蓝 `#2F5BFF` | 纸白 `#F6F4EF` | 4.70:1 | 文字与图形通过 |
| 墨水蓝 `#2F5BFF` | 白色 `#FFFFFF` | 5.17:1 | 文字与图形通过 |
| 墨水蓝 `#2F5BFF` | 主画布 `#FAFAFA` | 4.95:1 | 文字与图形通过 |
| 深底墨水蓝 `#4A6BFF` | 墨黑 `#15161A` | 4.17:1 | 图形与大字通过，正文小字低于 4.5:1 |
| 深底墨水蓝 `#4A6BFF` | 深色主画布 `#161616` | 4.17:1 | 图形与大字通过，正文小字低于 4.5:1 |
| 墨水蓝 `#2F5BFF` | 墨黑 `#15161A` | 3.50:1 | 仅满足 3:1 图形，深底改用 `#4A6BFF` |
| 深底墨水蓝 `#4A6BFF` | 纸白 `#F6F4EF` | 3.95:1 | 仅满足 3:1 图形，浅底改用 `#2F5BFF` |
| 纸白 `#F6F4EF` | 墨黑 `#15161A` | 16.45:1 | 通过 |
| 石墨灰 `#8B8C93` | 墨黑 `#15161A` | 5.40:1 | 通过 |
| 石墨灰 `#8B8C93` | 纸白 `#F6F4EF` | 3.05:1 | 仅满足 3:1 图形，不承载必须读到的文字 |
| 白色 | 墨水蓝 `#2F5BFF`（浅色外观主要按钮） | 5.17:1 | 通过 |
| 白色 | 深底墨水蓝 `#4A6BFF`（深色外观主要按钮） | 4.34:1 | 低于 4.5:1，见验收第 7 项 |

规则：

- 浅底上的墨水蓝文字使用 `#2F5BFF`。深底上的墨水蓝用于光标、图标、开关、焦点边界
  和 14 pt 以上的粗体文字；需要读到的小字使用主文字色。
- 石墨灰在浅底上用于图形和可省略的信息。

## 对比策略

- `#292929` 主文字在 `#FAFAFA` 上约为 `13.94:1`，`#5D5D5D` 次级文字约为
  `6.31:1`。
- `#9E9E9E` 在浅色主画布上约为 `2.57:1`，只承载可省略的低强调信息。
- 必须被读懂的 12 pt metadata 使用 `#6B6B6B`，在浅色主画布上约为 `5.11:1`。
- 主要 CTA 使用墨水蓝填充与白色文字；焦点通过墨水蓝边界、表面和文字共同表达。
- 状态同时提供图标、形状和文字。颜色只承担辅助提示。
- Increase Contrast 下切换到专用画布、文字、填充和边界值。
- Differentiate Without Color 下保留 checkmark、warning、error 与处理状态的独立轮廓。
- Reduce Transparency 下使用实色自适应表面。

## 图像与模板

- 菜单栏源图保持纯黑与透明通道，macOS 负责浅色、深色和选中态着色。
- App Icon 使用墨黑底板、墨水蓝光标和纸白基线，16 px 版本仍能分辨光标与基线两段。
- 社交图和 README Hero 在浅色、深色各提供一份确定性导出。

## 验收

1. 在 Aqua、Dark Aqua、Increase Contrast 与 Reduce Transparency 下检查全部自适应 token。
2. 使用 Accessibility Inspector 验证图标按钮的 label、value、hint 与 enabled state。
3. 使用 16、32、64 px 光栅预览检查光标与基线的缝是否保持分离，并在浅色与深色菜单栏
   检查八帧菜单栏图标。
4. 使用灰阶预览验证内容层级，并确认主要动作与焦点在浅色和深色外观中分别使用
   `#2F5BFF` 与 `#4A6BFF`。
5. 验证 24 / 14 / 13 / 12 pt 与 `-0.15` tracking，必要小字只使用 Metadata Text。
6. 使用 VoiceOver 完成主导航、听写启动、取消、处理、错误恢复和设置路径。
7. 在深色外观中检查主要按钮的白色文字（4.34:1）。低于 4.5:1 时调整按钮字号或字重，
   并在 Increase Contrast 下确认专用填充值。
