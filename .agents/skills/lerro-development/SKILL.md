---
name: lerro-development
description: Develop, diagnose, validate, document, and release Lerro end to end. Use for any Lerro Swift, macOS integration, Speech, hotkey, permission, UI, model, website, Cloudflare distribution, GitHub mirror, packaging, or release task.
---

# Lerro Development

## 目标

把一次 Lerro 工作推进到与风险相称的完成边界：定位事实、实现最小完整改动、执行确定性验证、完成真实系统验收、同步文档，并在用户明确要求发布时完成 Cloudflare 与 GitHub 的公开闭环。

仓库根目录的 `AGENTS.md` 拥有最高项目优先级。详细实现事实继续以代码、脚本、Release manifest 和专题文档为准。

## 零上下文启动

1. 用 `git rev-parse --show-toplevel` 确认仓库根，随后进入该目录。
2. 运行 `git status --short`，保留用户和其他 agent 的并行改动。
3. 完整读取 `AGENTS.md`、`docs/README.md`、`Package.swift`。
4. 读取 `docs/handoff/README.md` 和 `docs/handoff/current-state.md`。
5. 运行 `./script/validate_agent_workspace.sh`。
6. 使用 `rg` 定位受影响符号、调用者、测试和文档，再给出改动边界。

## 按任务加载事实

| 任务 | 必读 |
| --- | --- |
| Core、状态机、存储、AppSession | `docs/architecture.md`、`docs/core-flow.md`、`docs/testing.md` |
| Speech、Audio、快捷键、AX、权限 | 上述三份 + `docs/permissions.md`、`docs/privacy-security.md`、`docs/troubleshooting.md` |
| MLX、BYOK、模型下载 | `docs/models.md`、`docs/privacy-security.md`、`docs/testing.md` |
| SwiftUI、HUD、Onboarding、设置 | `AGENTS.md` 的 UI 不变量、`docs/ui-parity.md`、`Brand/README.md`、`docs/testing.md` |
| Bundle、脚本、签名、公证 | `docs/build.md`、`docs/release.md`、`docs/testing.md` |
| 网站 | `site/README.md`、`site/package.json`、受影响页面与测试 |
| Cloudflare 更新分发 | `distribution/README.md`、`docs/release.md`、ADR 0007、发布脚本 |
| GitHub、公开源码、治理 | `docs/open-source/README.md`、`docs/open-source/clean-export.md`、public allowlist 与 scanner |
| 真实发布 | 以上相关文档 + `docs/handoff/maintainer-readiness.md` |

只加载当前任务需要的专题文档。长期架构决策同时读取对应 ADR；需要新增 ADR 的边界以 `docs/architecture.md` 为准。

## 判断授权边界

- 回答、解释、审查和诊断任务保持只读。
- 实现任务允许修改仓库、运行确定性测试和生成本地 ignored 产物。
- 真实模型下载、BYOK 请求、TCC reset、证书变更、公证提交、Cloudflare 部署、stable 推进、Git push、tag 与 GitHub Release 都会改变外部或用户状态。执行前确认用户已明确要求对应动作。
- 发布请求覆盖正常发布链路；涉及凭据创建、账号权限变更、域名配置、版本撤回和删除历史对象时继续请求单独授权。
- 任何命令输出都排除 API Key、签名身份详情、Team ID、证书邮箱、notary 凭据和本地配置全文。

## 开发闭环

1. 从现有行为、测试和文档提炼验收条件。
2. 先运行最窄的相关测试，确认基线与真实筛选名称。
3. 把规则放入 Core，把系统 API 放入 LerroMac，把模型运行时放入 LerroIntelligence，把页面与编排放入 Lerro。
4. 使用 `apply_patch` 完成可审查改动，保持无关工作树内容不变。
5. 重跑 focused tests，随后执行变更类型要求的完整门禁。
6. UI 改动生成 inert fixture 证据；系统集成改动使用最终 `.app` 完成相应 T4 行。
7. 同步行为文档、隐私声明、ADR、CHANGELOG、网站文案或 Release Notes。
8. 运行 `git diff --check`、文档与 Skill 校验、公开导出扫描，并记录仍需人工验证的边界。

## 验证层级

按 `docs/testing.md` 的 T0–T5 证明等级报告结果：

- T0：shell、plist、package、文档和静态声明。
- T1：focused tests 与完整 `swift test`。
- T2：`./script/build_and_run.sh --release --no-launch` 生成真实 app bundle。
- T3：inert fixture、双语页面、视觉和可访问性矩阵。
- T4：最终 Release app 的真实麦克风、Speech、Fn/Globe、AX、剪贴板、焦点和跨应用交付。
- T5：显式授权的真实模型/BYOK，以及 Developer ID、公证、Gatekeeper、Cloudflare、Sparkle 和 GitHub 分发。

`./script/build_and_run.sh --verify` 只覆盖全量测试、bundle 组装、启动和短暂存活。核心链路完成声明必须附上对应 T4/T5 证据。

## 网站闭环

在 `site/` 运行：

```zsh
npm ci
npm run lint
npm run build
npm test
npm audit --omit=dev --audit-level=high
```

获得部署授权后执行 `npm run deploy`，再检查四条语言路由、changelog、截图、下载链接、metadata、重定向和真实浏览器渲染。保存 Worker version 与公开 URL。

## App 与公开发布闭环

1. 更新版本、build、CHANGELOG、站点 changelog 和本版验收记录。
2. 提交并冻结发布源；发布期间 source tree 保持静止。
3. 运行 `./script/check_maintainer_readiness.sh --release --online`。
4. 使用 `LERRO_SIGNING_MODE=developer-id ./script/verify_release.sh` 完成签名、公证、staple、Gatekeeper、独立解压、SBOM、manifest、checksum 与 fixture gate。notary profile 从已加载的本地维护配置取得。
5. 完成受影响的 T4/T5 人工矩阵并记录设备、系统、签名模式和结果。
6. 先部署网站 changelog并公开复验，再运行 `./script/publish_cloudflare_release.sh` 推进 R2/D1 stable。
7. 按 `docs/handoff/README.md` 把 fresh allowlist export 同步到现有公开仓库工作树，扫描、审查、提交并 push `main`。
8. App 版本发布在公开 commit 创建 annotated tag，创建 GitHub Release，上传五项 canonical 资产并通过 API 读回 digest。
9. 等待 branch/tag CI 完成，复验官网、appcast、latest、immutable ZIP、GitHub latest 和真实 Sparkle N 到 N+1。

任一步失败时保留上一份 canonical 产物和 stable head，修复后从静止源重新生成受影响产物。

文档或 agent-only 改动只同步公开 `main` 并等待 CI；它们不递增 App 版本、不移动现有 tag、不创建新的 App Release。

## 交付格式

最终说明包含：

- 实际改动与用户可见结果。
- source/public commit 与工作树状态。
- focused/full tests 的精确命令和结果。
- bundle、签名、公证、架构、UUID、manifest 与 SHA-256，适用于本次边界时列出。
- fixture、真实 TCC/硬件、Cloudflare、GitHub、CI 和线上复验结果。
- 明确跳过的验证与原因。
- App 下载、网站 changelog、GitHub source/README/Release 链接，适用于本次交付时列出。
