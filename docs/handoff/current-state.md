# 当前状态

最后核验日期：2026-08-04（Asia/Shanghai）。动态事实每次接手都要用本地代码、CLI 和公开端点刷新。

## 当前公开版本

| 项目 | 当前值 |
| --- | --- |
| App version / build | `1.2.0` / `8` |
| Bundle ID | `app.lerro.mac` |
| 平台 | macOS 26.0+，Apple silicon arm64 |
| GitHub Release | `v1.2.0` |
| Release source commit | `0c7a7d17ddb2a0dc639f5a51d56b18cb29696e47` |
| 官网 | `https://lerroapp.com` |
| 中文官网 | `https://lerroapp.com/zh` |
| 更新日志 | `https://lerroapp.com/changelog`、`https://lerroapp.com/zh/changelog` |
| Sparkle feed | `https://updates.lerroapp.com/appcast/stable.xml` |
| 最新下载 | `https://updates.lerroapp.com/download/macos/latest` |
| 公开仓库 | `https://github.com/Ryan-yang125/lerro` |

`config/Info.plist`、线上 appcast、GitHub latest 与 release manifest 应保持一致。发生差异时停止发布并逐项核对 source、canonical ZIP、R2/D1 stable 和 GitHub assets。

## 最近完成状态

- v1.2.0 已完成 App、官网和 GitHub README 的英文/简体中文支持。
- canonical ZIP 已完成 Developer ID 签名、Apple 公证、staple、Gatekeeper、Sparkle Ed25519、独立解压、SBOM、manifest 与 checksum 验证。
- Cloudflare stable、GitHub tag/Release 和真实 Sparkle 1.1.1 → 1.2.0 安装链路已通过。
- 官网截图 hotfix 已部署为 Worker version `757e3efb-53b0-43cf-8e94-f179b67b2196`。
- public hotfix commit `cf9bd1abd6a4404d2e884e6c667dd944d43f036a` 在 CI run `30893659041` 中通过 Website 与 Build and test。此 handoff 文档同步后，public `main` 会继续前进；固定 App release tag 保持 `v1.2.0`。
- 私有工程树中的 `docs/releases/v1.2.0.md` 保存完整版本证据，并由 public allowlist 排除。

## 当前产品与权限边界

- Apple Speech 负责原生转写，Apple Translation 负责本地翻译。
- 原始 Dictate 零模型调用；Local MLX 与 BYOK API 为可选增强。
- App 界面支持英文与简体中文，界面语言独立于 Speech 和 Translation 语言。
- 公开权限面为 Microphone 与 Accessibility。
- 全局快捷键默认 Fn Dictate 与 Fn + Shift Translate，支持 toggle/hold；物理 Fn/Globe 拦截沿用 v1.1.1 的事件所有权实现。
- 数据默认保存在本机；原始音频默认关闭；无产品遥测。

## 当前真实边界

以下检查受设备、TCC、硬件、缓存或第三方账号状态影响，每次相关改动后重新执行：

- 麦克风、Speech 语言资源、输出音频恢复。
- 内置 Fn 与外接 Globe、系统 Emoji and Symbols 设置、Secure Input 与 event-tap reset。
- TextEdit、浏览器和其他编辑器中的 AX、剪贴板、当前焦点和选区交付。
- 多显示器、Space、HUD 与 Ask panel。
- 真实 MLX 缓存模型加载/生成，以及 BYOK Provider 调用。
- 真实旧版本到新版本的 Sparkle 检查、下载、安装和重启。

## 下一次迭代起点

- `CHANGELOG.md` 的 `[Unreleased]` 接收下一版内容。
- 文档、agent 或 CI-only 改动保持 App `1.2.0 (8)`，同步公开 `main` 并等待 CI。
- 新 App 版本递增 version/build，创建新的版本证据、站点 changelog、Cloudflare immutable key、GitHub tag 和 Release。
- 开始功能开发前读取用户当前需求和 git 状态；本文件不保存推测 backlog。

## 每次接手的刷新命令

```zsh
git status --short
git rev-parse HEAD
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' config/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' config/Info.plist
git ls-remote https://github.com/Ryan-yang125/lerro.git refs/heads/main refs/tags/v1.2.0
gh release view --repo Ryan-yang125/lerro --json tagName,publishedAt,url
curl --fail --silent --show-error https://updates.lerroapp.com/appcast/stable.xml
```

记录变化后更新本文件，固定版本的详细证据继续写入独立 release record。
