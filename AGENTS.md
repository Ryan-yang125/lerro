# Lerro Agent 协作约定

本文件约束所有在本仓库工作的 agent。Lerro 是开源的 macOS 听写应用（Apache-2.0），处于维护模式，由一位维护者负责。

## 开始工作

1. 读 [`README.md`](README.md) 和 [`docs/README.md`](docs/README.md)，按任务读 [`docs/architecture.md`](docs/architecture.md) 或 [`docs/development.md`](docs/development.md)。
2. 运行 `git status --short`，保留用户和其他 agent 的并行改动。
3. 运行 `./script/validate_agent_workspace.sh`（检查 agent 入口文件与 Markdown 相对链接）。
4. 用 `rg` 定位符号和调用者，再确定改动边界；先跑最窄的相关测试。
5. 完整工作流见 [`.agents/skills/lerro-development/SKILL.md`](.agents/skills/lerro-development/SKILL.md)；Claude Code 通过 `CLAUDE.md` 与 `.claude/skills` 进入同一流程。
6. 构建、测试、签名与发布命令都在 [`docs/development.md`](docs/development.md)。

## 沟通硬规则

- 避免先否定前项、随后肯定后项的对照句式；英文同构句式同样禁用。
- 用直接、字面的表达，不用隐喻和修饰性语句。
- 结论由当前代码、真实构建产物、系统运行状态或记录下来的命令输出支撑。
- 最终说明列出实际运行的命令、结果，以及没有验证的系统边界。编译通过、进程存活和 fixture 各自只证明对应边界。

## 架构不变量

```text
Lerro -> LerroIntelligence -> LerroCore
   |                           ^
   +----------> LerroMac ------+
```

- `LerroCore` 只依赖 Foundation，承载模型、协议、规则、提示词和存储。
- `LerroIntelligence` 只含 OpenAI-compatible 远程运行时。
- AppKit、Accessibility、AVFoundation、Core Audio、Speech、CGEventTap、ServiceManagement 集中在 `LerroMac`。
- `AppDependencies.live()` 是唯一生产组合根；fixture 组合只使用 inert adapters。
- `AppSession`（`@MainActor`）是会话状态的唯一所有者。每次录音有独立 generation 和 session ID，旧异步结果无权更新新会话。
- 业务规则优先进入 Core，系统行为通过窄协议注入，视图负责展示并转发用户意图。
- 新增第三方依赖前先检查现有依赖是否已覆盖；每项依赖保留许可证记录（[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)）。

## 核心链路不变量

- 流程：权限 → 上下文冻结 → 收音 → 转写 → raw/remote 处理 → 严格目标交付 → 完成。交付完成后 session 立即回到 `idle`，历史、用量和词典持久化在后台串行执行。
- 麦克风先打开，音频在内存中缓冲到 `SpeechTranscriber` 就绪。词典不发给 Apple Speech，只进入 AI 提示词。
- 捕获快捷键只有 `hold` 与 `toggle`；hold 的 release 必须匹配启动时的 definition ID。`transcribing`、`enhancing`、`inserting` 阶段忽略重复开始或停止。
- capture 启动时冻结智能模式、Provider 配置、API Key 与上下文开关。Dictate 的模型失败回退原始 transcript，Translate 保持明确失败。
- 开始录音前检查安全输入框。交付前校验目标应用、元素、完整值、选区和安全状态指纹，任一漂移都停止写入，最终文本留在剪贴板。
- 文本通过剪贴板加合成 Command-V 交付；Command-V down/up 发布完成是 commit point，交付随即返回并忽略之后的取消；剪贴板恢复（固定等待 500 ms）在后台完成，下一次交付先等待上一次恢复结束；Lerro 合成的按键带 source marker 并始终透传。
- 取消、失败和过期 session 清理未持久化录音、释放已按下的按键、恢复输出音频、阻止旧结果提交。
- 捕获、识别、模型和交付错误只进入 HUD 失败态；设置和存储错误使用 app 级提示。
- 删除带录音的历史时先删音频再移除索引。

## 隐私与安全

- 日志排除 transcript、选中或焦点文本、提示词、模型回答、词典内容、API Key、邮箱和个人路径。
- 原始音频默认关闭（`saveAudio == false`）；`historyRetention == .never` 时不写入新历史和录音。
- API Key 是 `preferences.json` 里的明文字段；Application Support 根目录保持 `0700`，该文件保持 `0600`。
- 测试和 fixture 使用临时目录和 inert adapters，不接触真实 Application Support、麦克风、TCC、AX、CGEventTap、剪贴板和登录项。
- 新增网络、权限、日志、数据字段或 Required Reason API 时，同步审查 `PRIVACY.md`、privacy manifest、Info.plist、entitlements 和测试。
- 凭据、签名身份、Team ID、notary profile 不进入受版本控制的文件、日志和聊天；维护者本地配置在 `config/maintainer.local.env`（已忽略）。

## UI 规则

- 主窗口是固定宽度侧栏加页面，每页顶部用 `LerroPageHeader`（[ADR 0017](docs/decisions/0017-fixed-sidebar.md)），设置在独立的 `Settings` 窗口；列表、表格和表单使用原生控件。
- 颜色来自 `LerroTheme`（自适应灰阶 + 墨水蓝强调色），字号来自 `LerroFont`；改动先更新 [`DesignTokens.swift`](Sources/Lerro/DesignSystem/DesignTokens.swift) 或共享组件，再更新页面。
- 图标：一律使用 SF Symbols 描边版本，状态和播放控制用实心；不自绘产品图标。
- HUD 是固定墨黑的单胶囊，所有状态在同一胶囊内形变；外观规则见 [ADR 0013](docs/decisions/0013-brand-capsule-hud.md)。
- 不在标题、卡片或设置项下方添加说明性小字，除非用户要求或为了避免误解。
- UI 改动用 inert fixture（见 `docs/development.md`）检查 1080×750 与 988×658、浅色、深色、Increase Contrast、Reduce Transparency、Reduce Motion。
- 品牌资产与规则在 [`Brand/`](Brand/README.md)。

## 变更与发布

- 行为、命令、环境变量或数据边界变化时，同一变更更新对应文档。长期架构决策写入 [`docs/decisions/`](docs/decisions/README.md)。
- 改动范围对应的最低验证：Core 与存储跑 `swift test`；`AppSession`、系统适配、UI 改动在此之上构建并运行 `./script/build_and_run.sh`；脚本与配置跑 shell 和 plist 检查。
- push、tag、Cloudflare 部署、GitHub Release 和公证提交都会改变外部状态，只在用户明确要求时执行。发布步骤见 `docs/development.md` 的 Release 一节。
- 交付前运行 `git diff --check` 并报告 `git status --short`。
