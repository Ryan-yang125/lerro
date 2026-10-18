# Lerro Brand Kit

Lerro（读音 `LEH-ro`）是一款本地优先的 macOS 语音写作工具。本目录是品牌系统的
source of truth。

标志是「光标 L」：一根圆角墨水蓝光标立在一条圆角基线上，两者之间留缝，读作字母 L，
也读作光标停在一行文字上。

> 自在说，清楚写。
>
> Speak freely. Write clearly.

## 系统原则

- 标志由光标和基线两个独立图形组成，光标可单独上色和动画。
- 固定品牌色为墨黑 `#15161A`、纸白 `#F6F4EF`、墨水蓝 `#2F5BFF`、深底墨水蓝
  `#4A6BFF`、石墨灰 `#8B8C93`。
- 墨水蓝用于光标、主窗口强调色和焦点；success、warning、error 使用 macOS system
  status colors，墨水蓝不表达状态。
- 字标为大写 `Lerro`：`L` 是标志，`erro` 是 Inter SemiBold 转成路径的轮廓。仓库不
  分发任何字体，Logo 不使用 SF Pro。
- App Icon 是 macOS 26 Icon Composer 分层文件，由 `xcrun actool` 编译为
  `AppIcon.icns` 与 `Assets.car`。
- 菜单栏使用 18×18 pt template image，状态依靠形状和动画区分。
- App 内：侧栏显示字标，关于页显示 App Icon、名称和版本，Onboarding 首屏显示标志，
  光标闪烁一次后停住。
- HUD 是墨黑玻璃胶囊，内含墨水蓝光标，见
  [ADR 0013](../docs/decisions/0013-brand-capsule-hud.md)。
- 主窗口画布、卡片、文字层级使用 `LerroTheme` 自适应黑白灰；字体使用 SF Pro、苹方与
  SF Mono，字号 24 / 14 / 13 / 12 pt，tracking `-0.15`。
- 所有核心动作保留文字标签、键盘路径和 VoiceOver 语义。

运行时 UI 的权威来源是
[`DesignTokens.swift`](../Sources/Lerro/DesignSystem/DesignTokens.swift)、
[`Components.swift`](../Sources/Lerro/DesignSystem/Components.swift) 与
[`LerroBrandGeometry.swift`](../Sources/Lerro/DesignSystem/LerroBrandGeometry.swift)。
[`brand.tokens.json`](tokens/brand.tokens.json)、
[`brand.css`](tokens/brand.css) 和 [`LerroTokens.swift`](tokens/LerroTokens.swift)
保存可公开复用的同版规范。

## 目录

```text
Brand/
├── README.md
├── guidelines/
├── source/
│   ├── logo/
│   ├── app-icon/AppIcon.icon
│   ├── menu-bar/
│   ├── icons/Glyphs.xcassets
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

`source/` 保存可编辑 SVG 与 Icon Composer 文件。`exports/` 保存由脚本生成的 SVG、
PDF、PNG、`AppIcon.icns` 与 `Assets.car`。`templates/` 保存 GitHub、README、Release
与截图包装资产。`validation/` 保存小尺寸、深浅外观和菜单栏状态的验收记录。

## 重新生成

在仓库根目录执行：

```zsh
./Brand/scripts/generate-assets.sh
./Brand/scripts/verify-assets.sh
```

生成脚本依赖 macOS 自带的 Swift、AppKit、`xcrun actool`、`sips`、`xmllint` 与
`shasum`。输出采用 sRGB，并保持相同输入产生相同像素和哈希。

## 快速选用

| 场景 | 资产 |
| --- | --- |
| 标志（浅底） | `exports/logo/lerro-mark.svg` |
| 标志（深底） | `exports/logo/lerro-mark-reversed.svg` |
| 标志（单色） | `exports/logo/lerro-mark-mono.svg` |
| 字标（浅底） | `exports/logo/lerro-wordmark.svg` |
| 字标（深底） | `exports/logo/lerro-wordmark-reversed.svg` |
| 标志加字标，产品与仓库主标志 | `exports/logo/lerro-lockup-horizontal.svg` |
| 标志加字标，深底 | `exports/logo/lerro-lockup-horizontal-dark.svg` |
| 构造图 | `exports/logo/lerro-construction.svg` |
| App Icon | `exports/app-icon/AppIcon.icns`、`Assets.car`、`lerro-app-icon-1024.png` |
| 菜单栏 | `exports/menu-bar/LerroMenu*Template.png`，八帧 |
| GitHub 社交图 | `templates/github-social-preview.png` |
| README Hero | `templates/readme-hero-light.png`、`readme-hero-dark.png` |
| Release 卡片、截图包装 | `templates/release-card.svg`、`templates/screenshot-frame.svg` |

菜单栏八帧：`Idle`、`Listening`、`ListeningDim`、`Processing1`–`Processing4`、
`Error`。

## 产品图标

产品概念（听写、智能润色、翻译、麦克风、首页、历史、词典、应用语气、其他所有应用、用量、通用、
快捷键、隐私、关于、新版本）使用 `source/icons/Glyphs.xcassets` 里的 Lerro 图标，通用操作继续用
SF Symbols。规则：

- 16 pt 网格，1.4 pt 圆头描边，圆角 2–3 pt，开放几何形，不用实心面。
- 光标竖条是品牌签名，只出现在听写、智能润色、首页、词典和关于；这五个图标另有
  `glyph-*-cursor` 图层，App 内着墨水蓝，只接受单色图片的位置（设置 tab）整体单色。
- 状态图标（成功、警告、错误）与播放控制保留 SF Symbols 实心版本，其余图标一律描边。
- 每个图标是一份 16×16 SVG，模板渲染、保留矢量，随 `generate-assets.sh` 编进 `Assets.car`；
  App 内通过 `LerroGlyph` 调用。设计稿见 `work/design-v1.7/icons.html`。

## 工程接入

生成脚本重建全部公开导出，同时把 `AppIcon.icns`、`Assets.car` 与菜单栏模板图同步到
`Sources/Lerro/Resources`。`verify-assets.sh` 校验 SVG、图标、运行时资源逐字节一致性、
颜色边界和 SHA-256；Release 总门禁会调用同一资产校验。检查项见
[`validation/asset-validation.md`](validation/asset-validation.md)。

## 许可

资产归属与第三方记录见
[`licenses/ASSET-LICENSES.json`](licenses/ASSET-LICENSES.json)。字标中的 `erro`
使用 Inter 4.1（Rasmus Andersson，SIL Open Font License 1.1）的字形轮廓，许可证全文
见 [`licenses/Inter-OFL.txt`](licenses/Inter-OFL.txt)，字体文件不随仓库分发。系统字体
仅通过字体栈引用。
