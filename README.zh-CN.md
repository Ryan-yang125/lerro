<p align="center">
  <img src="site/public/lerro-logo.svg" width="176" alt="Lerro">
</p>

<h1 align="center">把语音直接写进 Mac。</h1>

<p align="center">
  <a href="README.md">English</a> · 简体中文
</p>

<p align="center">
  按一下开始，说完再按一下。Lerro 用 macOS 26 原生 Apple Speech，<br>
  快速、准确地把语音写入当前光标。
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

按一下快捷键开始，说完再按一下，转写结果会直接写入当前 Mac App。你也可以改成按住说话、松开完成。

| 模式 | 能力 | 运行位置 |
| --- | --- | --- |
| **听写** | 语音 → 当前光标 | Mac 上的 Apple Speech |
| **翻译** | 语音 → 目标语言 → 当前光标 | Mac 上的 Apple Translation |
| **指令** | 处理选中文字，或结合当前应用上下文回答 | 可选本地 MLX 模型或自带 API |

Lerro 1.4 会在说话时显示目标应用与实时转写。写入后的六秒回执可在同一应用、输入框和内容保持不变时安全撤回或立即修正。免按住听写可以用 **“发送”** 或 **“send it”** 结束；Lerro 会先确认每个应用，再允许后续语音发送。应用语气、精确快捷语、按应用修正学习和默认使用 **Fn Space** 的指令继续保留。

![Lerro 快捷键设置](https://lerroapp.com/screenshots/zh/lerro-onboarding-shortcuts-light.png)

Lerro 会请求两项 macOS 权限：**麦克风**用于收音，**辅助功能**用于全局快捷键和文本交付。它会在收音前检查安全输入框。普通听写和翻译会在交付瞬间写入当前键盘焦点；改写会再次确认原始选区，再执行替换。

写入回执会绑定 Command-V 完成后观察到的进程、Bundle、输入框、完整输入值与安全输入状态；任何一项发生变化，撤回和语音发送都会停用。

## 默认保护你的内容

- **核心链路留在本机。** 原始听写使用 Apple Speech，翻译使用已安装的 Apple Translation 语言资源。语言资源准备完成后，两条链路可离线使用。
- **原始音频默认不保存。** 你可以选择保留历史；选择“永不保存”后，Lerro 不会写入新的历史和录音。
- **没有遥测。** Lerro 没有账号系统、订阅、广告 SDK、产品分析，也没有用于保存转写、提示词或回答的服务端。
- **网络边界清晰。** Apple 可能下载语言资源；Lerro 会检查已签名更新；可选 MLX 模型仅在你确认后下载；BYOK 请求直接发送到你配置的服务商。

完整的数据、权限、剪贴板、更新和服务商边界见[隐私政策](PRIVACY.md)。

![Lerro 设置](https://lerroapp.com/screenshots/zh/lerro-settings-light.png)

## 先用原生能力，需要时再加智能处理

核心听写和本机翻译无需账号，Lerro 不收取使用费。可选的 Qwen MLX 本地模型会在你确认后下载，约需 3.03 GB，用于在本机润色文字。你也可以配置自己的 OpenAI-compatible API 来使用云端处理。BYOK 只会发送转写文本和你开启的上下文字段；费用和隐私条款由所选服务商决定。

## 安装

1. [下载最新已签名、已通过 Apple 公证的版本](https://updates.lerroapp.com/download/macos/latest)。
2. 将 **Lerro.app** 移到“应用程序”。
3. 完成麦克风和辅助功能的引导授权。
4. 从听写开始；需要时再准备翻译语言资源、本地模型或 BYOK。

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
