# 性能规范

本文件记录 Lerro 的性能预算、写代码时要遵守的规则和测量方法。规则来自 2026-10 的整体性能审查，每条都对应一次实测问题。
架构决策见 [ADR 0017](decisions/0017-fixed-sidebar.md)（主窗口布局与页面常驻）和
[ADR 0018](decisions/0018-sqlite-history-store.md)（历史存储）。

## 预算

| 指标 | 预算 | 测量 |
| --- | --- | --- |
| 主窗口切页（988×690，`LERRO_FIXTURE_SCALE=large`） | 每页中位数 ≤ 70 ms | `./script/measure_ui_performance.sh` |
| 隐藏页面的键盘焦点 | Tab 和切页都不能让焦点落在隐藏页面的控件上 | 同上，`focus` 结果为 `pass` |
| 按键到可以说话（`readyToSpeak`） | 中位数不高于改动前 | `python3 script/capture_latency_report.py` |
| 按键到麦克风开始收音（`microphoneLive`） | 中位数不高于改动前 | `capture_latency_report.py --prearm yes` 与 `--prearm no` 对比 |
| commit point 到回到空闲 | 中间没有固定等待和存储 I/O | 历史记录里 `deliveryCommitted` 到 `finished` |
| 保存一条历史 | 只写一行，与历史总量无关 | `SQLiteHistoryRepositoryTests` |

2026-10-24 用 `measure_ui_performance.sh` 测得的基线（3 轮中位数）：首页 33 ms，历史 29 ms，词典 51 ms，应用语气 54 ms。
改动后超出预算时，在改动说明里写明原因和实测数字。

## 主窗口布局

- 页面级的分栏和上下结构用 `LerroSplitLayout`；等宽卡片行用 `LerroEqualColumns`。
  `HStack`/`VStack` 分配空间时会用 0 和无穷大两种尺寸探测每个子视图，子视图是 `ScrollView` 时整页内容会被多排版几遍，
  曾让每次切页多花 60–80 ms。
- 卡片行不要用 `.fixedSize(horizontal: false, vertical: true)` 取齐高度，它同样触发重复测量。
- `Text` 的本地化走二进制 plist（构建脚本负责转换）。SwiftUI 每次查找都会重新读字符串表，文本格式每次 0.5–0.8 ms。

## 页面常驻

四个页面启动时全部创建，切页只改可见性。新增页面内容时：

- 不要在页面根部放随可见性变化的环境值，也不要用 `.disabled` 控制整页。两者变化时 SwiftUI 会重新检查两个页面里的每个文本视图，
  每次切页多 10–20 ms。
- 新的可聚焦控件要接上焦点限制：文本输入框用 `lerroPageTextInput`，列表用 `lerroPageFocusable`。
  `TextEditor` 隐藏时仍然在 Tab 顺序里，只在页面可见时创建它，草稿状态放在外层视图。
- 原来写在 `.task`/`.onAppear` 里、每次进入页面都要做的事，改用 `onLerroPageVisibilityChange`。
  页面隐藏时要停下的东西（播放、预览请求）也放在这里。
- 页面在偏好和数据加载完成前就已创建。用数据初始化的 `@State` 要跟随数据变化（例如应用语气编辑框在草稿未改动时跟随已保存的值）。
- 这些修饰器在自己的 body 里读取 `session.destination`，切页时只更新被限制的控件。不要在页面 body 里直接读 `destination`。

## 状态更新

- `AppSession` 里的高频属性（`audioLevel`、`partialTranscript` 等）只给 HUD 读。主窗口和菜单栏面板不读这些属性。
- 从仓库刷新到 `@Observable` 属性时，值没变就不赋值，免得让订阅的视图重新计算。
- body 里不做 JSON 解析、文本对比、分组这类计算；需要时在加载数据时算好。

## 采集与交付链路

- Command-V 发出是 commit point。commit 之后不能再有任何等待挡在回到 `idle` 之前：剪贴板恢复在 deliverer 的后台任务里完成，
  历史、用量和词典的持久化走 `AppSession` 的后台串行队列。
- 启动链和结束链上新增的步骤要加 `CaptureMilestone`，并同步 `CaptureMilestone` 的链定义和
  `script/capture_latency_report.py`。没有里程碑的步骤以后测不出来。
- 麦克风要尽早打开，音频先缓冲在内存里，等 `SpeechTranscriber` 准备好再送入。不要把语音模型准备放在开麦之前。
  单修饰键快捷键在按下时预开麦克风，判定为组合键时丢弃音频（[ADR 0019](decisions/0019-microphone-prearm-at-modifier-key-down.md)）。

## 存储

- 不整份重写文件。历史一条一行（SQLite），查询用索引和 FTS5。
- 页面和统计用分页、计数、按条件查询的仓库接口；`entries()` 只用于一次性的全量工作（每日用量补建）。
- 存储操作不在主线程上做。

## 测量方法

### 主窗口切页与焦点

```zsh
./script/build_and_run.sh --no-launch         # release 构建；debug 构建的数字不能和预算比较
./script/measure_ui_performance.sh            # dist/Lerro.app，跑 3 轮
```

- 计时从设置 `session.destination` 开始，到主线程 run loop 下一次 `beforeWaiting`（Core Animation 提交之后）结束，
  同时记录主线程 CPU 时间。两者接近说明时间都花在主线程计算上。
- 焦点检查在每页用进程内合成的 Tab 键走 8 次，焦点落到透明度为 0 的控件上记为 `tab_hidden_hits`；
  再在焦点停在本页控件时切页，切页后焦点还在原控件上记为 `switch_kept_focus`。任一项大于 0 时结果为 `fail`。
- 脚本先打印系统负载。负载高时数字会偏大，和改动前的版本在同一时段交替跑再比较。
- 对比两个版本时，各构建一份 app，交替运行各 3 轮，取中位数的中位数。单次结果的波动可以超过 30%。
- fixture 和正式版共用 bundle id，AppKit 会把窗口位置写进用户的 defaults；脚本会恢复原值。手动跑 fixture 时也要注意这一点。

### 找原因

- 用 Time Profiler 附加到已经运行的进程：`xcrun xctrace record --template 'Time Profiler' --attach <pid>`。
  用 `--launch` 启动时采样不完整，结果和实际不符。
- 导出 `time-profile` 表（`xcrun xctrace export --xpath …`）后只看主线程，按调用栈里的 `Lerro` 帧和 SwiftUI 布局帧聚合。
- 常见信号：`StackLayout` 下大量 `sizeThatFits` 说明有探测排版；`PropertyList.Tracker.hasDifferentUsedValues` 和
  `ResolvedTextFilter.updateValue` 占比高，说明环境值变化让大量文本重新检查；`NSHostingView.layout` 下的
  `NSTableView` 行高计算说明列表被重建。

### 真实链路

- `python3 script/capture_latency_report.py` 只读打开历史数据库，汇总每次听写的里程碑耗时。
- 改动采集或交付链路后，用新版本正常听写一段时间，再和改动前同一报告的中位数、p90 对比。
