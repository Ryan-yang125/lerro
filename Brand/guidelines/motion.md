# Motion

## 感受目标

Lerro 的动效传达即时、连续、可控。声线响应语音输入，随后收束到文字基线与光标，
让用户清楚理解“声音正在成为文字”。

## Motion tokens

| 用途 | 参数 | 行为 |
| --- | --- | --- |
| 主窗口 hover | `150 ms` ease-out | 只更新填充、边界、文字或阴影 |
| 主窗口 pointer-down | 向下 `1 pt`，response `0.20`，damping `1.0` | 当帧响应，释放后从当前值回到原位 |
| HUD 外壳形变 | mass `0.9`，stiffness `420`，damping `36` | 近临界阻尼，约 200 ms 平稳停靠 |
| 手势释放 | response `0.36`，damping `0.82` | 轻微动量，仅用于真实手势 |
| HUD 首帧反馈 | `≤120 ms` ease-out | 预热 panel 内即时显现 |
| 状态交叉淡化 | `100 ms` | waiting、listening、processing、error |
| Processing 显现 | `80 ms` strong ease-out | 快速转写和模型结果中仍有清晰首帧反馈 |

主窗口导航、卡片、pill CTA 与图标按钮共享 1 pt 按压位移和 `0.92` pressed opacity。
hover 保持 150 ms；稳定卡片不使用 hover scale。Reduce Motion 开启时取消按压位移，
透明度与静态填充继续表达状态。

## HUD 保护边界

下方序列、外壳 spring、声线采样、processing 节奏、状态切换、静音策略和无障碍降级
继续作为 HUD 验收基线。processing 三点使用系统强调色，其他 HUD 图形继续使用现有
黑白与系统状态色。

## HUD 序列

1. **Idle**：透明热区保留，视觉内容收起。
2. **Waiting**：hold 快捷键被接受的同一事件轮展示低幅、非周期声线。
3. **Hands-free**：toggle 快捷键直接展开最终外壳，X、静态低亮声线和完成按钮在同一次形变中出现；麦克风准备保持为内部状态。
4. **Listening**：麦克风就绪后沿用同一声线，真实音量脉冲在 90 ms 内驱动振幅，外壳保持稳定。
5. **Processing**：停止手势后一帧内收束为系统强调色三点流动指示；固定外壳内只有
   opacity 与 scale 变化，约 720 ms 完成一次从左到右的轻量循环，不延迟结果交付。
6. **Success**：Command-V commit 后 100 ms 内收起，以连续形变完成确认。
7. **Error**：声线停止，感叹光标与明确文字同步出现。

实时音量以约 21–23 Hz 进入 UI，声线每 50 ms 更新一次。十根柱分别保留自己的能量与
衰减状态；语音脉冲在中心区域游走，并以不同延迟、衰减和轻微变化扩散到相邻柱。安静环境
只保留无固定周期的微弱 room tone，停止说话后约 300 ms 回到基线。外壳在整个会话内保持
同一个 SwiftUI identity；控制按钮通过宽度、透明度与 scale 连续披露，声线在 waiting、
listening 和 hands-free 之间保持同一个 identity。状态切换从当前 presentation value 开始，
连续输入可随时改变目标。窗口只在离散状态变化时重新定位，波形高度只通过 scale 更新；
八分钟倒计时出现前，计时器只做每秒一次的轻量边界检查，不写入界面观察状态。

开始、完成和错误全程保持静音，HUD 视觉状态与 VoiceOver 公告承担反馈。
HUD 内既有按钮反馈保持不变。主窗口控件使用共享 Navigation、Card、Pill 与 Icon
ButtonStyle，通过 1 pt 位移和 opacity 提供即时按下反馈；Reduce Motion 开启时取消位移，
透明度反馈继续生效。主窗口 disabled opacity 为 `0.48`。

## 空间与材质

- 浮层从动作来源或当前输入区域出现，返回沿同一路径。
- passive HUD 保持非激活并维持原应用焦点。
- Ask 面板获得键盘焦点后提供清晰关闭路径。
- material 的 blur、opacity 与 scale 同步建立，层级变化保持连贯。

## Reduce Motion

读取 `accessibilityReduceMotion`。启用后：

- 位移、弹性与循环声线停用，状态以静态图形即时切换。
- waiting 使用静态低幅声线；实时音量使用离散的三档强度。
- processing 采用静态三点状态，中央点保持高亮。
- 完成与错误仍保留即时视觉反馈。

## Reduce Transparency 与 Increase Contrast

- Reduce Transparency 使用实色表面与 separator。
- Increase Contrast 使用更清晰边界、Label text 和图形状态差异。
- 大面积亮度切换保持平滑，避免突然闪烁。
