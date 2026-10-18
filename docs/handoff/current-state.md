# 当前状态

最后核验日期：2026-10-19（Asia/Shanghai）。动态事实每次接手都要用本地代码、CLI 和公开端点刷新。

## 当前公开版本

| 项目 | 当前值 |
| --- | --- |
| App version / build | `1.7.0` / `14` |
| Bundle ID | `app.lerro.mac` |
| 平台 | macOS 26.0+，Apple silicon arm64 |
| GitHub Release | [`v1.7.0`](https://github.com/Ryan-yang125/lerro/releases/tag/v1.7.0) |
| Package source commit | `f5c61b657386e2d912b23e3dc76a1d0d763db5ce` |
| Public source commit | `41b0bc99b9f910c966eb830ae4280a88361a033c`（tag `v1.7.0`） |
| 官网 | `https://lerroapp.com`（中文）、`https://lerroapp.com/en`（英文） |
| 更新日志 | `https://lerroapp.com/changelog`、`https://lerroapp.com/en/changelog` |
| Sparkle feed | `https://updates.lerroapp.com/appcast/stable.xml` |
| 最新下载 | `https://updates.lerroapp.com/download/macos/latest` |
| 不可变下载 | `https://updates.lerroapp.com/releases/1.7.0/14/Lerro-macOS-arm64.zip` |
| 公开仓库 | `https://github.com/Ryan-yang125/lerro` |

`config/Info.plist`、线上 appcast、GitHub latest 与 release manifest 当前一致。发生差异时停止发布，
逐项核对 package source、canonical ZIP、R2/D1 stable 和 GitHub assets。

## 最近完成状态

- v1.7.0 交付新品牌（光标 L、墨水蓝）、品牌 glyph、墨黑 HUD、品牌菜单栏面板、SpeechTranscriber 识别、
  先开麦的采集链路、输入法式 AI 润色提示词、词典建议、全局自动学习词条和 AI 用量页。
- 官网改为 Astro 静态站，由 Worker `lerro-site` 提供；中文在 `/`，英文在 `/en`，旧 `/zh` 路由 301 跳转。
  README 中英文重写，配图位于 `site/public/readme/`。
- 289 tests、30 suites 通过；网站 `astro check`、17 项 node 测试和 `npm audit` 通过。
- canonical ZIP 完成 Developer ID、Apple notarization、staple、Gatekeeper、Sparkle Ed25519、arm64、
  App/dSYM UUID、资源、独立解压、SBOM、manifest 与 checksum 验证。
- Cloudflare appcast、latest 和 immutable 1.7.0/14 ZIP 已上线，公开端点返回 11,667,630-byte canonical archive。
- GitHub Release `v1.7.0` 已上线，五项资产的名称、字节数和 digest 与 canonical 产物一致。
- 本版按维护者决定跳过真实 Release 人工矩阵、本地 MLX 模型 smoke 与 1.6.0 → 1.7.0 Sparkle 实机更新。
- 固定证据位于私有工程树 `docs/releases/v1.7.0.md`（不进入公开导出）。

## 当前产品与权限边界

- 主路径：快捷键开始 → 居中实时预览 → 同一快捷键结束 → 严格写入 → 成功 HUD 消失。
- Apple Speech（SpeechTranscriber）负责转写；词典不发给 Apple Speech，只进入 AI prompt。
- remote/local AI 提供 Dictate 润色、Translate、自动词典分类和应用语气。
- 写入前校验 capture app、input element、value、selection 与 secure state；漂移时 final text
  留在剪贴板并显示恢复卡。
- AI Dictate 成功写入后可在同 app/element 观察 60 秒；编辑稳定 800 ms 后本地提取最小差异，
  AI 返回 0–3 个结构化候选。
- 主导航为首页、历史、词典、应用语气；设置为独立 Settings 窗口（⌘,，通用 / 快捷键 / 智能 / 用量 / 隐私 / 关于）。词典支持 learned/manual/snippet、CSV、应用筛选、编辑、
  删除、撤销与提升全局。
- Onboarding 八步为隐私、Speech、AI、快捷键、真实听写、失败恢复、自动词典和应用语气。
- 本地模型约 3.03 GB，支持后台继续、暂停、恢复、停止和重启续传。
- Ask、Rewrite、成功回执、撤回、语音跟进修改、版本恢复、重新听写、语音发送和 Apple
  Translation 已退出生产路径；旧 Ask history 只读。
- 公开权限面为 Microphone、Speech Recognition 与 Accessibility。数据默认保存在本机，原始音频
  默认关闭，无产品遥测。

## 当前真实边界

以下项目受设备、TCC、硬件、缓存或第三方账号影响，每次相关改动后重新执行：

- 真实麦克风、Speech 语言资源、输出音频恢复。
- 内置 Fn、外接 Globe、自定义 Option/Command、Secure Input 与 event-tap reset。
- TextEdit、Notes、ChatGPT/浏览器、Electron 的严格写入、剪贴板恢复和自动词典观察。
- 浅色、深色、高对比度、Reduce Transparency、Reduce Motion、VoiceOver、多显示器和 Space。
- 真实 3.03 GB 模型下载、低内存设备建议、暂停/恢复/停止/重启续传与 MLX generation。
- 上一公开版本到 v1.7.0 的 Sparkle 检查、下载、安装和重启。
- 配置的 BYOK Provider 两条生成链路已通过；目标用户自己的 Provider、模型和额度仍需各自验证。

## 下一次迭代起点

- `CHANGELOG.md` 的 `[Unreleased]` 接收下一版内容。
- 文档、agent 或 CI-only 改动保持 App `1.7.0 (14)`，同步公开 `main` 并等待 CI。
- 新 App 版本递增 version/build，创建新版本证据、站点 changelog、Cloudflare immutable key、
  GitHub tag 和 Release。
- 开始功能开发前读取用户当前需求和 git 状态；本文件不保存推测 backlog。

## 每次接手的刷新命令

```zsh
git status --short
git rev-parse HEAD
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' config/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' config/Info.plist
git ls-remote https://github.com/Ryan-yang125/lerro.git refs/heads/main refs/tags/v1.7.0
gh release view v1.7.0 --repo Ryan-yang125/lerro --json tagName,publishedAt,url,assets
gh run list --repo Ryan-yang125/lerro --limit 3
curl --fail --silent --show-error https://updates.lerroapp.com/appcast/stable.xml
```

记录动态变化后更新本文件；固定版本证据继续写入独立 release record。
