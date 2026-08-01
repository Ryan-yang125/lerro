# Color and Accessibility

## 自适应中性色板与系统强调色

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

`accent`、`primaryAction` 与 `focusBorder` 使用 macOS `controlAccentColor`，随用户在系统
设置中选择的强调色动态变化。主要动作文字使用
`alternateSelectedControlTextColor`，让系统为当前强调色提供对应前景。
Success、Warning、Error 分别继续使用 `systemGreen`、`systemOrange` 与 `systemRed`。

固定品牌资产使用 Ink Black `#111113` 与 Soft White `#F5F2EA`。这组颜色服务 App Icon、
Logo 与品牌预览；产品控件使用自适应黑白灰与系统状态色。

## 对比策略

- `#292929` 主文字在 `#FAFAFA` 上约为 `13.94:1`，`#5D5D5D` 次级文字约为
  `6.31:1`。
- `#9E9E9E` 在浅色主画布上约为 `2.57:1`，只承载可省略的低强调信息。
- 必须被读懂的 12 pt metadata 使用 `#6B6B6B`，在浅色主画布上约为 `5.11:1`。
- 主要 CTA 使用系统强调色与系统选中控件文字色；焦点通过强调色边界、表面和文字共同表达。
- 状态同时提供图标、形状和文字。颜色只承担辅助提示。
- Increase Contrast 下切换到专用画布、文字、填充和边界值。
- Differentiate Without Color 下保留 checkmark、warning、error 与处理状态的独立轮廓。
- Reduce Transparency 下使用实色自适应表面。

## 图像与模板

- 菜单栏源图保持纯黑与透明通道，macOS 负责浅色、深色和选中态着色。
- App Icon 保持 Ink Black 底面与 Soft White 前景，16 px 版本仍能识别 `L`、双拱与
  开放 `o` 的光标切口。
- 社交图和 README Hero 在浅色、深色各提供一份确定性导出。

## 验收

1. 在 Aqua、Dark Aqua、Increase Contrast 与 Reduce Transparency 下检查全部自适应 token。
2. 使用 Accessibility Inspector 验证图标按钮的 label、value、hint 与 enabled state。
3. 使用 16、24、32 px 光栅预览检查断线、粘连与光标辨识度。
4. 使用灰阶预览验证内容层级，并切换至少两种系统强调色验证主要动作与焦点同步。
5. 验证 24 / 14 / 13 / 12 pt 与 `-0.15` tracking，必要小字只使用 Metadata Text。
6. 使用 VoiceOver 完成主导航、听写启动、取消、处理、错误恢复和设置路径。
