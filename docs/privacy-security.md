# 隐私与安全边界

用户可读承诺位于 [`PRIVACY.md`](../PRIVACY.md) 和应用内
[`PrivacyPolicy.html`](../Sources/Lerro/Resources/PrivacyPolicy.html)。本文件记录工程约束、
失败策略与验收要求。

## 数据地图

| 数据 | 产生条件 | 默认 | 保存与删除 |
| --- | --- | --- | --- |
| Preferences | 首次启动或设置变化 | 本地 JSON | `preferences.json`，设置页更新；Key 可单独清除 |
| History | capture 完成或交付失败 | 按用户 retention | 应用内单条/批量删除；`never` 阻止新记录 |
| Audio | `saveAudio` 开启且 history 允许 | 关闭 | history 拥有相对路径；删除历史先删除音频 |
| Dictionary | 手动录入、CSV 或 AI 学习 | 手动可用；AI 学习偏好开启但只在 AI 模式运行 | 应用内编辑、撤销、删除、应用 scope/全局调整 |
| App tone | AI 用户保存真实预览 | 空 | 个性化页面编辑或删除 |
| Local model | 用户确认下载 | 缺失 | Models cache；停止清理断点，完整 blob 保留 |
| API configuration | 用户测试并保存 | 空 | plaintext `preferences.json`；清除 Key 回到 raw |
| Target fingerprint | capture 与写入 | 进程内 | session 结束即释放，不写入历史 |
| Correction diff | AI 自动学习观察 | 进程内 | 分类后释放；只保存合格 dictionary entry |

Application Support 根目录每次准备或迁移后收紧到 `0700`，preferences 文件每次读取或
原子替换后收紧到 `0600`。同一 macOS 用户身份下的软件仍可读取 plaintext API Key。

历史允许保存 raw/final 文本、route、model ID、context category presence、remote-sharing
category names、phase timing、状态和可选音频引用。历史排除 focused value、element fingerprint、
选区正文、附近文本和自动学习 diff。旧 Ask history 只保留本地解码与展示。

## 身份迁移

迁移在 repositories 和模型 runtime 初始化前执行：

- lock 防止两个新进程同时迁移；journal 支持崩溃重放；receipt 记录完成状态。
- 单一旧根通过同卷 staging/rename 推进；模型 inode 复用。
- 新旧根并存时完整预检；独有项移动，相同字节去重，冲突产生 recovery report 并保持原数据。
- receipt 提交前失败会回滚目录；组合根返回 inert adapters 并展示启动错误。
- lock、journal、receipt 与 recovery report 排除 transcript、词典内容、凭据和个人绝对路径。

完整边界见 [`identity.md`](identity.md)。

## 系统权限

| 权限 | 用途 |
| --- | --- |
| Microphone | 用户触发的 Dictate/Translate 与 onboarding 麦克风测试 |
| Accessibility | 全局快捷键、有限目标上下文、严格写入、失败保护与修正观察 |

Apple Speech authorization 与语言资源状态由 Speech framework 管理。Quick Dictate 使用同一
Speech session 的 `SpeechDetector`，默认关闭且不增加权限。

Onboarding 通过真实操作验证权限、语言资源、麦克风、快捷键、写入和恢复。用户可以随时在
系统设置撤销 TCC。撤销会取消活动 capture、停止 event tap，并让自动学习观察安静结束。

## 上下文最小化

`CapturedContext` 可以包含：

- application name、bundle identifier、PID 与 application kind；
- window title；
- caret 前最多 80、后最多 40 个 UTF-16 单元；
- 当前任务需要的 selected text，远端上限 4,096 字符；
- focused element/value/selection/secure state 的严格 delivery fingerprint；
- 最多 12 个 prompt dictionary match 与当前 app tone。

视图只展示必要状态。上下文开关按 capture 开始时冻结；用户在生成期间修改设置只影响下一次。
系统 prompt 把 transcript、上下文和词典声明为无权限数据，抵抗 prompt injection。

## 安全输入与严格目标

capture 开始时如果 `IsSecureEventInputEnabled()` 或 AX 元素属于安全输入，流程在录音前结束。
严格写入前重新确认：

1. secure input 关闭；
2. frontmost PID/bundle 与 capture 目标一致；
3. focused application 与 element fingerprint 一致；
4. role/subrole、完整 value 与 selected range/value 一致；
5. 剪贴板和 synthetic event transaction 可用。

