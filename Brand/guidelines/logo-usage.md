# Logo Usage

## 组成

| 元素 | 说明 |
| --- | --- |
| 标志（mark） | 光标加基线，36 × 61 品牌单位，两个图形之间留缝 6 |
| 字标（wordmark） | 大写 `Lerro`：`L` 是标志，`erro` 是 Inter SemiBold 轮廓 |
| 横向组合（lockup） | App Icon 加 `Lerro` 文字，用于官网导航与 GitHub |
| App Icon | 墨黑底板、墨水蓝光标、纸白基线 |

字标中的 `erro` 以路径保存，仓库不分发字体文件。Inter 4.1 的来源与许可见
[`ASSET-LICENSES.json`](../licenses/ASSET-LICENSES.json) 和
[`Inter-OFL.txt`](../licenses/Inter-OFL.txt)。

## 版本与文件

| 版本 | 文件 | 用途 |
| --- | --- | --- |
| Mark | `lerro-mark.svg` | 浅底，光标墨水蓝，基线墨黑 |
| Mark reversed | `lerro-mark-reversed.svg` | 深底，光标深底墨水蓝，基线纸白 |
| Mark mono | `lerro-mark-mono.svg` | 单色印刷与模板渲染 |
| Wordmark | `lerro-wordmark.svg`、`lerro-wordmark-reversed.svg` | 侧栏、页眉、文档 |
| Horizontal lockup | `lerro-lockup-horizontal.svg`、`lerro-lockup-horizontal-dark.svg` | README、官网导航、发布页 |
| Construction | `lerro-construction.svg` | 比例与留白参考 |

## 留白

四周留白等于光标宽度（10 个品牌单位）。周围图标、文字与边缘均位于留白范围之外。

## 最小尺寸

- 标志：屏幕上高度 12 px。
- 标志低于 32 px 高时使用小尺寸比例：光标宽 13，基线高 12，缝 5。
- 字标与横向组合：`L` 的高度同样不低于 12 px。
- App Icon：16 px 到 1024 px，16 px 仍可辨认光标和基线两段。
- 菜单栏：18 × 18 pt template image。

## 颜色

| 背景 | 光标 | 基线 / 字母 |
| --- | --- | --- |
| 纸白、白色、浅色画布 | 墨水蓝 `#2F5BFF` | 墨黑 `#15161A` |
| 墨黑、深色画布 | 深底墨水蓝 `#4A6BFF` | 纸白 `#F6F4EF` |
| 单色 | 与基线同色 | 100% 黑或 100% 白 |
| 菜单栏 | 与基线同色 | template image，由 macOS 着色 |

## 使用规则

- 保持原始比例、缝宽与圆角端点。
- 光标与基线保持分离，缝宽按构造图执行。
- 光标使用墨水蓝，基线和字母使用墨黑或纸白。
- 复杂背景上先放置纯色承载面，再放标志。
- 使用提供的 SVG 导出文件，不重新绘制或重新排版字标。

## 禁用

- 把光标与基线连成一笔。
- 把基线改成蓝色，或把光标改成非品牌色。
- 给标志添加描边、轮廓线、渐变、投影、浮雕。
- 旋转、倾斜、拉伸或镜像标志。
- 用 SF Pro 或其他字体重新排 `erro`。
- 在低于最小尺寸的位置使用标志。

## 菜单栏状态

| 状态 | 帧 | 图形信号 | 可访问标签 |
| --- | --- | --- | --- |
| idle | `Idle` | 完整的光标与基线 | `Lerro，空闲` |
| listening | `Listening`、`ListeningDim` | 光标闪烁，基线变淡 | `Lerro，正在听写` |
| processing | `Processing1`–`Processing4` | 光标变淡，基线从左向右画出 | `Lerro，正在处理` |
| error | `Error` | 光标变成「!」 | `Lerro，需要处理` |

图像接入 `NSImage` 后设置 `isTemplate = true`，菜单标题与 VoiceOver 标签同步更新。
动画时序见 [`motion.md`](motion.md)。
