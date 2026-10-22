# 0006：BYOK OpenAI-compatible Provider 与 JSON 凭据

- 状态：superseded（服务商范围由 [ADR 0016](0016-deepseek-only.md) 替代；模式、JSON 凭据和上下文部分仍然有效）
- 日期：2026-08-01
- 决策人：Lerro maintainer

## 背景

用户希望使用自己的 DeepSeek、OpenAI、Gemini 或其他 OpenAI-compatible API 完成低延迟的文本整理，同时保持快捷键、HUD、Apple Speech
和 Command-V 链路不变。

## 决策

### 模式与 Provider

智能处理有两种模式：

1. `raw`：Apple Speech 原始转写直接交付。
2. `remote`：原始转写与用户允许的上下文进入 OpenAI-compatible runtime。

capture 开始时冻结模式、endpoint、model、API Key 和上下文授权，设置变化从下一次 capture 生效。Dictate 的远程错误回退到原始转写，
Translate 保持明确的错误状态。

| Provider | API base | 默认 Model ID |
| --- | --- | --- |
| DeepSeek | `https://api.deepseek.com` | `deepseek-flash` |
| OpenAI | `https://api.openai.com/v1` | 用户填写 |
| Gemini | `https://generativelanguage.googleapis.com/v1beta/openai` | 用户填写 |
| Custom | 用户填写 | 用户填写 |

请求使用 Chat Completions。DeepSeek 使用非思考模式和 `temperature: 0`。连接测试只发送固定合成内容。

### JSON 配置与 API Key

Provider、Base URL、Model ID、API Key、模式和上下文开关保存在 `~/Library/Application Support/app.lerro.mac/preferences.json`。
API Key 以明文保存。根目录权限为 `0700`，`preferences.json` 在每次原子写入后收紧为 `0600`。日志、历史、错误信息和 fixture 排除
API Key；设置页使用 `SecureField` 和 view-local draft，用户确认保存时才写入。

这个选择的代价是：同一 macOS 用户下运行的软件可以读取该文件，备份和手动复制会带走 API Key。隐私说明与设置页展示这一事实。

### 上下文

远程 Dictate 的 payload 包含 Apple Speech 转写、提示词规则、应用类型与名称、可选窗口标题、光标前 80 与后 40 个字符、应用语气、
命中的词典条目（最多 12 个）和 `known_terms`（最多 40 个）。PID、Bundle ID、选区指纹、完整文档、完整历史和原始音频留在本机。
workspace 字段按不可信参考数据处理。

## 备选方案

| 方案 | 未采用的原因 |
| --- | --- |
| macOS Keychain | 签名身份变化会带来额外交互，配置分散在两个存储中 |
| 独立 secrets JSON | 多一套迁移、写入和恢复路径 |
| Lerro 托管代理 | 引入账号、服务端和数据控制责任 |

## 后果

- DeepSeek、OpenAI、Gemini 与自定义服务共用一套 runtime 和测试。
- 第三方 Provider 会获得用户选择发送的文本和常规连接元数据。
- 兼容 API 在错误结构和扩展字段上存在差异，需要确定性网络测试。

## 隐私与安全

- remote 模式需要用户主动配置并启用，设置页逐项展示发送字段。
- URLSession 使用 ephemeral 配置，关闭 Cookie 与 URL cache；生产 endpoint 使用 HTTPS，本地开发可使用 loopback HTTP。
- 重定向阻止跨 origin 和 HTTPS 降级；错误与日志只保留状态码、Provider 和无内容诊断。

## 验证

`OpenAICompatibleHTTPClientTests`（URL、header、body、响应、错误、取消、大小限制、重定向）、`UserPreferencesTests`（解码、
往返、权限）、`CloudPromptComposerTests`（payload 与上下文边界）、`AppSessionCoreFlowTests`（路由、配置冻结、Dictate 回退）。
`./script/test_live_remote.sh` 在有 DeepSeek Key 时做真实调用检查。
