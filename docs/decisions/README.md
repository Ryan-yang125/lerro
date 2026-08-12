# Architecture Decision Records

ADR 用于记录会长期影响模块、数据、系统权限、模型、发布或 UI 基线的选择。它保存决策时的背景和权衡，代码继续作为当前行为的 source of truth。

## 当前记录

| ADR | 状态 | 决策 |
| --- | --- | --- |
| [0001](0001-vendored-hugging-face-download-stack.md) | accepted | Vendored Hugging Face 下载栈、进度补丁、临时文件消费与真实模型 smoke 边界 |
| [0002](0002-lerro-product-identity.md) | accepted | Lerro 产品、target、Bundle ID、数据与发布身份 |
| [0003](0003-explicit-hotkey-gesture-semantics.md) | accepted | 单修饰键录制、hold/toggle、active event tap 与 binding-bound release |
| [0004](0004-transactional-command-v-delivery.md) | accepted | AX 安全验证、事务化 Command-V 文本交付与显式 commit 边界 |
| [0005](0005-current-focus-command-v-insertion.md) | superseded | 普通插入 current-focus 方案；由 0012 的 capture-bound 严格写入取代 |
| [0006](0006-byok-openai-compatible-providers.md) | accepted | BYOK Provider 路由、OpenAI-compatible runtime、JSON API Key 与远程上下文边界 |
| [0007](0007-cloudflare-distribution-and-sparkle-updates.md) | accepted | Cloudflare Worker/R2/D1 公开分发与 Sparkle 应用内更新 |
| [0008](0008-accessibility-owned-fn-shortcuts.md) | accepted | 两项系统权限、HID Fn 物理所有权与空闲 HUD 隐藏 |
| [0009](0009-bound-delivery-receipts.md) | superseded | 写入后回执、撤回、即时修正与发送；由 0012 的成功即结束方案取代 |
| [0010](0010-quick-dictate-and-spoken-delivery-edits.md) | superseded | 语音跟进编辑与版本链由 0012 移除；可选 SpeechDetector 收敛为默认关闭的 Quick Dictate |
| [0011](0011-device-aware-ai-onboarding-and-resumable-model-downloads.md) | accepted | 设备感知 AI 分流、Onboarding 内配置、后台可恢复模型下载与 Quick Dictate 降级 |
| [0012](0012-strict-delivery-ai-dictionary-learning.md) | accepted | 居中实时预览、capture-bound 严格写入、失败恢复、AI 自动词典与操作型 Onboarding |

## 需要 ADR 的变化

- 新增、删除或重组生产 target。
- 改变 `LerroCore`、`LerroMac`、`LerroIntelligence`、`Lerro` 的依赖方向。
- JSON repository 迁移到 SQLite、GRDB、SwiftData 或云同步。
- 替换 Apple Speech、MLX runtime 或默认模型。
- 新增外部推理、账号、同步、analytics 或其他网络服务。
- 新增或移除 TCC 权限、entitlement、App Sandbox、Hardened Runtime 例外。
- 改变签名、公证、更新、版本或产物策略。
- 拆分 AppSession 的状态所有权。
- 改变原始音频、历史、模型授权或安全输入框边界。
- 改变 Apple-native 视觉系统、品牌资产格式或视觉回归方法。

局部 bug 修复、无语义重构和单页视觉调整通常不需要 ADR；它们仍需更新对应专题文档和测试。

## 命名

```text
docs/decisions/NNNN-short-kebab-title.md
```

示例：

```text
0001-package-first-swiftpm-app.md
0002-local-speech-and-mlx-boundary.md
```

编号只递增。已接受 ADR 不复写历史；方向变化时新增 ADR，并在新记录中标记被替代项。

## 状态

- `proposed`：正在讨论，禁止当成当前实现。
- `accepted`：已决定并与代码同步。
- `superseded`：被后续 ADR 替代。
- `rejected`：评估后未采用，保留原因。

## 模板

```markdown
# NNNN：标题

- 状态：proposed
- 日期：YYYY-MM-DD
- 决策人：
- 关联任务/PR：
- 替代：无

## 背景

描述当前问题、用户目标、系统限制和可验证证据。链接相关源码、官方文档、测试和产物。

## 决策驱动因素

- 隐私与安全边界
- macOS 版本与 API 可用性
- 本地性能、内存、磁盘和启动时间
- 可测试性与失败恢复
- 发布、签名和公证
- UI、品牌与可访问性影响

## 方案

描述选择的模块、数据流、接口、迁移和失败策略。

## 备选方案

逐项记录其他可行方案、收益、成本和未采用原因。

## 后果

### 收益

-

### 成本与风险

-

## 隐私与安全

列出数据、网络、权限、日志、凭据、安全输入框和删除边界的变化。

## 迁移与兼容

列出数据迁移、偏好 Codable、版本门槛、回滚和旧产物兼容。

## 验证

列出 focused tests、全量测试、Release bundle、`verify_release.sh`、实机矩阵和性能证据。

## 文档同步

列出需要更新的 architecture、core-flow、testing、release、privacy-security、
Brand Kit 和 troubleshooting。
```

## ADR 完成门禁

- 背景引用当前 source of truth。
- 数据流和依赖方向清晰。
- 失败、取消、迁移与回滚可执行。
- 隐私、权限、网络和日志影响明确。
- 测试与真实 Release 验收方案明确。
- `accepted` 状态对应实现、测试和专题文档已经落地。
