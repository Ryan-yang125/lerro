# 0006：BYOK OpenAI-compatible Provider 与 JSON 凭据

- 状态：accepted
- 日期：2026-08-01
- 决策人：Lerro maintainer
- 关联任务/PR：本地工作区 BYOK 集成
- 替代：无

## 背景

Lerro 已经具备 Apple Speech 转写、本地 MLX 整理、Ask、Translate、Rewrite、
Command-V 交付和本地 JSON 偏好存储。默认 Qwen 模型约 3.03 GB，部分机器上的加载、
内存和生成成本较高。用户希望继续保留本地模型，同时使用自己的 DeepSeek、OpenAI、
Gemini 或其他 OpenAI-compatible API 完成低延迟文本整理。

本轮 DeepSeek V4 Flash 评测已经冻结 Dictate 的四层 payload、80/40 光标上下文、
匹配词典、用户语气和七个合成 few-shot。产品实现需要把这条能力接入当前 session、
取消、历史和文本交付状态机。

## 决策驱动因素

- 保持快捷键、HUD、Apple Speech 和 Command-V 黄金链路稳定。
- 让用户在设置中直接填写 API Key 并立即启用。
- 保留基础听写和本地 MLX 两条离线路径。
- 使用一个原生 Swift 网络实现覆盖多个兼容 Provider。
- 配置文件透明、可审查、可备份并支持确定性迁移。
- 明确明文凭据、上下文发送和第三方数据处理边界。

## 方案

### Provider 路由

应用提供三种智能处理模式：

1. `raw`：Apple Speech 原始转写直接进入现有文本交付。
2. `local`：原始转写进入本地 MLX runtime。
3. `remote`：原始转写与用户允许的上下文进入 OpenAI-compatible runtime。

一次 capture 在开始时冻结模式、endpoint、model、API Key 和上下文授权。设置变化从
下一次 capture 生效。Dictate 的云端错误回退到原始转写；Translate、Ask 和 Rewrite
保留明确、可重试的错误状态。

### Provider 预设

- DeepSeek：`https://api.deepseek.com`，默认 `deepseek-v4-flash`。
- OpenAI：`https://api.openai.com/v1`，Model ID 可编辑。
- Gemini：`https://generativelanguage.googleapis.com/v1beta/openai`，Model ID 可编辑。
- Custom：Base URL 与 Model ID 均可编辑。

公共请求使用 Chat Completions 结构。DeepSeek V4 Flash 使用非思考模式和
`temperature: 0`。连接测试只发送固定合成内容。

### JSON 配置与 API Key

Provider、Base URL、Model ID、API Key、当前模式和上下文开关统一保存在：

```text
~/Library/Application Support/app.lerro.mac/preferences.json
```

API Key 在该 JSON 中以明文保存。Application Support 根目录权限收紧为 `0700`，
`preferences.json` 在每次原子写入后收紧为 `0600`。日志、历史、错误信息、fixture、
公开导出和诊断摘要排除 API Key。设置界面使用 `SecureField` 和 view-local draft，
用户确认保存时才写入 JSON。

该选择接受以下边界：当前 macOS 用户权限下运行的软件可以读取明文配置；文件备份和
手动复制会携带 API Key。产品隐私说明和设置页持续展示这项事实。

### 上下文

远程 Dictate 的 payload 包含：

- Apple Speech 原始转写。
- 版本化规范化规则。
- App 类型和名称、可选窗口标题、光标前 80 字符、光标后 40 字符、最多 4,096 字符的选中文字。
- 用户语气和最多 12 个实际命中的词典条目。

PID、bundle identity、选区 fingerprint、完整文档、完整历史、未命中词典和原始音频
留在本机。workspace 字段按不可信参考数据处理。API Rewrite 要求用户开启选中文字
发送；超出上限时在模型调用前停止。

## 备选方案

| 方案 | 结果 |
| --- | --- |
| macOS Keychain | 凭据获得系统加密和访问控制；开发签名变化与钥匙串状态可能带来额外交互，配置也分散到两个存储系统 |
| 独立 secrets JSON | 可以单独备份或排除；增加第二套迁移、写入和恢复路径 |
| Lerro 托管代理 | 用户配置最少；引入账号、服务端、运营成本和新的数据控制责任 |

当前产品选择单一 JSON 配置，以透明度和本地可操作性为优先级。

## 后果

### 收益

- 用户填写 Key 后即可使用，无额外系统凭据交互。
- DeepSeek、OpenAI、Gemini 与自定义服务共用一套 runtime 和测试。
- 本地模型、基础听写和云端模型可以在一个明确页面切换。
- 配置迁移、fixture 和问题复现保持 JSON-first。

### 成本与风险

- API Key 以明文落盘，文件权限与日志脱敏成为发布门禁。
- 第三方 Provider 会获得用户选择发送的文本和常规连接元数据。
- 兼容 API 在错误结构、流式分片和扩展字段上存在差异，需要确定性网络测试。
- Provider 服务可用性、价格、配额和数据政策由对应服务商控制。

## 隐私与安全

- 云端模式默认需要用户主动配置并启用。
- 设置页逐项展示发送字段和本地保留字段。
- URLSession 使用 ephemeral 配置，关闭 Cookie 与 URL cache。
- 生产 endpoint 使用 HTTPS；本地开发可显式使用 loopback HTTP。
- 重定向阻止跨 origin 和 HTTPS 降级。
- 错误与日志只保留状态码、Provider 和无内容诊断。
- 远程结果首版不触发自动词典学习。

## 迁移与兼容

旧 `enhancementEnabled` 偏好迁移规则：开启映射为 `local`，关闭映射为 `raw`。
缺少远程配置时使用 Provider 默认值和空 API Key。旧历史、词典、模型缓存、热键、
权限身份和 Application Support 根保持原位。

## 验证

- UserPreferences 旧 JSON 解码、往返和明文 Key 持久化测试。
- Application Support `0700` 与 preferences `0600` 权限测试。
- Prompt payload、80/40 上下文、选中文字边界和词典命中测试。
- OpenAI-compatible URL、header、body、响应、错误、取消、大小限制和重定向测试。
- AppSession raw/local/remote 路由、配置冻结、Dictate 回退和非 Dictate 错误测试。
- 使用用户提供的 DeepSeek Key 执行显式 live smoke。
- 全量 `swift test`、Release `.app` 构建、启动和真实当前光标交付。

## 文档同步

- `docs/architecture.md`
- `docs/core-flow.md`
- `docs/models.md`
- `docs/privacy-security.md`
- `docs/testing.md`
- `docs/troubleshooting.md`
- `PRIVACY.md`
- 应用内 Privacy Policy、Terms 和 Release notes
