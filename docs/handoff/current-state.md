# 当前状态

最后核验日期：2026-08-11（Asia/Shanghai）。动态事实每次接手都要用本地代码、CLI 和公开端点刷新。

## 当前公开版本

| 项目 | 当前值 |
| --- | --- |
| App version / build | `1.5.1` / `12` |
| Bundle ID | `app.lerro.mac` |
| 平台 | macOS 26.0+，Apple silicon arm64 |
| GitHub Release | `v1.5.1` |
| Release source commit | `213ced452c300753f52ea3e166f3002cd6f963f1` |
| 官网 | `https://lerroapp.com` |
| 中文官网 | `https://lerroapp.com/zh` |
| 更新日志 | `https://lerroapp.com/changelog`、`https://lerroapp.com/zh/changelog` |
| Sparkle feed | `https://updates.lerroapp.com/appcast/stable.xml` |
| 最新下载 | `https://updates.lerroapp.com/download/macos/latest` |
| 公开仓库 | `https://github.com/Ryan-yang125/lerro` |

`config/Info.plist`、线上 appcast、GitHub latest 与 release manifest 应保持一致。发生差异时停止发布并逐项核对 source、canonical ZIP、R2/D1 stable 和 GitHub assets。

## 最近完成状态

- v1.5.1 已交付设备感知 AI 建议、内嵌 API 配置、九步任务型 onboarding，以及本地模型下载的后台进度、暂停、重启恢复、继续和确认停止。
- 378 个 Swift 测试、60 条场景化听写基准、真实 BYOK Provider 2/2 smoke、本地化、网站、UI fixture、Vendor、发布脚本与公开边界门禁已通过。
- canonical ZIP 已完成 Developer ID 签名、Apple 公证、staple、Gatekeeper、Sparkle Ed25519、独立解压、SBOM、manifest 与 checksum 验证。
- 官网 Worker version `a7a0fa8b-41de-46a0-b378-d1e691ed7b2e` 已部署；四条双语路由已线上复验。
- Cloudflare stable generation 10、release ID `2e263551-e0b6-452a-9eba-a16988229d02` 已切换到 v1.5.1 build 12；R2、D1、appcast、latest 与 immutable 下载均通过 canonical SHA-256 回读。
- public release commit `adca55baaa669b9348aa132eb834e5e9da5b0f32` 与 annotated tag object `208cb71e6dad2b7e540f7cabc83b07217933838a` 固定 v1.5.1 源码快照。
- GitHub Release `v1.5.1` 已成为 latest，五个资产的名称、字节数和 SHA-256 digest 与 canonical 文件一致；GitHub ZIP 资产也已独立整包下载复验。
- public `main` CI run `31460500924` 与 tag CI run `31460519074` 的 Website、Build and test 与完整 Release artifact 均通过。
- 私有工程树中的 `docs/releases/v1.5.1.md` 和 `docs/releases/v1.3-v1.5-acceptance.md` 保存完整版本证据，并由 public allowlist 排除。

## 当前产品与权限边界

- Apple Speech 负责原生转写，Apple Translation 负责本地翻译。
- 首次启动由九步 onboarding 完成 AI、权限、快捷键、Quick Dictate、交付回执、语音跟进修改与完整工具箱教学；AI 页面根据 Apple silicon、Metal、内存和可用磁盘给出建议。
- 本地模型下载在用户确认约 3.03 GB 后开始，显示字节、速度和剩余时间；支持后台继续、暂停、重启恢复与确认停止。API 路径在 onboarding 内完成 Provider、Model、Base URL、API Key、连接测试和启用。
- Quick Dictate 只在相应 session 挂载 SpeechDetector；首句后连续静音约 1.2 秒自动完成，hold/toggle 继续使用原有转写行为。
- 原始 Dictate 零模型调用；Local MLX 与 BYOK API 为可选增强。
- 应用语气按当前 Mac 应用选择并冻结到每次 capture；本地语音快捷语和应用级修正词条均可管理。
- HUD 在说话时显示目标应用与两行实时转写；交付后显示六秒回执，可安全撤回、修正、继续语音编辑或确认应用级语音发送。
- 最近交付目标在内存中保留 60 秒；确定性语音指令支持恢复、删句、精确替换和重新听写，已授权模型支持缩短、扩写、语气、翻译和通用编辑。
- 历史记录保存处理路径、上下文类别、远程共享类别、阶段耗时和发送状态；每次跟进编辑追加父版本链。
- App 界面支持英文与简体中文，界面语言独立于 Speech 和 Translation 语言。
- 公开权限面为 Microphone 与 Accessibility。
- 全局快捷键默认 Fn Quick Dictate、Fn + Shift Translate 与 Fn Space Command；设置中继续提供 hold/toggle，物理 Fn/Globe 拦截沿用 v1.1.1 的事件所有权实现。
- 数据默认保存在本机；原始音频默认关闭；无产品遥测。

## 当前真实边界

以下检查受设备、TCC、硬件、缓存或第三方账号状态影响，每次相关改动后重新执行：

- 麦克风、Speech 语言资源、输出音频恢复。
- 内置 Fn 与外接 Globe、系统 Emoji and Symbols 设置、Secure Input 与 event-tap reset。
- TextEdit、浏览器和其他编辑器中的 AX、剪贴板、当前焦点和选区交付。
- 多显示器、Space、HUD 与 Command panel。
- 真实 3.03 GB 模型下载、8 GB 设备建议、暂停后重启续传与 MLX 缓存模型加载/生成；发布时本机模型缓存为 0B。配置的 BYOK Provider 两条生成链路已通过。
- 真实旧版本到新版本的 Sparkle 检查、下载、安装和重启。

## 下一次迭代起点

- `CHANGELOG.md` 的 `[Unreleased]` 接收下一版内容。
- 文档、agent 或 CI-only 改动保持 App `1.5.1 (12)`，同步公开 `main` 并等待 CI。
- 新 App 版本递增 version/build，创建新的版本证据、站点 changelog、Cloudflare immutable key、GitHub tag 和 Release。
- 开始功能开发前读取用户当前需求和 git 状态；本文件不保存推测 backlog。

## 每次接手的刷新命令

```zsh
git status --short
git rev-parse HEAD
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' config/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' config/Info.plist
git ls-remote https://github.com/Ryan-yang125/lerro.git refs/heads/main refs/tags/v1.5.1
gh release view --repo Ryan-yang125/lerro --json tagName,publishedAt,url
curl --fail --silent --show-error https://updates.lerroapp.com/appcast/stable.xml
```

记录变化后更新本文件，固定版本的详细证据继续写入独立 release record。