任何漂移都会停止 Command-V，最终文本复制到剪贴板，failed history 保存最终文本，HUD 只显示
恢复卡。成功写入立即关闭 HUD。生产路径没有写入成功回执、Undo、语音修改、版本恢复、重新听写
或自动 Return。

## 剪贴板事务

严格事务步骤：

1. 快照 pasteboard 全部可读取 item/type data 与 change count。
2. 写入唯一 session marker、transient type 与最终文本。
3. 创建并发送带 Lerro source marker 的 Command-V down/up。
4. Command-V event pair 成为交付 commit point。
5. 等待 500 ms consumption window。
6. session 仍拥有临时内容时恢复快照；外部内容已出现时保留外部内容。

commit point 前取消阻止交付；commit point 后仍完成等待、按键释放与条件恢复。交付失败时
`PasteboardRecoveryTextCopier` 把最终文本写入剪贴板；“再次复制”重复该动作。

人工验收使用包含 plain text、rich text、image/file URL 的多 item pasteboard，并覆盖写入成功、
目标漂移、外部并发修改与恢复复制。

## 自动词典学习

AI 自动学习只观察成功写入的 AI Dictate：

- timeout 固定 60 秒，poll interval 100 ms，稳定 debounce 800 ms；
- 继续要求同一 frontmost app、focused element 与非 secure input；
- AX value 上限 65,536 UTF-16 单元；
- delivered text 在 baseline 中必须唯一；
- diff 必须与该 delivered range 相交；
- 本地算法只定位最小 original/corrected span，并截取前 80/后 40 上下文。

remote/local AI 接收这些 spans、bounded context、app name 和 optional bundle ID，并返回严格
JSON 0–3 candidates。候选 phrase 必须源自 original span，replacement 必须源自 corrected span，
confidence 必须在 0–1；保存阈值为 0.7。

允许学习姓名、品牌、术语、拼写、同音词、音译和混合语言专名。事实、日期、时间、语义、
语气、增删句、结构或大段重写返回空候选。额外字段、代码围栏、超量候选、来源不匹配或无效
confidence 会拒绝整个输出。

AI 未启用、新 capture、离开 app/field、secure input、AX unavailable、unsupported editor、
timeout 或 task cancellation 会安静停止。日志和 history 不写 span 或 AI 分类输出。合格条目默认
绑定当前 app，用户可以撤销通知、编辑、删除或提升为全局。

## Apple Speech 词典上下文

同一 `DictionaryEntry` 数据通过 `SpeechVocabularyTerm` 进入 Apple Speech。AppSession 只选择
当前应用相关的 non-snippet 条目，应用级优先于全局，并按 priority、use count、recency 排序。
Apple `AnalysisContext.contextualStrings[.general]` 单次最多 100 个去重 replacement/phrase。

词典同时进入 local/remote AI prompt、词典页面、CSV 和 scope 管理。Apple-only 用户可以手动
维护词典并获得 Speech contextual recognition。

## 音频生命周期

- `saveAudio` 默认 `false`。
- `historyRetention == .never` 禁止新 history 与 audio。
- 每次 capture 使用独立 CAF 相对路径；路径解析必须保持在 Audio 根内。
- 完成 history 成功保存后才拥有 audio；保存失败删除未拥有文件。
- 删除 history 先删除 audio，再移除索引。
- history index 成功读取后才允许清理孤儿 audio。
- cancel、stale generation 和 pre-persistence failure 清理当前 session 文件。

任何调整覆盖成功、取消、Speech 失败、交付失败、history 保存失败、删除失败和索引损坏。

## 网络边界

### Apple

macOS 可以下载 Speech language assets。Apple framework 接收音频流和最多 100 个 contextual
strings；行为继续受系统版本和 Apple 服务约束。生产代码不使用 Apple Translation。

### Hugging Face

显式同意后，本地模型从公开仓库下载。client 使用 `bearerToken: nil`。Hugging Face 接收 IP、
User-Agent、请求时间和模型文件请求；Lerro 不发送音频、transcript、AX context、dictionary、
prompt 或 Key。

### BYOK

用户启用 remote 后，Lerro 直接请求配置的 DeepSeek/OpenAI/Gemini/custom endpoint。连接测试
只发送固定合成消息。正常请求按已启用类别发送 transcript、应用、窗口、80/40 caret context、
task-required selection、最多 12 个 dictionary matches 和 app tone。

