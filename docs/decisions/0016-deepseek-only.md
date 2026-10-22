# 0016：AI 整理只支持 DeepSeek

- 状态：accepted
- 日期：2026-10-22
- 决策人：Lerro maintainer
- 关联任务/PR：新手引导、首页与设置重做
- 替代：ADR 0006 中的服务商范围（OpenAI、Gemini、自定义端点、模型与地址可配置）

## 背景

Lerro 的目标用户是每天在微信、邮件、飞书里打字的上班族。ADR 0006 让用户在 DeepSeek、OpenAI、Gemini
和自定义端点之间选择，并填写模型名与地址。这些选项对普通用户没有意义：多数人没有 API Key，也分不清
服务商、模型和地址；设置页因此有大量只服务于少数用户的表单，新手引导也无法给出一条确定的路径。

DeepSeek 的单次整理成本很低（每天听写一百多次，一个月约 2 元），并提供官方余额接口
`GET https://api.deepseek.com/user/balance`，返回账户是否可用和各币种余额。有了余额，App 可以直接显示
「还剩多少」，并在余额用完时给出明确提示。

## 决策

1. AI 整理只支持 DeepSeek。地址固定为 `https://api.deepseek.com`，模型固定为 `deepseek-flash`。
   删除 `RemoteProviderKind`、地址策略、模型与地址的设置项。`RemoteProviderConfiguration` 只保存 API Key
   和上下文开关。
2. 用户可见的功能名统一为「AI 整理」。
3. 余额来自 DeepSeek 官方接口，带 API Key 请求，App 只读取金额、币种和可用状态。DeepSeek 没有用量接口，
   用量继续由本地 `ai-usage.json` 统计，费用只使用内置人民币价格，删除价格编辑和美元币种。
4. HTTP 401 和 403 映射为 `LerroError.invalidAPIKey`，HTTP 402 映射为 `LerroError.insufficientBalance`。
   余额用完时 Dictate 回退原始转写并提示「DeepSeek 余额用完了，这次写的是原文」，Translate 保持明确失败。
5. 旧服务商配置不迁移。`preferences.json` 里只有 DeepSeek 的旧 Key 会被保留；OpenAI、Gemini、自定义服务商的
   Key 在解码时丢弃，避免把别家的 Key 发给 DeepSeek。其他旧字段（地址、模型、价格覆盖）被忽略。

## 备选方案

| 方案 | 未采用的原因 |
| --- | --- |
| 保留多服务商，只在引导里推荐 DeepSeek | 设置页仍要维护服务商、模型、地址三组表单和对应测试，普通用户仍会看到它们 |
| Lerro 托管代理 | 引入账号、服务端和数据控制责任，见 ADR 0006 |
| 迁移旧服务商配置 | 迁移代码只服务极少数用户，且无法保证别家的模型名和地址在 DeepSeek 上有效 |

## 后果

- 引导和设置只需要讲清一件事：拿到 DeepSeek Key，粘贴，完成。
- 想用其他服务商的用户需要使用旧版本，或转用 DeepSeek。
- 请求内容和余额请求都只发往 `api.deepseek.com`；`PRIVACY.md`、隐私政策页和服务条款同步更新。
- 依赖 DeepSeek 的接口形态和可用性。余额读取失败时界面显示「读不到」，不影响听写。

## 隐私与安全

- 余额请求不含文字内容，只带 Authorization header。日志不记录 API Key 和余额响应内容。
- API Key 仍是 `preferences.json` 里的明文字段，目录 `0700`，文件 `0600`。
- 新增的网络用途（`/user/balance`）写入 `PRIVACY.md` 与应用内隐私政策。

## 验证

`UserPreferencesTests`（旧配置解码：DeepSeek 保留 Key，其他服务商丢弃 Key）、
`OpenAICompatibleHTTPClientTests`（401、402 映射，余额请求）、`DeepSeekBalance` 解析测试、
`AppSessionCoreFlowTests`（连接结果、余额状态、余额用完时的回退与失败、旧结果无权更新新会话）。
