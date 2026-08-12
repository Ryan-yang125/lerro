<p align="center">
  <img src="site/public/lerro-logo.svg" width="176" alt="Lerro">
</p>

<h1 align="center">把语音直接写进 Mac。</h1>

<p align="center">
  <a href="README.md">English</a> · 简体中文
</p>

<p align="center">
  按一次快捷键开始，实时预览；再按一次，写入当前光标。Lerro 使用 macOS 26 原生 Apple Speech，<br>
  成功写入后立即结束，异常时自动保留到剪贴板。
</p>

<p align="center">
  <a href="https://updates.lerroapp.com/download/macos/latest"><strong>下载 macOS 版</strong></a>
  · <a href="https://lerroapp.com/zh">官网</a>
  · <a href="https://lerroapp.com/zh/changelog">更新日志</a>
</p>

<p align="center">
  Apple silicon · macOS 26+ · 无账号 · 无订阅
</p>

![Lerro 主界面](https://lerroapp.com/screenshots/zh/lerro-home-light.png)

## 一个快捷键，直接写入当前光标

按一次你设置的快捷键开始，HUD 会居中显示目标应用、实时转写与波形；再按一次完成并写入。Quick Dictate 是默认关闭的可选设置，开启后会在约 1.2 秒静音后自动完成。

| 模式 | 能力 | 运行位置 |
| --- | --- | --- |
| **听写** | 语音 → 当前光标 | Mac 上的 Apple Speech |
| **翻译** | 语音 → 目标语言 → 当前光标 | 已选择的远端或本地 AI |
| **智能润色** | 整理口语并匹配应用语气 | 已选择的远端或本地 AI |

Lerro 1.6 将正常路径收敛为“开始、预览、完成、写入”。写入成功后 HUD 立即消失；焦点或输入框发生变化时停止写入，最终文本进入剪贴板。启用 AI 后，Lerro 会观察刚写入文本的手动专名修正，通过 AI 判断后自动加入当前应用词典；语义改写不会进入词典。

![Lerro 快捷键设置](https://lerroapp.com/screenshots/zh/lerro-onboarding-shortcuts-light.png)

Lerro 会请求两项 macOS 权限：**麦克风**用于收音，**辅助功能**用于全局快捷键、严格目标写入和自动词典观察。它会在收音前检查安全输入框，并在写入前再次校验应用、输入元素、文本值、选区与安全状态。

写入失败时会显示恢复卡，文本持续保留在剪贴板，可再次复制或关闭。

## 默认保护你的内容

- **原始听写留在本机。** Apple Speech 完成语音转文字，并接收当前应用最相关的词典上下文。
- **原始音频默认不保存。** 你可以选择保留历史；选择“永不保存”后，Lerro 不会写入新的历史和录音。
- **没有遥测。** Lerro 没有账号系统、订阅、广告 SDK、产品分析，也没有用于保存转写、提示词或回答的服务端。
- **网络边界清晰。** Apple 可能下载语言资源；Lerro 会检查已签名更新；可选 MLX 模型仅在你确认后下载；BYOK 请求直接发送到你配置的服务商。

完整的数据、权限、剪贴板、更新和服务商边界见[隐私政策](PRIVACY.md)。

![Lerro 设置](https://lerroapp.com/screenshots/zh/lerro-settings-light.png)

## 先用原生能力，需要时再加智能处理

核心听写无需账号。可选的 Qwen MLX 本地模型会在你确认后下载，约需 3.03 GB，用于本机润色、自动词典学习、应用语气与翻译；下载支持后台继续、暂停、恢复、停止和重启续传。你也可以配置自己的 OpenAI-compatible API。BYOK 只会发送转写文本和你开启的上下文字段；费用和隐私条款由所选服务商决定。

## 安装

1. [下载最新已签名、已通过 Apple 公证的版本](https://updates.lerroapp.com/download/macos/latest)。
2. 将 **Lerro.app** 移到“应用程序”。
3. 完成麦克风和辅助功能的引导授权。
4. 按操作型引导完成第一次真实听写和失败恢复；AI 用户继续完成自动词典与应用语气。

系统要求：Apple silicon Mac 与 macOS 26 或更高版本。可选本地模型需要约 3.03 GB 存储空间。

## 开源与文档

Lerro 以 [Apache-2.0](LICENSE) 开源。产品、发布、隐私和工程文档均在本仓库：

- [架构](docs/architecture.md)
- [核心流程](docs/core-flow.md)
- [模型与 BYOK](docs/models.md)
- [隐私与安全](docs/privacy-security.md)
- [构建与测试](docs/build.md)
- [场景化听写基准](benchmarks/README.md)
- [参与贡献](CONTRIBUTING.md)

品牌与第三方声明见 [TRADEMARKS.md](TRADEMARKS.md)、[NOTICE](NOTICE) 和 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。第一方文档和截图采用 [CC BY 4.0](LICENSES/CC-BY-4.0.txt)。
