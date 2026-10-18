# Motion

## 感受目标

Lerro 的动效传达即时、连续、可控。光标闪烁表示等待输入，基线画出表示正在处理，
动效时长和节奏在所有界面保持一致。

## Motion tokens

| 用途 | 参数 | 行为 |
| --- | --- | --- |
| 主窗口 hover | `150 ms` ease-out | 更新填充、边界、文字或阴影 |
| 主窗口 pointer-down | 向下 `1 pt`，response `0.20`，damping `1.0` | 当帧响应，释放后从当前值回到原位 |
| HUD 外壳形变 | mass `0.9`，stiffness `420`，damping `36` | 近临界阻尼，约 200 ms 平稳停靠 |
| 手势释放 | response `0.36`，damping `0.82` | 轻微动量，用于真实手势 |
| HUD 首帧反馈 | `≤120 ms` ease-out | 预热 panel 内即时显现 |
| 状态交叉淡化 | `100 ms` | waiting、listening、processing、error |
| 光标闪烁 | `1.05 s` 周期，step | 前半周期完整，后半周期透明度 `0.25` |
| 基线画出 | `1.2 s` ease-in-out | 从左端缩放 `0.15` 到 `1.0` |
| 菜单栏 listening 帧 | `0.525 s` 每帧 | `Listening` 与 `ListeningDim` 交替，周期 1.05 s |
| 菜单栏 processing 帧 | `0.15 s` 每帧 | `Processing1`–`Processing4` 循环，周期 0.6 s |

主窗口导航、卡片、pill CTA 与图标按钮共享 1 pt 按压位移和 `0.92` pressed opacity。
hover 保持 150 ms；稳定卡片不使用 hover scale。主窗口 disabled opacity 为 `0.48`。

## 标志动效

- 光标闪烁使用 step 曲线，没有淡入淡出过渡。
- 基线画出从左端向右生长，光标保持降低透明度。
- Onboarding 首屏标志的光标闪烁一次后停住。
- 菜单栏动画只在 listening 和 processing 播放，idle 与 error 保持静态。
- 动效不用于传达成功或失败，状态由形状、文字和系统状态色承担。

## 菜单栏帧

| 状态 | 帧序列 |
| --- | --- |
| idle | `Idle` |
| listening | `Listening` → `ListeningDim` → 重复，每帧 0.525 s |
| processing | `Processing1` → `Processing2` → `Processing3` → `Processing4` → 重复，每帧 0.15 s |
| error | `Error`，光标变成「!」 |

## HUD

HUD 的形状、状态和文案由
[ADR 0013](../../docs/decisions/0013-brand-capsule-hud.md) 定义。动效要点：

- 所有状态在同一个 40 pt 高的胶囊内完成，宽度以 spring 变化，最大 480 pt。
- 录音态显示墨水蓝光标与 9 根音量波形；实时文字单行显示，旧文字从左侧淡出，光标跟随
  文字末尾。
- 处理中写「AI 润色中…」或「翻译中…」。
- Command-V commit point 之后 HUD 立即淡出。
- AI 失败退回原文时显示橙色圆点和「已写入原文 · AI 未响应」，持续 2 秒。
- 开始、完成和错误全程保持静音，HUD 视觉状态与 VoiceOver 公告承担反馈。
- 外壳在整个会话内保持同一个 SwiftUI identity；状态切换从当前 presentation value
  开始，连续输入可随时改变目标。

## 空间与材质

- 浮层从动作来源或当前输入区域出现，返回沿同一路径。
- passive HUD 保持非激活并维持原应用焦点。
- Ask 面板获得键盘焦点后提供清晰关闭路径。
- material 的 blur、opacity 与 scale 同步建立，层级变化保持连贯。

## Reduce Motion

读取 `accessibilityReduceMotion`。启用后：

- 位移、弹性与循环动画停用，状态以静态图形即时切换。
- 主窗口控件取消按压位移，透明度反馈继续生效。
- 光标闪烁停用，光标保持完整显示；Onboarding 首屏标志直接显示静态标志。
- 基线画出停用，基线保持完整显示。
- 菜单栏停止帧循环：listening 固定显示 `Listening`，processing 固定显示
  `Processing4`，idle 与 error 不变。四种状态的静态形状互不相同。
- HUD 实时音量使用离散的三档强度。
- 完成与错误仍保留即时视觉反馈。

## Reduce Transparency 与 Increase Contrast

- Reduce Transparency 下 HUD 使用不透明墨黑，主窗口使用实色表面与 separator。
- Increase Contrast 下 HUD 增加纸白描边，主窗口使用更清晰的边界与文字值。
- 大面积亮度切换保持平滑，避免突然闪烁。
