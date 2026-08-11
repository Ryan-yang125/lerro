# Lerro Agent 协作约定

本文件约束所有在本仓库工作的 agent。开始修改前阅读本文件与
[`docs/README.md`](docs/README.md)，再按改动范围阅读对应专题文档。

## 零上下文接手

- 新会话先读取 [`docs/handoff/README.md`](docs/handoff/README.md) 与
  [`docs/handoff/current-state.md`](docs/handoff/current-state.md)，确认当前公开版本、发布边界和待复验项。
- 项目级完整工作流以
  [`.agents/skills/lerro-development/SKILL.md`](.agents/skills/lerro-development/SKILL.md)
  为单一事实源。Codex 从 `.agents/skills` 发现它；Claude Code 通过根
  [`CLAUDE.md`](CLAUDE.md) 和 `.claude/skills` 薄入口接入同一流程。
- `.codex/environments/environment.toml` 只配置 Codex Desktop 的本地 Run 动作；仓库级 Codex Skill 位于 `.agents/skills`。
- 开始实现前运行 `./script/validate_agent_workspace.sh`。准备真实发布时再运行
  `./script/check_maintainer_readiness.sh --release --online`。
- 发布机的非秘密标签和公开仓库工作树路径放在被忽略的
  `config/maintainer.local.env`；模板为
  [`config/maintainer.env.example`](config/maintainer.env.example)。禁止把凭据值、证书身份详情或个人路径写入受版本控制文件。

## 沟通硬规则

- 避免先否定前项、随后肯定后项的对照句式；英文同构句式同样禁用。
- 结论由当前代码、真实 Release 产物、系统运行状态或明确记录的证据支撑。
- 最终说明列出已验证项目、实际命令、产物签名模式和仍需人工验证的系统边界。
- 编译通过、进程存活和合成 fixture 各自只证明对应边界，不能代替真实核心链路结果。

## 开始工作

1. 运行 `git status --short`，保留用户和其他 agent 的并行改动。
2. 阅读 [`Package.swift`](Package.swift) 和受影响模块。
3. 按任务读取：
   - 架构：[`docs/architecture.md`](docs/architecture.md)
   - 核心链路：[`docs/core-flow.md`](docs/core-flow.md)
   - 权限：[`docs/permissions.md`](docs/permissions.md)
   - 模型：[`docs/models.md`](docs/models.md)
   - 测试：[`docs/testing.md`](docs/testing.md)
   - 发布：[`docs/release.md`](docs/release.md)
   - 隐私与安全：[`docs/privacy-security.md`](docs/privacy-security.md)
   - 身份与迁移：[`docs/identity.md`](docs/identity.md)
   - 排障：[`docs/troubleshooting.md`](docs/troubleshooting.md)
   - 开源边界：[`docs/open-source/README.md`](docs/open-source/README.md)
   - 陌生会话接手与完整交付：[`docs/handoff/README.md`](docs/handoff/README.md)
4. 使用 `rg` 定位符号和调用者，再确定改动边界。
5. 先跑最窄的相关验证，再跑改动类型要求的完整门禁。

## Source of truth

| 事实 | 权威来源 |
| --- | --- |
| 平台、target、依赖 | [`Package.swift`](Package.swift)、[`Package.resolved`](Package.resolved) |
| 生产依赖组合 | [`AppDependencies.live()`](Sources/Lerro/App/AppDependencies.swift) |
| 会话状态与产品编排 | [`CaptureModels.swift`](Sources/LerroCore/Models/CaptureModels.swift)、[`AppSession.swift`](Sources/Lerro/App/AppSession.swift) |
| 数据路径、身份与迁移 | [`ApplicationPaths.swift`](Sources/LerroCore/Support/ApplicationPaths.swift)、[`ApplicationDataMigrator.swift`](Sources/LerroCore/Support/ApplicationDataMigrator.swift) |
| 智能处理与模型行为 | [`PipelineIntelligenceService.swift`](Sources/LerroCore/Services/PipelineIntelligenceService.swift)、[`CloudPromptComposer.swift`](Sources/LerroCore/Services/CloudPromptComposer.swift)、[`MLXLanguageModelRuntime.swift`](Sources/LerroIntelligence/MLXLanguageModelRuntime.swift)、[`OpenAICompatibleRemoteLanguageModelRuntime.swift`](Sources/LerroIntelligence/OpenAICompatibleRemoteLanguageModelRuntime.swift) |
| macOS 系统适配 | [`Sources/LerroMac`](Sources/LerroMac) |
| UI 令牌与实现 | [`DesignTokens.swift`](Sources/Lerro/DesignSystem/DesignTokens.swift)、[`Components.swift`](Sources/Lerro/DesignSystem/Components.swift)、Feature views |
| 构建、签名、打包 | [`build_and_run.sh`](script/build_and_run.sh)、[`signing_support.zsh`](script/signing_support.zsh)、[`package_release.sh`](script/package_release.sh)、[`verify_release.sh`](script/verify_release.sh) |
| 应用身份与系统声明 | [`Info.plist`](config/Info.plist)、[`Lerro.entitlements`](config/Lerro.entitlements)、[`PrivacyInfo.xcprivacy`](Sources/Lerro/Resources/PrivacyInfo.xcprivacy) |
| CI 门禁 | [`.github/workflows/ci.yml`](.github/workflows/ci.yml) |
| 品牌资产与许可 | [`Brand/README.md`](Brand/README.md)、[`ASSET-LICENSES.json`](Brand/licenses/ASSET-LICENSES.json) |
| 公开导出边界 | [`public_repo_allowlist.txt`](script/public_repo_allowlist.txt)、[`scan_public_repo.sh`](script/scan_public_repo.sh) |

