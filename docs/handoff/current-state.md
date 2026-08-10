# 当前状态

最后核验日期：2026-08-10（Asia/Shanghai）。动态事实每次接手都要用本地代码、CLI 和公开端点刷新。

## 当前公开版本

| 项目 | 当前值 |
| --- | --- |
| App version / build | `1.4.0` / `10` |
| Bundle ID | `app.lerro.mac` |
| 平台 | macOS 26.0+，Apple silicon arm64 |
| GitHub Release | `v1.4.0` |
| Release source commit | `368fbba9ce158b56da535e24dd60f5c780117bb1` |
| 官网 | `https://lerroapp.com` |
| 中文官网 | `https://lerroapp.com/zh` |
| 更新日志 | `https://lerroapp.com/changelog`、`https://lerroapp.com/zh/changelog` |
| Sparkle feed | `https://updates.lerroapp.com/appcast/stable.xml` |
| 最新下载 | `https://updates.lerroapp.com/download/macos/latest` |
| 公开仓库 | `https://github.com/Ryan-yang125/lerro` |

`config/Info.plist`、线上 appcast、GitHub latest 与 release manifest 应保持一致。发生差异时停止发布并逐项核对 source、canonical ZIP、R2/D1 stable 和 GitHub assets。

## 最近完成状态

- v1.4.0 已交付实时转写 HUD、六秒写入回执、焦点安全撤回、即时修正学习、历史处理回执和应用级安全语音发送。
- 347 个 Swift 测试、60 条场景化听写基准、真实 DeepSeek Provider smoke、本地化、网站、UI fixture、发布脚本与公开边界门禁已通过。
- canonical ZIP 已完成 Developer ID 签名、Apple 公证、staple、Gatekeeper、Sparkle Ed25519、独立解压、SBOM、manifest 与 checksum 验证。
- 官网 Worker version `f21de301-ebb8-45b6-9762-43a2b8b89290` 已部署；四条双语路由和 `www` 重定向已线上复验。
- Cloudflare stable generation 8 已切换到 v1.4.0 build 10；R2、D1、appcast、latest 与 immutable 下载均通过 canonical SHA-256 回读。
- public release commit `ef29c41ad2f0d01030d723135d1d45cbe610028c` 与 annotated tag object `358f68572963e2fc06ef3f6da90d6f85bf183364` 固定 v1.4.0 源码快照。
- GitHub Release `v1.4.0` 已成为 latest，五个资产的名称、字节数和 SHA-256 digest 与 canonical 文件一致。
- public `main` CI run `31392364637` 与 tag CI run `31392394102` 的 Website 和 Build and test 均通过。此 handoff 同步后，public `main` 会继续前进；固定 App release tag 保持 `v1.4.0`。
- 私有工程树中的 `docs/releases/v1.4.0.md` 保存完整版本证据，并由 public allowlist 排除。

## 当前产品与权限边界

- Apple Speech 负责原生转写，Apple Translation 负责本地翻译。
- 原始 Dictate 零模型调用；Local MLX 与 BYOK API 为可选增强。
- 应用语气按当前 Mac 应用选择并冻结到每次 capture；本地语音快捷语和应用级修正词条均可管理。
- HUD 在说话时显示目标应用与两行实时转写；交付后显示六秒回执，可安全撤回、修正或确认应用级语音发送。
- 历史记录保存处理路径、上下文类别、远程共享类别、阶段耗时和发送状态；修正保留 raw、processed、corrected 文本链路。
- App 界面支持英文与简体中文，界面语言独立于 Speech 和 Translation 语言。
- 公开权限面为 Microphone 与 Accessibility。
- 全局快捷键默认 Fn Dictate、Fn + Shift Translate 与 Fn Space Command，支持 toggle/hold；物理 Fn/Globe 拦截沿用 v1.1.1 的事件所有权实现。
- 数据默认保存在本机；原始音频默认关闭；无产品遥测。

## 当前真实边界

以下检查受设备、TCC、硬件、缓存或第三方账号状态影响，每次相关改动后重新执行：

- 麦克风、Speech 语言资源、输出音频恢复。
- 内置 Fn 与外接 Globe、系统 Emoji and Symbols 设置、Secure Input 与 event-tap reset。
- TextEdit、浏览器和其他编辑器中的 AX、剪贴板、当前焦点和选区交付。
- 多显示器、Space、HUD 与 Command panel。
- 真实 MLX 缓存模型加载/生成；发布时本机模型缓存为空。合成 DeepSeek Provider 生成与产品修复提示已通过。
- 真实旧版本到新版本的 Sparkle 检查、下载、安装和重启。

## 下一次迭代起点

- `CHANGELOG.md` 的 `[Unreleased]` 接收下一版内容。
- 文档、agent 或 CI-only 改动保持 App `1.4.0 (10)`，同步公开 `main` 并等待 CI。
- 新 App 版本递增 version/build，创建新的版本证据、站点 changelog、Cloudflare immutable key、GitHub tag 和 Release。
- 开始功能开发前读取用户当前需求和 git 状态；本文件不保存推测 backlog。

## 每次接手的刷新命令

```zsh
git status --short
git rev-parse HEAD
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' config/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' config/Info.plist
git ls-remote https://github.com/Ryan-yang125/lerro.git refs/heads/main refs/tags/v1.4.0
gh release view --repo Ryan-yang125/lerro --json tagName,publishedAt,url
curl --fail --silent --show-error https://updates.lerroapp.com/appcast/stable.xml
```

记录变化后更新本文件，固定版本的详细证据继续写入独立 release record。
