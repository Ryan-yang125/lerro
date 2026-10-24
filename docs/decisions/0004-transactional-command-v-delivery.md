# 0004：事务化 Command-V 文本交付

- 状态：accepted
- 日期：2026-07-31
- 决策人：Lerro maintainers
- 补充：[`0012`](0012-strict-delivery-ai-dictionary-learning.md) 定义写入前的 capture-bound 严格校验

## 背景

早期实现优先通过 Accessibility 设置 selected text，失败时再走剪贴板。Chromium textarea 等控件会为 AX set 返回 success，同时保持真实
DOM value 不变，系统调用状态因此不能证明文本已经到达目标编辑器。

## 决策

生产交付只有一个文本变更路径，行为与用户正常粘贴一致：

1. `AccessibilityTextDeliverer` 验证目标应用、secure input 和 AX 状态。
2. `PasteboardTransaction` 保存全部 item/type，复验 change count，写入文本、唯一 session marker 与 transient type。
3. 提交前再次检查任务取消、事件发布权限、目标身份和剪贴板所有权。
4. 带 Lerro source marker 的 Command-V keyDown/keyUp 连续发布到 HID event tap。两个事件发布完成是 commit point，随后同步调用
   `TextDeliveryCommitHandler`。
5. `inserting` 阶段在 commit 前保留取消入口；commit 后撤下取消入口，交付立即返回，session 回到 `idle`。约 500 ms 的消费等待和剪贴板恢复
   运行在 deliverer 持有的 detached task 中，调用方取消不会缩短临时剪贴板的寿命；下一次交付先等待该任务结束。历史写入在 `AppSession` 的后台串行队列中完成。
6. 恢复只执行一次；marker 或 change count 已变化时保留新的外部内容。

依赖方向为 `Lerro -> LerroMac -> LerroCore`：`TextDelivering` 在 Core 声明，`LerroMac` 产生提交事件，`AppSession` 持有产品状态。

## 备选方案

- AX selected-text 写入优先：虚假 success 会静默丢字。
- 针对各应用的专用 API：维护面随应用数量增长，无法覆盖未知编辑器。
- commit 后继续响应 Escape：事件已进入系统队列，取消无法撤回文本，并会留下剪贴板污染。

## 后果

- AX 虚假写入成功无法形成静默丢字；pre-commit 与 post-commit 取消边界可由 `AppSession` 测试证明。
- 临时剪贴板保持约 500 ms，其间的外部写入会取得所有权并使 Lerro 放弃恢复。
- 合成事件 API 不确认目标已消费文本，跨应用行为需要在目标应用中人工确认。

## 隐私与安全

交付文本只进入本机剪贴板和目标应用，日志不记录文本、剪贴板内容或 marker。

## 验证

`AccessibilityTextDelivererTests`（门禁、marker、多 item 恢复、外部所有权、并发事务、post-commit 非取消收尾）与
`AppSessionCoreFlowTests`（pre-commit 取消不提交，post-commit 取消被忽略并完成历史）。