测试数量、测试文件数量和 target 数量由 `swift package describe --type json`
与 `swift test` 的当前输出决定。文档不维护脱离 commit 的固定数量。

## 架构不变量

依赖方向保持单向：

```text
Lerro -> LerroIntelligence -> LerroCore
   |                           ^
   +----------> LerroMac ------+
```

- `LerroCore` 保持 Foundation-only，承载模型、协议、规则、提示词和存储抽象。
- MLX 与 Hugging Face 依赖集中在 `LerroIntelligence`。
- `swift-huggingface` 与 `swift-transformers` 通过根包的本地 path 依赖进入构建；所有生效 manifest 使用相邻的 patched Hub，保持单一 package identity。
- Vendor 更新保留 `LICENSE` 与 `UPSTREAM.md`，记录上游 release、commit、本地增量和日期。
- AppKit、Accessibility、AVFoundation、Core Audio、Speech、CGEventTap 和 ServiceManagement 集中在 `LerroMac`。
- `AppDependencies.live()` 是生产组合根；fixture 组合全部使用 inert adapters。
- UI 与 AppKit 生命周期在 `@MainActor` 上运行；长任务位于 actor 或明确的异步协议后方。
- 每次录音使用独立 generation 和 session ID，旧异步结果无权更新新会话。
- 业务规则优先进入 Core；系统行为通过窄协议注入；视图负责展示与用户意图转发。

## 核心链路不变量

- 捕获流程由 `CapturePhase` 和 `AppSession` 驱动：授权与权限 → 上下文 → 收音 → 转写 → raw/local/remote 处理 → 交付或回答卡 → 持久化 → 完成。
- `transcribing`、`enhancing`、`inserting` 阶段忽略重复开始或停止快捷键。
- 捕获快捷键只有 `hold` 与 `toggle` 两种公开模式；hold 的 release 必须匹配启动时的 definition ID，toggle 的第二次点按完成锁定录音。
- 单修饰键通过 `flagsChanged` 识别；命中普通键时吞掉 down、repeat 与 up，未命中的系统 chord 保持透传。
- 快捷键冲突按规范化物理 signature 判断；左右同类修饰键共享语义，legacy modifier keyCode 与对应 flag 视为同一 binding。
- trigger 通过单一 FIFO consumer 进入 `AppSession`；Fn 前缀升级到更具体 chord 时依次取消旧 capture、转交物理按键所有权并启动目标 action。
- event tap 的重复安装和相同 definitions 更新保持幂等，禁止在捕获权限刷新期间清除已收到的 key-down。
- 正常逻辑 reset 保留已吞键直到对应 key-up 与 modifier release；Lerro 合成的交付按键带 source marker 并始终透传。
- Onboarding 与设置录制快捷键时暂停生产 hotkey dispatch，测试状态禁止启动麦克风、HUD、历史或文本交付。
- 开始录音前检查安全输入框。
- 自动 `.insert` 使用提交瞬间的当前键盘焦点，不依赖 AX focused element、选区、PID 或 bundle；Ask card 显式插入先恢复捕获应用，再走相同 current-focus paste。
- `.replaceSelection` 绑定原进程或原 bundle，并确认安全状态、focused element 与原选区保持不变。
- 文本通过剪贴板和合成 Command-V 交付；普通插入在 500ms 后恢复 best-effort 归档，Rewrite 只在本 session 仍持有 marker 时恢复严格归档。
- 取消信号贯穿激活、Command-V 提交前检查、Speech 和模型任务；`inserting` 在提交前继续接受取消，Command-V down/up 提交是文本交付 commit point，提交后会完成剪贴板等待与恢复并忽略取消；所有退出路径释放已按下按键并恢复输出音频。
- 取消、失败和过期 session 清理未持久化录音、重置热键临时状态并阻止旧结果提交。
- 原始 Dictate 直接交付 Apple Speech transcript；Translate、Ask、Rewrite 和智能 Dictate 受当前 local/remote 模式授权策略约束。
- capture 启动时冻结 intelligence mode、Provider 配置、API Key 与上下文开关；Dictate 的模型失败回退原始 transcript，Translate、Ask 和 Rewrite 保持明确失败。
- 模型调用前保留原始 transcript；生产链路不运行 `TextPipeline` 预清洗。remote 结果不进入词典自动学习。
- 普通 Dictate 遵循系统 Command-V 语义；Rewrite 额外执行严格选区一致性验证。
- 交付失败保存可恢复的失败历史和最终文本，UI 保持失败状态。
- 捕获、识别、模型和交付错误只进入 HUD 失败态，不触发主窗口 alert、Dock attention 或失败声音；设置、存储、迁移等需要用户处理的错误继续使用 app-level 提示。
- 删除带录音历史时先删除音频，再移除索引；历史索引读取失败时保留孤儿文件等待恢复。

