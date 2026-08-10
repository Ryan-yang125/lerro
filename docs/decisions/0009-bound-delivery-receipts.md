# 0009：写入后动作绑定一次性交付回执

- 状态：accepted
- 日期：2026-08-10
- 决策人：Lerro maintainers
- 关联任务/PR：Lerro v1.4
- 替代：无

## 背景

ADR 0005 让普通插入遵循提交瞬间的当前键盘焦点，保持对 Electron、Chromium 与自绘
编辑器的兼容。v1.4 增加写入后撤回、即时修正与免手发送。这些动作会在 Command-V 之后
再次影响目标应用，需要比捕获上下文更精确地绑定实际交付目标，并在用户继续编辑或切换
输入框时失效。

## 决策驱动因素

- 保持 ADR 0005 的 current-focus 普通写入语义。
- 写入后动作只能影响刚刚提交的目标与内容。
- secure、unknown、Terminal、search 与 address 目标保持 fail closed。
- 回执不持久化 focused text 或完整输入值。
- 可通过 Core 协议、Mac adapter、AppSession 和 inert fixture 分层测试。

## 方案

1. `TextDelivering.deliver` 在 500ms 剪贴板消费窗口结束后返回
   `TextDeliveryReceipt`。
2. receipt 使用实际 post-delivery focus，记录 PID、bundle、role/subrole、focused
   element fingerprint 与完整 AX value fingerprint。fingerprint 只存在于当前进程内。
3. `undo`、`correct` 与 `submit` 重新激活并确认同一 app，随后验证 secure state、focused
   element 和完整值。任一不匹配都会停止动作。
4. Undo 提交带 Lerro source marker 的 Command-Z；submit 提交带同一 marker 的 Return；
   correct 在同一个 adapter 事务与 MainActor turn 连续提交 Command-Z 和 Command-V。
5. AppSession 在六秒内持有 receipt。开始新 capture 或计时结束会销毁它。
6. 即时修正使用 receipt 的原子 `correct` 契约写入修正文；history 保存 raw、processed
   与 corrected 沿袭。
7. 免按住 Dictate 只解析末尾“发送”或“send it”。每个 app 第一次提交前确认，成功后
   才把 app name 和 bundle 写入偏好。

## 备选方案

- 仅按时间窗口发送 Command-Z：无法排除窗口内的用户编辑。
- 捕获时绑定目标：普通插入可能在处理期间随用户焦点变化，无法代表实际提交目标。
- 全局监听鼠标和键盘以推断编辑：扩大 event tap 范围并增加状态复杂度。
- 持久化完整 focused value：增加不必要的敏感文本存储。

## 后果

### 收益

- 普通插入保持广泛兼容，写入后动作拥有独立、严格、可验证的安全门禁。
- 用户编辑、切换输入框、撤销权限或进入安全输入后，旧回执立即失效。
- correction learning 获得可审计的 raw/processed/corrected 沿袭。

### 成本与风险

- AX value 或 focused element 不可读的控件仍可完成普通写入，回执 Undo、修正与发送会停用。
- Return 的提交语义由用户批准的目标 app 决定，需要真实应用矩阵验收。
- fingerprint 只在同一进程生命周期有效，应用重启后不会恢复回执。

## 隐私与安全

不新增权限、entitlement 或网络路径。receipt 不记录 transcript、focused value、选区或
prompt；history 只新增上下文类别、remote 共享类别、处理路径、阶段耗时与发送状态。
语音发送 app allowlist 位于权限为 `0600` 的 `preferences.json`，用户可在个性化设置删除。

## 迁移与兼容

v1.4 直接采用返回 receipt 的 `TextDelivering` 协议并移除旧 void contract。新增 history
字段为可选；新增偏好缺失时使用空 voice-send allowlist。旧 Release 产物继续由各自签名与
appcast 元数据独立验证。

## 验证

- `VoiceFinishActionResolverTests` 覆盖中英文解析与安全目标。
- `AccessibilityTextDelivererTests` 覆盖 receipt target、element 与 value 校验。
- `AppSessionCoreFlowTests` 覆盖实时 partial/final、首次确认、app 授权、submit、Undo 与历史。
- T3 覆盖 live HUD、delivery receipt、send confirmation 的双语与辅助功能 fixture。
- T4 使用无害本地目标覆盖 Undo、编辑后失效、即时修正与首次/再次发送。

## 文档同步

- `README.md` / `README.zh-CN.md`
- `PRIVACY.md`
- `docs/core-flow.md`
- `docs/privacy-security.md`
- `docs/testing.md`
- `docs/releases/v1.4.0.md`
