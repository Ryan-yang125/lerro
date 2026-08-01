# Lerro Brand Kit

Lerro（读音 `LEH-ro`）是一款本地优先的 macOS 语音写作工具。本目录是
Phase 1 品牌系统的 source of truth。产品视觉以自适应黑白灰内容层、系统强调色交互层、
清晰文字层级、克制材质和即时反馈构成 Apple-native 桌面体验。

核心标志采用 A4 平面结构：左侧 `L` 表示输入起点，中部双拱对应 Lerro 的 `rr`
节奏，末端开放 `o` 形成文字落点与光标切口。品牌体验围绕一句话展开：

> 自在说，清楚写。
>
> Speak freely. Write clearly.

## 系统原则

- App Icon 与导出 Logo 使用固定 Ink Black / Soft White 黑白组合。
- 主 UI 的画布、卡片、文字、普通图标与 hover 使用 `LerroTheme` 自适应黑白灰色板；
  主要动作与焦点继承 macOS `controlAccentColor`，用户修改系统强调色后自动同步。
  success、warning、error 保留 macOS system status colors。
- 浅色文字层级为 `#292929`、`#5D5D5D`、`#9E9E9E`；必要的 12 pt 小字使用
  `#6B6B6B` 保证可读对比度。深色与 Increase Contrast 使用对应自适应值。
- App 内 inline mark 按信息层级使用主文字或次级文字；品牌 badge 保持固定黑白。
- App UI 使用 SF Pro 与苹方，技术信息使用 SF Mono。字体由 macOS 提供。
- 主窗口字号采用 24 / 14 / 13 / 12 pt 四级系统，tracking 统一为 `-0.15`。
- 导航图标与圆角分别为 14 / 8 pt；卡片图标与圆角分别为 20 / 16 pt；
  主要 CTA 使用 pill 形态。
- 菜单栏图标采用 monochrome template artwork，状态依靠轮廓、节奏和符号区分。
- hover 使用 150 ms ease-out，pointer-down 立即下沉 1 pt；Reduce Motion 下取消位移。
- HUD 保持既有外壳、声线、processing 节奏、状态切换和静音反馈；processing 三点使用
  系统强调色，形成克制的处理中状态提示。
- 所有核心动作保留文字标签、键盘路径和 VoiceOver 语义。

运行时 UI 的权威来源是
[`DesignTokens.swift`](../Sources/Lerro/DesignSystem/DesignTokens.swift) 与
[`Components.swift`](../Sources/Lerro/DesignSystem/Components.swift)。本目录的
[`brand.tokens.json`](tokens/brand.tokens.json) 和
[`LerroTokens.swift`](tokens/LerroTokens.swift) 保存可公开复用的同版规范。

## 目录

```text
Brand/
├── README.md
├── guidelines/
├── source/
│   ├── logo/
│   ├── app-icon/
│   ├── menu-bar/
│   ├── templates/
│   └── validation/
├── exports/
│   ├── logo/
│   ├── app-icon/
│   └── menu-bar/
├── tokens/
├── templates/
├── licenses/
├── scripts/
├── validation/
└── SHA256SUMS.txt
```

`source/` 保存可编辑 SVG。`exports/` 保存由脚本生成的 SVG、PDF、PNG 与 ICNS。
`templates/` 保存 GitHub、README、Release 与截图包装资产。`validation/` 保存小尺寸、
深浅外观和菜单栏状态的验收记录。

## 重新生成

在仓库根目录执行：

```zsh
./Brand/scripts/generate-assets.sh
./Brand/scripts/verify-assets.sh
```

生成脚本依赖 macOS 自带的 Swift、AppKit、`iconutil`、`sips`、`xmllint` 与
`shasum`。输出采用 sRGB，并保持相同输入产生相同像素和哈希。

## 快速选用

| 场景 | 资产 |
| --- | --- |
| 产品与仓库主标志 | `exports/logo/lerro-lockup-horizontal.svg` |
| 仅符号 | `exports/logo/lerro-symbol.svg` |
| 16–24 px | `exports/logo/lerro-micro-16.svg`、`lerro-micro-24.svg` |
| App Icon | `exports/app-icon/Lerro.icns`、`lerro-app-icon-1024.png` |
| 菜单栏 | `exports/menu-bar/` 中四态 template assets |
| GitHub 社交图 | `templates/github-social-preview.png` |
| README Hero | `templates/readme-hero-light.png`、`readme-hero-dark.png` |

## 工程接入

生成脚本会重建全部公开导出，同时把 `Lerro.icns` 与菜单栏四态模板同步到
`Sources/Lerro/Resources`。`verify-assets.sh` 校验 SVG、全尺寸 ICNS、运行时资源
逐字节一致性、颜色边界和 SHA-256；Release 总门禁会调用同一资产校验。

## 许可

资产归属与第三方依赖记录见
[`licenses/ASSET-LICENSES.json`](licenses/ASSET-LICENSES.json)。系统字体仅通过
字体栈引用，仓库中未分发 Apple 字体文件。