完整流程与失败出口见 [`docs/core-flow.md`](docs/core-flow.md)。

## 隐私、权限与模型不变量

- 原始音频默认关闭；`saveAudio` 默认值保持 `false`。
- `historyRetention == .never` 时禁止写入新历史和新录音。
- 默认模型约 3.03 GB，下载前取得用户明确确认。
- 本地模型下载由 AppSession 持有，支持后台继续、暂停、重启恢复和停止；停止只清理未完成
  文件、resume data 与下载 checkpoint，完整 blob 保留。
- Hugging Face 公共客户端保持 `bearerToken: nil`，不继承本机 CLI 登录令牌。
- 真实缓存模型 smoke 默认跳过。标准显式入口是 `LERRO_LIVE_MODEL_OFFLINE=1 ./script/test_live_model.sh`，执行前记录授权、模型 ID、缓存来源、网络状态、硬件和结果。
- 测试与 fixture 使用临时目录和 inert adapters，避开真实 Application Support、麦克风、TCC、AX、CGEventTap、剪贴板和登录项。
- 日志排除 transcript、selected text、focused text、prompt、模型回答、邮箱、邀请码、凭据和个人路径。
- 新增网络、权限、日志、数据字段或 Required Reason API 时，同步审查 `PRIVACY.md`、privacy manifest、Info.plist、entitlements、测试和发布说明。
- BYOK Provider、Base URL、Model ID、API Key 与上下文开关统一保存在 `preferences.json`；API Key 为明文字段，Application Support 根目录保持 `0700`，preferences 文件保持 `0600`，日志与公开导出排除凭据。
- usage description、entitlement 和签名构成系统声明与身份；用户在目标 Mac 上完成 TCC 授权。
- 新 Bundle ID 使用新的权限身份。迁移在 repositories 和模型 runtime 初始化前执行，并保持幂等、可回滚和模型单副本。

## Apple-native UI 不变量

- 主窗口界面使用 `LerroTheme` 自适应黑白灰色板；警告、错误和成功继续使用 macOS
  system status colors。Aqua、Dark Aqua 与 Increase Contrast 各自解析对应灰阶值。
- 浅色正文层级依次为 `#292929`、`#5D5D5D`、`#9E9E9E`；承担必要信息的
  12 pt 小字使用 `#6B6B6B`，避免把低对比 tertiary text 用于关键内容。
- App UI 使用 SF Pro、苹方与 SF Mono。主窗口字号只使用 24、14、13、12 pt，
  tracking 统一为 `-0.15`。
- 导航图标为 14 pt、导航圆角为 8 pt；卡片图标为 20 pt、卡片圆角为 16 pt；
  主要 CTA 使用 pill 形态。
- 主窗口 hover 以 150 ms ease-out 更新填充、边界或阴影；pointer-down 立即下沉
  1 pt。Reduce Motion 下取消按压位移，并保留清晰的透明度反馈。
- 仓库不分发 Apple 字体；App UI 不捆绑第三方字体。
- 品牌固定色仅用于可导出的品牌资产预览；主 UI 内容层使用 `LerroTheme` 灰阶，
  主要动作与焦点继承系统 Accent Color，success、warning、error 使用系统语义色。
- App Icon、菜单栏四态、HUD、Ask、窗口和公开截图全部使用 Lerro 品牌资产。
- HUD 外壳、声线、processing 节奏、状态切换、静音反馈与 Reduce Motion 行为继续以
  `CaptureHUDView.swift` 和既有 HUD fixture 为准；processing 三点继承系统 Accent Color。