自动学习使用更窄 payload：original/corrected spans、80/40 nearby context、app name、optional
bundle ID。Provider 按自己的条款处理内容和连接/计费元数据。

remote runtime 使用 ephemeral URLSession、HTTPS 或 loopback HTTP、cross-origin redirect block、
response size cap 和 sanitized error。API Key 为 `preferences.json` plaintext；UI 与日志不回显完整值。

### 更新

Sparkle 在启动、每 24 小时和用户主动检查时访问 `updates.lerroapp.com`。Cloudflare 只保存公开
release archive 与版本、build、签名、长度、SHA、发布时间等元数据。更新服务不接收用户内容。
ZIP 安装前使用嵌入 Ed25519 key 验证。

## 本地模型授权

默认模型约 3.03 GB。首次下载前必须展示模型 ID、大小、license、网络和磁盘影响并获得明确确认。
Onboarding 读取 chip、Metal、RAM 和 free disk 形成本地建议；数据保持本机。

下载由 AppSession 持有并支持后台继续、pause、resume、stop 和 restart continuation。stop 只清理
incomplete file、resume data 和 checkpoint，完整 blob 保留。公共客户端不能继承本机 Hugging Face
CLI token。

真实模型 smoke 默认关闭；授权后使用 [`script/test_live_model.sh`](../script/test_live_model.sh)，
记录硬件、cache 来源、model ID、network mode 和结果，输出排除生成内容。

## 日志

允许记录：

- session/generation 的非内容标识；
- phase、duration、error category；
- model/download 状态与非秘密 model ID；
- permission state；
- delivery/recovery/observer 的 stage 与成功失败。

禁止记录：

- audio、transcript、selected/focused text、correction spans；
- prompt、model output、dictionary value、app window body；
- API Key、Authorization header、certificate identity、Team ID、notary value；
- email、invite code 和用户绝对路径。

新日志字段先完成 sample-value review 和 secret scan。

## Privacy manifest、Info.plist 与 entitlements

变更系统 API、权限、网络、日志、数据或 Required Reason API 时同步检查：

- [`PrivacyInfo.xcprivacy`](../Sources/Lerro/Resources/PrivacyInfo.xcprivacy)
- [`Info.plist`](../config/Info.plist)
- [`Lerro.entitlements`](../config/Lerro.entitlements)
- [`PRIVACY.md`](../PRIVACY.md)
- 应用内 [`PrivacyPolicy.html`](../Sources/Lerro/Resources/PrivacyPolicy.html)
- 自动测试、T4/T5 matrix 与 release notes

Release bundle 和最终 ZIP 独立解压后都要确认这些资源存在且内容匹配。

## Fixture 隔离

`LERRO_FIXTURE_MODE=1` 必须使用内存 repositories、规则化 intelligence 和 inert adapters。fixture
禁止访问真实 Application Support、TCC、麦克风、Speech asset、AX、CGEventTap、pasteboard、
login item、model cache 或 network。HUD recovery、dictionary learned、Onboarding 和 personalization
fixture 只使用合成数据。

## 删除与恢复

- History：先删除 owned audio，再删除索引。
- Dictionary：手动删除或撤销 learning toast；删除立即影响下一次 Speech/AI context。
- API Key：清除 plaintext 字段并切到 raw。
- Download stop：删除 incomplete、resume、checkpoint；保留 complete blob。
- Model cache：退出 app 后只删除目标 model directory。
- App bundle：删除 bundle 不会自动删除 Application Support。
- Backup：系统或手动备份可能包含 history、dictionary、audio、model 和 plaintext API Key。

## 隐私变更检查表

- [ ] `PRIVACY.md` 与应用内 HTML 描述当前行为。
- [ ] usage descriptions、entitlements、privacy manifest 与签名一致。
- [ ] secure field、strict target drift、clipboard recovery 和 observer quiet-exit 通过。
- [ ] remote normal/correction payload category test 通过。
- [ ] Apple Speech vocabulary 上限与 app scope test 通过。
- [ ] logs 与 public export 不含用户内容、Key、证书、Team ID 和个人路径。
- [ ] audio/history/dictionary/model 删除顺序与恢复策略通过。
- [ ] fixture 在 offline/inert 环境通过。
- [ ] Developer ID、notary、Gatekeeper 与在线 feed 验证记录完成。
