# 0001：Vendored Hugging Face 下载栈

- 状态：accepted
- 日期：2026-07-30
- 决策人：Lerro maintainers
- 关联任务/PR：[PR #50](https://github.com/huggingface/swift-huggingface/pull/50)、[Issue #52](https://github.com/huggingface/swift-huggingface/issues/52)
- 替代：无

> 2026-08-11：本记录的首次中断恢复边界由
> [ADR 0011](0011-device-aware-ai-onboarding-and-resumable-model-downloads.md) 扩展；其余 Vendor、缓存提交与来源决策继续有效。

## 背景

Lerro 的默认 MLX 模型约 3.03 GB。首次使用需要可见且单调的下载进度；取消、已有 `.incomplete` 的 Range 合并、重复 blob 和缓存命中也需要明确的文件所有权与临时文件生命周期。

上游 `swift-huggingface` release `0.9.0` 在 Apple 平台的异步下载桥接存在进度与 URLSession 临时文件生命周期问题。[PR #50](https://github.com/huggingface/swift-huggingface/pull/50) 用 continuation 驱动的 `hfAsyncDownload` 和 delegate 所有权修复进度与下载完成交接。截至 2026-07-30，该 PR 状态为 Open，head commit 为 `4abcf1485f3e06456140a1e0d33e72fa0bff273a`。

[Issue #52](https://github.com/huggingface/swift-huggingface/issues/52) 记录了成功下载后 `CFNetworkDownload_*.tmp` 累积问题。Lerro 需要先通过同目录 staging 原子安装完整 blob，再提交 snapshot 和可选 ref，全部成功后消费 URLSession 临时文件；任何 metadata commit 失败都要保留原始 source 供重试。首次 blob 与同 ETag blob 已存在两个路径遵循同一提交顺序，同时保留调用者拥有的普通 source。截至 2026-07-30，该 Issue 状态为 Open。

`swift-transformers` 自身依赖 `swift-huggingface`。根包单独切换 Hub 到本地 path 时，variant manifest 仍可能引入同 identity 的远程包。Swift 6.2 会选择 `Package@swift-6.1.swift`，因此普通 manifest 与 toolchain variant 必须共同维护。

## 决策驱动因素

- 大模型下载进度对用户可见并保持单调。
- 下载成功、已有 `.incomplete` 的 Range 合并、截断 blob、重复 blob、metadata commit 失败、显式 destination fallback 和取消路径具备可验证的文件所有权。
- task 安装前取消、上层取消错误类型、runtime load task 取消与 commit 边界保持一致。
- ETag-aware 与 generic 下载在取得临时 URL 后的所有出口都执行清理。
- `HuggingFace` 与 `Tokenizers` 使用同一份 patched Hub 实现。
- Release 构建不依赖尚未合并的上游进度修复。
- 上游来源、许可证、本地差异和升级路径可审计。
- 常规测试保持确定性，真实模型加载由用户显式授权。

## 方案

1. 在 [`Vendor/swift-huggingface`](../../Vendor/swift-huggingface) 保存上游 release `0.9.0`、baseline commit `b721959445b617d0bf03910b2b4aced345fd93bf`、PR #50 head commit 和本地临时文件消费补丁。
2. 在 [`Vendor/swift-transformers`](../../Vendor/swift-transformers) 保存上游 release `1.3.3`、commit `2fa33e1f5e7131a7fc64c28e6d161dcec0d24820`，并让所有生效 manifest 指向相邻的 `../swift-huggingface`。
3. 根 [`Package.swift`](../../Package.swift) 通过本地 path 引入两个包。`Package.resolved` 继续记录远程传递依赖；本地 path 包的来源由 `Package.swift` 与各自 `UPSTREAM.md` 证明。
4. Apple `hfAsyncDownload` 使用锁保护的 `DownloadTaskBox` 记录 task 安装前的取消；delegate 把 `URLError.cancelled` 归一为 `CancellationError`。`MLXLanguageModelRuntime` 的 waiter 取消底层 load task，并在提交 loaded container 前检查取消。
5. ETag-aware 和 generic 下载路径在取得 `tempURL` 后立即安装 `defer` 清理，覆盖后续每个返回与抛错出口。
6. HEAD 预检读取 `X-Linked-Size`。正数 header 与现有 ETag blob size 不一致时，在 cache fast path 前删除该 blob 并重新下载。header 缺失或无效时继续依赖后续下载与模型加载验证。
7. `HubCache.storeFile` 新增默认关闭的 `consumeSource`。Hub 下载提交 URLSession 临时文件时显式开启。安装器在 blobs 目录创建唯一 staging，同卷尝试 hard-link，链接失败时复制 source；size 校验通过后用同目录 rename 安装新 blob，或原子 replace size 不匹配的旧 blob。最终 blob size 再次校验，随后提交 snapshot 和可选 ref，全部成功后删除 source。snapshot 或 ref 提交失败时抛错并保留 source；故障注入测试验证原始内容仍可读取。
8. `HubClient` 收到显式 destination 时保留 payload 可用性。cache snapshot 提交失败后，cache lookup 会 miss，下载临时文件随后转移到 destination；调用方获得完整文件。无 destination 的 cache-only 调用继续返回明确错误。
9. 自动 Range 合并只消费调用开始前已经存在的 `<etag>.incomplete`。首次网络中断或取消当前不会持久化响应体或 `URLSession` resume data，跨请求与 app 重启续传保留为人工验证边界。
10. 保留两个 Vendor 的 `LICENSE` 和 `UPSTREAM.md`。Release app 的 `ThirdPartyLicenses` 必须包含四份非空记录，并与仓库源文件 byte-identical。
11. `liveCachedModelSmoke` 默认 disabled。[`test_live_model.sh`](../../script/test_live_model.sh) 检查缓存和 Release Metal library，准备临时 symlink，并只在最终 focused test 中设置 `LERRO_LIVE_MODEL_SMOKE=1`。

## 备选方案

### 等待 PR #50 合并和新 release

维护成本最低，发布时间受上游 review 与 release 节奏约束。本轮核心下载进度与文件生命周期需要立即具备确定性，因此保留本地 Vendor。

### 指向个人 fork revision

仓库体积更小，构建继续依赖远程 fork 的可用性与历史保留。来源审计、离线构建和本地消费补丁的可见性较弱。

### 仅在 App runtime 修饰进度

UI 可以维持单调显示，URLSession 临时文件所有权和 Tokenizers 内部 Hub 路径仍缺少修复。该方案无法覆盖下载栈根因。

## 后果

### 收益

- Apple 下载进度、预置 `.incomplete` 后的 Range 合并与最终完成状态可由 vendored tests 证明。
- task 安装前取消会到达底层 `URLSessionDownloadTask`，上层统一观察 `CancellationError`；runtime 在提交 loaded 状态前再次检查取消。
- ETag-aware 与 generic 路径在取得下载临时 URL 后通过 `defer` 覆盖所有后续出口。
- `X-Linked-Size` 可在 cache fast path 前识别并清除 size 不匹配的 ETag blob。
- 首次缓存写入和重复 blob 在完整提交后都会消费下载临时源。
- 截断 blob 会在 snapshot 发布前由完整 staging 原子替换，最终路径不会暴露正在写入的内容。
- snapshot/ref 失败会保留原始 source，后续重试可以复用已存在的 cache 工件并完成缺失元数据。
- 显式 destination 可以在 cache snapshot 失败时继续接收完整 payload。
- 根 runtime 与 Tokenizers 共享相同 patched Hub。
- 构建、调试和上游 diff 可在仓库内完成。

### 成本与风险

- 仓库体积增加，安全与兼容更新需要主动跟踪两个上游。
- SwiftPM variant manifest 容易随工具链变化产生来源分叉。
- 上游合并后可能出现重复修改，升级时需要逐项比较并移除已覆盖的本地 diff。
- 已有 blob 的恢复门禁比较 size；同尺寸内容异常依赖 ETag、HTTP 响应和后续模型加载错误暴露。
- 首次网络中断或取消不会生成可供后续请求使用的 `.incomplete`，也不会保存 `URLSession` resume data；跨请求和 app 重启可能重新下载。
- `X-Linked-Size` 预检依赖服务端提供正数 header。
- 同一模型的并发 load waiter 共享底层任务；任一 waiter 取消会终止其他 waiter。当前主流程通常只有一个 waiter，多 owner 场景需要后续引入引用计数或明确 owner policy。
- 真实模型 smoke 消耗较多内存、磁盘和时间；缓存缺失时可能访问网络。

## 隐私与安全

- 公共模型 HubClient 保持 `bearerToken: nil`，不继承 Hugging Face CLI 凭据。
- 常规测试、CI、fixture 和 `verify_release.sh` 不启用真实模型 smoke。
- 真实 smoke 使用合成输入，只打印最多 240 个字符的合成输出前缀。
- 模型缓存继续位于 Lerro Application Support 的 `Models` 目录。
- 删除缓存、补充下载和真实 MLX 加载需要用户授权或专用验收账户。
- Vendor 许可证进入 Release app，来源 commit 和本地补丁记录保留在仓库。

## 迁移与兼容

每次升级执行：

1. 实时读取 PR #50、Issue #52、最新 upstream release 和相关安全公告，记录检查日期。
2. 对比新 release 是否包含 commit `4abcf1485f3e06456140a1e0d33e72fa0bff273a`，以及 pre-cancel、取消错误归一、post-download `tempURL` 清理、`X-Linked-Size` 预检、已有 `.incomplete` 的 Range 合并边界、staging install → atomic publish/replace → snapshot → optional ref → source removal 的提交语义、截断恢复和失败保留保证。
3. 更新两个 `UPSTREAM.md`、`LICENSE`、基线 commit 和导入日期。
4. 同步 `swift-transformers/Package.swift` 与所有 `Package@swift-*.swift` 的本地 Hub path。
5. 运行依赖图检查，确认本地和远程来源没有 identity 冲突。
6. 运行 vendored tests、根包全量测试、显式缓存模型 smoke 和 Release 门禁。

回滚时选择已验证且同时覆盖进度与临时文件消费语义的上游版本或 Vendor 快照。该决策不改变用户数据格式、模型缓存目录或偏好 Codable。

## 验证

```zsh
swift package show-dependencies --format json
swift test --package-path Vendor/swift-huggingface --filter HubCacheTests
swift test --package-path Vendor/swift-huggingface --filter FileOperationsTests
swift test --package-path Vendor/swift-huggingface
swift test --package-path Vendor/swift-transformers
swift test
./script/verify_release.sh
```

用户授权后的真实缓存模型 smoke：

```zsh
LERRO_LIVE_MODEL_CACHE="$HOME/Library/Application Support/app.lerro.mac/Models" \
LERRO_LIVE_MODEL_ID='mlx-community/Qwen3.5-4B-MLX-4bit' \
./script/test_live_model.sh
```

Release 人工证据继续包含模型下载进度、取消、预置 `.incomplete` 的 Range 合并、首次中断后的跨请求与重启行为、缓存命中、离线重开与内存卸载。首次中断场景需要明确记录重新下载或实际续传结果，自动化测试不提供该场景的通过证明。

## 文档同步

- [`AGENTS.md`](../../AGENTS.md)
- [`architecture.md`](../architecture.md)
- [`testing.md`](../testing.md)
- [`release.md`](../release.md)
- [`troubleshooting.md`](../troubleshooting.md)