- 颜色、尺寸、圆角和字体先更新 `DesignTokens.swift` 或共享组件，再更新页面。
- 视觉 fixture 只使用 inert adapters，不能触发系统权限、真实录音、真实文本交付或用户数据写入。
- UI 改动至少验证 1080×750、988×658、浅色、深色、Increase Contrast、
  Reduce Transparency、Reduce Motion、VoiceOver，以及受影响的 HUD、Ask 和设置状态。

品牌源稿、使用规则、动效与许可见 [`Brand/`](Brand)。

## 构建与签名不变量

- SwiftPM GUI 应用通过 `./script/build_and_run.sh` 组装标准 `.app`。
- `.build` 下的裸 executable 不具备完整 app bundle 语义，不能作为 Release 验收对象。
- Release 验收对象是 `dist/Lerro.app` 和最终 ZIP 独立解压后的 `.app`。
- SwiftPM `.bundle`、图标、隐私文件、条款、第三方许可证和 upstream NOTICE 保留在 `Contents/Resources`。
- app binary 与 dSYM 都是 arm64，UUID 保持一致。
- 签名模式为 `auto`、`development`、`ad-hoc`、`developer-id`，解析规则以 `signing_support.zsh` 为准。
- `ad-hoc` 用于本机与 CI；`development` 用于稳定 TCC 测试；`developer-id` 同时需要 notary profile。
- 发布期间源码树发生变化时立即停止并重新打包。
- 失败的构建、公证或复验不得覆盖上一份有效 canonical 产物。
- 版本发布同步更新 `CFBundleShortVersionString`、`CFBundleVersion`、CHANGELOG 与验收记录。

## 开源边界

- 公开仓库由 `script/export_public_repo.sh` 从显式 allowlist 生成。
- `outputs/`、`work/`、`.build/`、`dist/`、模型权重、用户数据、日志、录音、证书信息、Team ID、个人路径和研究材料不进入公开导出。
- 旧产品身份只允许出现在数据迁移常量、迁移测试和明确的兼容说明中。
- 每项第三方依赖、模型、字体和资产都保留来源与许可证记录。
- 干净导出初始化独立空 Git 仓库，不继承源仓库对象、refs、作者身份或 remote。

## 变更门禁

| 改动范围 | 必须完成 |
| --- | --- |
| Core 模型、规则、存储、迁移 | focused tests、`swift test`、迁移幂等与回滚验证 |
| `AppSession`、组合根 | `LerroTests`、全量测试、Release bundle、受影响的实机核心路径 |
| Speech、Audio、Core Audio | 全量测试、真实麦克风成功/取消/错误、输出音频恢复、录音保留 |
| AX、热键、权限 | 全量测试、安全输入框、TextEdit 交付、剪贴板恢复、真实 TCC |
| Intelligence、模型、BYOK runtime | 全量测试、授权与上下文边界；真实 local/remote 链路分别需要显式授权的加载或 API 生成证据 |
| Vendor、Hub 下载 | vendored tests、依赖来源、许可证、真实缓存模型 smoke 或跳过原因 |
| UI、窗口、HUD、Ask | fixture 截图、可访问性、Release app 真实窗口检查 |
| scripts、config、resources | shell/plist 检查、Release package、独立解压复验 |
| 治理、许可证、公开文档 | public export、allowlist、秘密、旧身份、资产许可和空 Git 历史扫描 |

精确命令见 [`docs/testing.md`](docs/testing.md)、[`docs/release.md`](docs/release.md)
和 [`docs/open-source/clean-export.md`](docs/open-source/clean-export.md)。

## 公开 Release definition of done

完成声明至少包含：

- 相关 focused tests 和全量 `swift test` 结果。
- Release `.app` 的构建、架构、dSYM UUID、资源与签名验证。
- 最终 ZIP、dSYM ZIP、release manifest、SBOM 与 `SHA256SUMS.txt` 校验。
- 核心改动对应的真实 Release 人工矩阵结果。
- UI 改动的 fixture、真实窗口与可访问性证据。
- 公开导出扫描及其中独立空 Git 仓库的验证结果。
- 未运行的模型下载、TCC、硬件、多显示器、Developer ID 或公证项逐项列明。
- `git diff --check` 和最终 `git status --short`。

`./script/build_and_run.sh --verify` 证明测试通过并确认进程短暂存活。真实麦克风、Speech 资源、TCC、Accessibility、CGEventTap、MLX 生成和跨应用写入分别由对应实机门禁证明。

## 文档维护

- 行为、命令、环境变量、签名模式和数据边界变化时，同一变更更新对应文档。
- 文档链接代码文件和符号名，减少复制实现。
- 架构边界变化时新增 ADR，模板见 [`docs/decisions/README.md`](docs/decisions/README.md)。
- 交付前运行文档链接检查、禁用表达扫描和公开仓库扫描。
