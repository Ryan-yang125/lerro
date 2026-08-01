# Logo Usage

## 组成

Lerro 标志由三段连续语义组成：

1. 左侧竖笔与圆角转折形成 `L`，表示输入起点。
2. 中部两个圆拱压缩双 `rr`，表示连续语音节奏。
3. 右侧开放 `o` 形成光标切口，表示可编辑文字已经落位。

## 版本

| 版本 | 用途 |
| --- | --- |
| Symbol | App 内品牌入口、头像、较大图形 |
| Micro 16 | 菜单、紧凑工具栏、16 pt 环境 |
| Micro 24 | 工具栏、状态面板、24 pt 环境 |
| Horizontal lockup | README、网站、发布页 |
| Vertical lockup | 方形版面、社交图、启动画面 |
| Monochrome | 单色印刷、模板渲染、低色彩环境 |
| Reversed | 深色或高对比背景 |

## 留白

以 full symbol 的主笔画宽度 `x` 为单位，四周保留至少 `2x`。横向组合中，symbol 与
wordmark 的间距为 `3x`。周围图标、文字与边缘均位于留白范围之外。

## 最小尺寸

- Micro Mark：16 × 16 pt
- Full Symbol：24 × 24 pt
- Horizontal lockup：96 pt 宽
- Vertical lockup：72 pt 宽
- App Icon：从 16 px 到 1024 px 使用同一主轮廓，并按像素尺寸调整细节

## 颜色

- App Icon：Ink Black `#111113` + Soft White `#F5F2EA`
- 浅色画布：Ink Black symbol + Label wordmark
- 深色画布：White symbol + White wordmark
- 单色：100% Black 或 100% White
- 菜单栏：100% Black template source，由 macOS 自动着色
- App 内 inline mark：按界面层级使用 `label` 或 `secondaryLabel`
- App 内品牌 badge：Ink Black 承载面 + Soft White symbol

## 形态纪律

- 保持原始横纵比例、线宽与圆角端点。
- 保持 `L`、双拱、开放 `o` 和光标切口的相对位置。
- App Icon 保持纯平面黑底白形，不添加渐变、纹理、浮雕或投影。
- 使用提供的深浅色与单色版本。
- 复杂背景上先建立系统 material 或纯色承载面。
- 小于 24 pt 时选用 Micro Mark。

## 菜单栏状态

| 状态 | 图形信号 | 可访问标签 |
| --- | --- | --- |
| idle | 安静 `L` 与开放 `o` | `Lerro，空闲` |
| listening | 完整 `L + rr + open o` | `Lerro，正在听写` |
| processing | 三个节奏点进入开放 `o` | `Lerro，正在处理` |
| error | `L` 基线与感叹落点 | `Lerro，需要处理` |

图像接入 `NSImage` 后设置 `isTemplate = true`，菜单标题与 VoiceOver 标签同步更新。
