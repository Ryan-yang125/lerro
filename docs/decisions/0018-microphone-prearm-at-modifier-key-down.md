# 0018：单修饰键按下即预开麦克风

- 状态：accepted
- 日期：2026-10-24
- 决策人：Lerro maintainers
- 补充：[`0003`](0003-explicit-hotkey-gesture-semantics.md)（手势语义）

## 背景

单修饰键 toggle（例如只按 ⌘）在松开时才确认，因为按住期间按下其他键就是系统组合键。确认之后 `AppleSpeechService.start`
还要启动 `AVAudioEngine`。维护者 722 次真实 capture 的 `phaseTimings`：按住时长 p50 118 ms（p90 141 ms），
`engine.start()` p50 92 ms（p90 108 ms），麦克风开始收音在按下后 p50 229 ms，即松开后 113 ms（p90 137 ms）。
这段时间 HUD 已经出现，用户此时开口的音频会丢失。hold 模式的 120 ms 意图确认也在麦克风打开之前。

## 决策

- `HotkeyGesturePhase` 增加 `armed` 与 `disarmed`。`GlobalHotkeyMonitor` 在 Dictate / Translate 的单修饰键候选成立时发
  `armed`，候选在没有发出 `began` 的情况下结束时发 `disarmed`：按下其他键、加入其他修饰键、Escape、physical drain、
  Secure Input、monitor 停止、hold 在激活前松开。
- toggle 候选按住超过 1 秒（`modifierTapTimeout`）作废，到时发 `disarmed`，随后的松开不再开始听写。
- 按住期间点击鼠标（左、右、其他键）视为组合键：松开或 hold 激活时，用 `CGEventSource.secondsSinceLastEventType`
  检查按住期间有没有点击。滚轮不计入，滚动后的惯性事件会在用户按下快捷键之后继续到达。
- `AppSession` 在可以开始 capture 的状态（空闲类 phase、没有活动或清理中的 capture、不在录制快捷键、存储就绪、
  麦克风与辅助功能权限已缓存为已授权）收到 `armed` 时调用 `SpeechTranscribing.prearmMicrophone`，收到 `disarmed`
  或 `began` 没有进入 `speech.start` 时调用 `discardPrearmedMicrophone`。两者通过一条串行 Task 链发出，`beginCapture`
  在 `speech.start` 前等待这条链。预开麦不改变 HUD、phase、提示音、trace 和输出音频。
- `AppleSpeechService` 预开麦时启动引擎，输入 tap 写入 `CapturedAudioRelay`，音频只留在内存（最多 64 个缓冲）。
  同一设备的下一次 `start` 接管它：上报预开麦时记录的引擎里程碑和 `microphonePrearmed`，把缓存音频按顺序作为本次
  capture 的开头（开启录音保存时也写入文件），再转为实时转发。`cancel` 同样丢弃预开麦；2 秒内没有被接管时自动丢弃。
- 输入设备的 transport 是 Bluetooth 或 Bluetooth LE 时不预开麦，保持松开后再开麦。

## 备选方案

- 第一次按下后让麦克风保持开启数秒：指示灯常亮，蓝牙耳机持续处在通话音质，首次按下的延迟没有改善。
- 按下即正式开始 capture：每个 ⌘ 组合键都会闪 HUD、响提示音。
- 在按住期间只做权限检查和上下文读取：`hotkeyHandled → speechStartRequested` p50 只有 17 ms（p90 43 ms）。

## 后果

- 每个 ⌘ 组合键都会短暂打开麦克风：菜单栏橙点闪一下，控制中心显示 Lerro 最近使用过麦克风，麦克风监控工具会提示。
  每次打开最长 1 秒，组合键通常在按下其他键时立即关闭。
- 开始提示音在松开时播放，此时麦克风已在收音；使用扬声器时提示音可能进入录音。
- 预开麦的 capture 中 `audioEngineStarted` 等里程碑早于 `hotkeyHandled`；新增区段 `microphoneLive`
  （`hotkeyPressed → audioEngineStarted`）对新旧记录都可计算，用于前后对比。

## 隐私与安全

预开麦的音频只在内存中，作废时直接丢弃，不写盘、不进入 Speech、不进入历史。Secure Input 期间 monitor 不产生候选。
不会因为按键请求权限。日志不记录按键序列。

## 验证

`GlobalHotkeyMonitorTests` 覆盖 armed/disarmed 序列、组合键、修饰键升级、超时、鼠标点击、hold、Escape、reset 与自产粘贴事件；
`AppSessionCoreFlowTests` 覆盖预开麦的允许条件、作废、接管顺序与被拒绝的 began；`CapturedAudioRelayTests` 覆盖缓存顺序、
上限、丢弃与拷贝。麦克风、蓝牙设备与真实延迟只能在签名构建上用 `script/capture_latency_report.py --prearm yes|no` 验证。
