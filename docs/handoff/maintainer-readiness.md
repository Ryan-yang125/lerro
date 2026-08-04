# 发布机就绪检查

本文件记录发布所需的能力、只读探针和恢复路径。凭据值始终保存在 Keychain、Wrangler 和 GitHub CLI 的凭据存储中。

## 本地维护配置

创建被 Git 忽略的配置：

```zsh
cp config/maintainer.env.example config/maintainer.local.env
chmod 600 config/maintainer.local.env
```

字段职责：

| 字段 | 内容 |
| --- | --- |
| `LERRO_NOTARY_PROFILE` | `notarytool` Keychain profile 标签 |
| `LERRO_SPARKLE_KEY_ACCOUNT` | Sparkle `sign_update` 读取的 Keychain account 标签 |
| `LERRO_PUBLIC_REPO_DIR` | 已存在且保留 GitHub 历史的公开仓库工作树绝对路径 |
| `LERRO_PUBLIC_REMOTE` | 官方公开 Git remote URL |

该文件可以被 agent source。日志和最终交付只报告“可用/不可用”，避免打印具体标签与绝对路径。

## 一键只读探针

```zsh
source config/maintainer.local.env

# 工具、配置、签名类别、Keychain account、公开工作树
./script/check_maintainer_readiness.sh

# 同时要求 source/public 工作树干净
./script/check_maintainer_readiness.sh --release

# 增加 Apple、Cloudflare、GitHub 和公开端点网络检查
./script/check_maintainer_readiness.sh --online

# 正式发布前的完整 readiness
./script/check_maintainer_readiness.sh --release --online
```

探针只读。它不会构建、签名、上传、部署、推进 stable、提交或 push。

## 能力清单

| 能力 | 就绪证据 | 失败处理 |
| --- | --- | --- |
| Swift/Xcode/Metal | CLI 可用，SDK 与 `Package.swift` 匹配 | 切换 Xcode；安装 Metal Toolchain |
| Node/npm | Node 22+，`site/node_modules/.bin/wrangler` 存在 | `cd site && npm ci` |
| Development signing | Keychain 有有效 Apple Development identity | 在 Xcode/Developer account 恢复证书 |
| Developer ID signing | Keychain 有有效 Developer ID Application identity | 导入受控证书与私钥 |
| Notary | profile 标签已配置，`notarytool history` 可读 | 用维护者 Apple 凭据重新 store-credentials |
| Sparkle signing | Keychain account 可读，最终 ZIP manifest 有 Ed25519 signature | 恢复同一 update key；禁止换 key 后直接推进旧客户端渠道 |
| Cloudflare | 私有 `distribution/wrangler.toml`、Wrangler 登录、正确账户 | 从模板恢复 binding；核对账号后再部署 |
| GitHub | `gh auth status` 通过，公开工作树 remote 指向官方仓库 | 恢复 CLI 登录或 remote |
| 公开端点 | 官网、changelog、appcast 可读 | 检查 Worker route、D1 stable 与 DNS |

## 私有文件边界

- `config/maintainer.local.env`：非秘密标签与本地路径；ignored。
- `distribution/wrangler.toml`：D1/R2 资源标识；ignored，public export 明确排除。
- `.env.deepseek.local`：可选 BYOK smoke；`0600`，ignored。
- `outputs/`、`dist/`：本次 canonical 构建产物；ignored。
- `work/`：发布记录、临时 public notes 和已存在的公开工作树；ignored。

Skill、文档和脚本只能引用模板变量。公开扫描拒绝本机绝对路径、assigned profile、证书详情、Team ID、token 和 private key。

## 发布前人工确认

readiness 全部通过后仍需确认：

1. 用户要求发布的版本与改动范围。
2. version/build、CHANGELOG、站点双语 changelog 和验收记录一致。
3. source tree 已提交并静止。
4. 本版受影响的 T4/T5 项目已经安排目标设备或明确记录为剩余边界。
5. 当前 stable 与 public GitHub release 的版本基线准确。

遇到凭据或账号故障时停止公开动作，保留现有 canonical 产物与 stable head。
