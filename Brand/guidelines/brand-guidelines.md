# Lerro Brand Guidelines

## 品牌核心

- 名称：Lerro
- 发音：`LEH-ro`
- 品类：本地优先的 macOS 语音写作工具
- 承诺：自然表达进入麦克风，清晰文字落到当前光标
- 主标语：`自在说，清楚写。`
- 英文标语：`Speak freely. Write clearly.`
- Campaign：`Let your voice become a sentence.`

## 品牌人格

Lerro 的表达保持温和、精确、安静、自信。产品让用户始终了解当前状态、数据位置
和下一步动作。Apple 原生感来自熟悉的控件、系统语义、空间一致性与细节质量。

## 核心隐喻

标志以 Lerro 自身字母承担功能含义。左侧高竖笔形成 `L` 与输入起点，中部两个圆拱
压缩为双 `rr` 的声音节奏，末端 `o` 保留向右开放的光标切口，表示语音已经落入
可编辑文字。

```text
L → rr rhythm → open o
                  └── cursor cut
```

## 视觉语言

1. **中性内容层**：主窗口的画布、侧边栏、卡片、文字、普通图标、边界与选择背景
   使用 `LerroTheme` 黑白灰 token，并为 Aqua、Dark Aqua 和 Increase Contrast 提供
   对应值。
2. **黑白固定品牌**：App Icon 与 Logo 使用 Ink Black / Soft White，形成稳定签名。
3. **系统强调色交互层**：主要行动、焦点边界和 processing 三点继承 macOS
   `controlAccentColor`；成功、警告和错误使用 system status colors，并同时提供图标
   或文字。
4. **Graphite 承载工具感**：菜单栏、次级图标、结构线和普通交互状态采用单色层级。
5. **内容主导布局**：留白建立层级，卡片只用于独立任务或明确分组。
6. **稳定表面表达层级**：侧边栏、卡片和浮层依靠灰阶、细边界与克制阴影分层；
   正文画布保持稳定和清晰。
7. **原生排版**：SF Pro、苹方与 SF Mono 使用 24 / 14 / 13 / 12 pt 四级字号，
   tracking 统一为 `-0.15`。

## 产品 UI tokens

| 角色 | Token | 规范 |
| --- | --- | --- |
| 主文字 | `text` | 浅色 `#292929` |
| 次级文字 | `secondaryText` | 浅色 `#5D5D5D` |
| 低强调文字 | `tertiaryText` | 浅色 `#9E9E9E`，只承载非必要信息 |
| 必要小字 | `metadataText` | 浅色 `#6B6B6B`，满足小字对比要求 |
| 字号 | title / body / label / caption | 24 / 14 / 13 / 12 pt |
| 导航 | icon / radius | 14 / 8 pt |
| 卡片 | icon / radius | 20 / 16 pt |
| 主要 CTA | shape | pill / capsule |
| 强调交互 | color | macOS `controlAccentColor` |
| hover | duration | 150 ms ease-out |
| pointer-down | displacement | 向下 1 pt |

## 构图

- 主窗口使用平台导航结构、工具栏和列表层级。
- 页面标题与正文沿同一基线网格对齐。
- 8 pt 基础节奏覆盖间距，4 pt 用于紧密图标与标签。
- 交互控件保持至少 28 × 28 pt 的点击区域，主要动作优先 32–36 pt 高度。
- 导航项使用 14 pt 图标与 8 pt 连续圆角；卡片使用 20 pt 图标与 16 pt 连续圆角。
- 主要 CTA 使用 pill，普通导航与卡片保持稳定轮廓。
- 浮层从触发点或当前工作区域出现，进入与退出沿同一路径。

## 应用范围

- App Icon：Ink Black 平面底承载 Soft White `L + rr + open o`，不使用渐变与投影。
- 菜单栏：模板图标由系统着色，四态使用不同轮廓。
- HUD：继续使用既有紧凑黑色表面、白色声线、error 与完成反馈；processing 三点使用
  系统强调色，主窗口视觉 token 不参与 HUD 状态机和外壳动画。
- Ask：原生浮动面板承载问题、答案、复制与写回动作。
- 仓库与发布：大留白、系统字体、黑白品牌签名、单色行动点和真实产品截图。
