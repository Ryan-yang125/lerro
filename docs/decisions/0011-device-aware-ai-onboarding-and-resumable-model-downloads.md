# 0011：设备感知 AI 引导与可恢复模型下载

- 状态：accepted
- 日期：2026-08-11
- 决策人：Lerro maintainers
- 关联任务/PR：Lerro 1.5.1 onboarding
- 替代：扩展 ADR 0001 的下载恢复边界

## 背景

Lerro 的本地模型约 3.03 GB。首次使用者需要在开始核心练习前完成一条可用路径：准备本地
模型、配置自己的 OpenAI-compatible API，或明确选择基础听写。设备性能、下载时间和 API
凭据要求会直接影响这项选择。模型下载还需要在关闭页面、暂停和 app 重启后保持可恢复。

## 决策驱动因素

- 首次使用者可以在 Onboarding 内完成 AI 选择和必要配置。
- 设备建议来自可解释的本机事实，不上传硬件快照。
- 下载过程可见、可暂停、可继续、可停止，并保留完整缓存。
- Quick Dictate 在模型准备期间保持可用。
- Core 策略、macOS 硬件读取、Intelligence 下载和 SwiftUI 呈现继续遵循单向依赖。

## 方案

1. Core 的 `LocalAIReadiness` 根据 Apple silicon、Metal、16 GiB 内存和 10 GiB 可用空间给出
   local recommended、remote recommended 或 local unavailable。
2. LerroMac 的 `MacDeviceCapabilityAssessor` 读取芯片、Metal、物理内存和目标卷容量；快照只
   存在于当前 AppSession。
3. Onboarding 提供本地 AI、API 模型和基础听写三条路径。API 路径内完成 Provider、Model、
   Base URL、Key、上下文开关、固定合成连接测试和保存启用。
4. AppSession 拥有本地模型准备任务。关闭 Onboarding 或主窗口后任务继续；退出 app 时 runtime
   保存 checkpoint，下一次启动呈现 paused 并允许继续。
5. ETag-aware Apple 下载使用 `cancel(byProducingResumeData:)` 持久化 `<etag>.resume-data`。
   下一次请求优先恢复；系统拒绝或数据失效时清理该文件并发起完整请求。
6. 暂停保留未完成文件、resume data 和模型 checkpoint。停止清理这三类工件，完整 blob、
   snapshot 和 ref 继续保留。
7. 已批准本地模型仍在 preparing 时，Quick Dictate 为当前 capture 冻结 raw 路由并交付 Apple
   Speech transcript；用户的 local 偏好保持不变，ready 后的新 capture 自动使用本地模型。

## 备选方案

### 所有设备默认本地模型

流程统一，低内存或低磁盘设备会承担更长等待、内存压力和失败恢复成本。

### 所有设备默认 API

启动速度快，隐私优先和离线用户仍要额外寻找本地模式入口。

### 下载期间阻塞 Onboarding

教学顺序简单，3 GB 级下载会长时间占据首次体验，并阻止基础语音能力产生价值。

## 后果

### 收益

- 新用户在一个流程内获得设备建议、完成配置并理解完整产品工作流。
- 下载可跨页面和 app 启动恢复，显式停止也有清晰的数据删除边界。
- 模型准备期间仍可完成 Quick Dictate、权限和非 AI 教学。
- 设备策略与系统读取可独立测试和替换。

### 成本与风险

- URLSession resume data 的实际可用性取决于系统和服务端响应；失败时会完整重试当前文件。
- 16 GiB 与 10 GiB 是当前 Qwen3.5 4B 的产品阈值，默认模型或 runtime 变化时必须重新评估。
- 真实暂停、重启和续传需要目标设备、网络与 Hugging Face 服务共同验收。

## 隐私与安全

- 硬件快照不进入磁盘、日志或网络。
- 下载 checkpoint 只含模型 ID、比例和字节数。
- 公共 HubClient 继续使用 `bearerToken: nil`。
- Onboarding API Key 遵循现有明文 `preferences.json`、目录 `0700`、文件 `0600` 边界。
- Base URL origin 改变时清除当前 draft 中的 Key；连接测试只发送固定合成消息。

## 迁移与兼容

不新增偏好字段或用户数据迁移。已有完整模型缓存继续识别。首次遇到新 checkpoint 文件时
runtime 直接恢复 paused 状态。停止操作只删除未完成下载工件。

## 验证

```zsh
swift test --filter LocalAIReadinessTests
swift test --filter MLXLanguageModelRuntimeTests
swift test --filter AppSessionCoreFlowTests
swift test --package-path Vendor/swift-huggingface --filter HubCacheTests
swift test --package-path Vendor/swift-huggingface --filter FileOperationsTests
swift test
./script/verify_release.sh
```

Release 人工矩阵覆盖 8 GB 与 16 GB+ 设备建议、真实下载进度、关闭页面后台继续、暂停、重启
恢复、继续、停止清理、完成缓存、断网加载，以及下载期间 Quick Dictate。

## 文档同步

- [`models.md`](../models.md)
- [`architecture.md`](../architecture.md)
- [`core-flow.md`](../core-flow.md)
- [`privacy-security.md`](../privacy-security.md)
- [`testing.md`](../testing.md)
- [`Vendor/swift-huggingface/UPSTREAM.md`](../../Vendor/swift-huggingface/UPSTREAM.md)
