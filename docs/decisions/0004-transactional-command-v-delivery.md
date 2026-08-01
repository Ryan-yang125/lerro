# 0004：事务化 Command-V 文本交付

- 状态：accepted
- 日期：2026-07-31
- 决策人：Lerro maintainers
- 关联任务/PR：本地 Phase 5 核心链路完善
- 替代：旧 Accessibility selected-text 写入优先策略

## 背景

Lerro 需要把 Speech 与本地处理生成的最终文本写入用户当前输入光标。原实现优先设置
Accessibility selected-text，再以剪贴板和 Command-V 处理失败场景。实机 Chromium
textarea 验收发现，部分控件会为 AX set 返回 success，同时保持真实 DOM value 不变。
系统调用状态因此无法证明文本已经到达目标编辑器。

用户明确要求通用的“写入剪贴板并执行粘贴”链路。原生 NSTextView 与 Chromium
textarea 的 Release 探针也验证了 Command-V 路径可以覆盖两类目标，并允许完整恢复原剪贴板。

## 决策驱动因素

- 目标应用按正常粘贴命令消费文本，覆盖原生与第三方编辑器。
- Accessibility 继续提供 secure field、焦点、应用身份和选区安全验证。
- 普通听写遇到选区时折叠到尾部 caret，并通过 AX 回读证明范围已经生效。
- 所有剪贴板 item、type、顺序和字节在本 session 持有 marker 时精确恢复。
- Escape 在事件提交前保持有效；事件提交后的事务完整收尾。
- AppSession、系统 adapter、HUD 与自动化共享同一个 commit 定义。

## 方案

生产交付只使用一个文本变更路径：

1. `AccessibilityTextDeliverer` 验证捕获上下文、目标 PID/bundle、前台应用、Secure
   Event Input、AX focused element 与选区状态。
2. 普通插入发现非空选区时，把 selected range 折叠到尾部并立即精确回读。回读缺失或
   范围不一致时停止交付，最终文本保存在失败历史。
3. `PasteboardTransaction` 在同步 MainActor 步骤中保存全部 item/type，复验 change
   count，再写入文本、唯一 session marker 与 transient type。
4. 提交前再次检查任务取消、事件发布权限、目标前台身份、secure 状态、focused
   element 身份、选区和剪贴板所有权。
5. 带 Lerro source marker 的 Command-V keyDown/keyUp 连续发布到 HID event tap。两个
   事件发布完成构成 commit point，随后同步调用 `TextDeliveryCommitHandler`。
6. AppSession 在 `inserting` 的 pre-commit 区间保留取消入口。commit handler 绑定当前
   CaptureSession ID；匹配后撤下取消入口，并让交付任务完成消费等待、剪贴板恢复、历史
   写入和 UI 收尾。
7. post-commit 消费等待运行在 detached task 中，调用方取消不会缩短临时剪贴板寿命。
   恢复只执行一次；marker 或 change count 已变化时保留新的外部剪贴板内容。

依赖方向保持 `Lerro -> LerroMac -> LerroCore`。`TextDelivering` 在 Core 声明 commit
handler，LerroMac 产生提交事件，AppSession 持有产品状态。

## 备选方案

### Accessibility selected-text 写入优先

原生控件速度快，Chromium 等第三方控件可能产生虚假 success。添加延迟回读仍存在目标
晚到写入与 Command-V 重复提交风险，因此退出生产文本变更路径。

### 直接调用目标应用专用 API

每类应用需要独立适配和权限，维护面会随应用数量增长，也无法覆盖未知编辑器。

### Command-V 提交后继续响应 Escape

事件已经进入系统队列，撤销任务无法可靠撤回文本。此时终止恢复或历史写入会留下剪贴板
污染和交付记录缺口，因此 commit 后采用完整收尾语义。

## 后果

### 收益

- 文本交付行为与目标应用正常粘贴一致。
- AX 虚假写入成功无法形成静默丢字。
- pre-commit 与 post-commit 取消边界可由 AppSession 自动化证明。
- 剪贴板所有权、恢复与外部更新冲突保持确定。

### 成本与风险

- 交付依赖 Accessibility 的事件发布权限与目标应用对 Command-V 的正常处理。
- 临时剪贴板需要保持约 500 ms，期间外部写入会取得所有权并使 Lerro 放弃恢复。
- 第三方控件若拒绝选区范围回读，普通听写会安全停止并要求用户从历史重试。
- 合成事件发布 API 没有目标应用消费确认，真实 Release 跨应用矩阵继续作为发布门禁。

## 隐私与安全

交付文本只进入本机通用剪贴板和目标应用。Lerro 不记录文本内容、选区、剪贴板内容或
marker。Secure Event Input、secure role/subrole、目标身份和选区在提交前重复检查。
事务仅在唯一 marker、change count、transient type 和文本仍属于当前 session 时恢复；
其他应用取得所有权后保留其新内容。

## 迁移与兼容

该决策不改变 Bundle ID、数据格式、历史 schema 或模型缓存。旧版本与新版本共用设置和
历史。回滚会恢复旧交付策略，因此 Release 回滚验收需要重新覆盖 Chromium 文本框。

## 验证

- `AccessibilityTextDelivererTests`：secure/focus/selection 门禁、精确选区折叠回读、
  marker、multi-item/type 恢复、外部所有权、并发事务和 post-commit 非取消收尾。
- `AppSessionCoreFlowTests`：pre-commit 取消不提交、不写 completed history；post-commit
  取消被忽略并完成历史落盘。
- 全量 `swift test`、`git diff --check` 与 `script/verify_release.sh`。
- development-signed Release 在原生 NSTextView 与 Chromium textarea 执行固定 token
  插入；验证目标值、`delivery-complete stage=paste` 与剪贴板前后摘要一致。

## 文档同步

- `AGENTS.md`
- `README.md`
- `PRIVACY.md`
- `SECURITY.md`
- `docs/core-flow.md`
- `docs/engineering.md`
- `docs/privacy-security.md`
- `docs/testing.md`
- `docs/troubleshooting.md`
