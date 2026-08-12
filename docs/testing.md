# 测试与验收

Lerro 的完成标准分为确定性自动化、真实 app bundle、视觉 fixture、受权限约束的实机链路和分发验证。每一层回答不同问题。

## 证明等级

| 等级 | 入口 | 能证明 | 不能证明 |
| --- | --- | --- | --- |
| T0 静态检查 | shell/plist/package describe | 脚本语法、声明格式、SwiftPM source 接线 | 运行时行为 |
| T1 自动测试 | `swift test` | Core 规则、仓库竞态、adapter 纯逻辑、AppSession 替身编排 | TCC、硬件、真实 AX/CGEventTap/MLX |
| T2 app bundle | `build_and_run.sh` | Release 编译、资源布局、arm64、dSYM、签名 | 完整产品路径 |
| T3 fixture | inert fixture + 截图 | 合成数据下的 UI 状态和布局 | 生产 adapter、权限和真实用户流程 |
| T4 Release 实机 | 独立解压的 Release `.app` | 麦克风、Speech、快捷键、AX、剪贴板、窗口和持久化 | Developer ID 公证，除非使用对应签名模式 |
| T5 模型/分发 | 真实模型 + Developer ID/notary | 模型下载生成、缓存、Gatekeeper 分发 | 仍需记录设备与网络条件 |

发布或核心链路完成声明必须说明达到哪些等级。

## 快速环境检查

在仓库根目录运行：

```zsh
git status --short
swift --version
xcode-select -p
xcrun metal --version
zsh -n script/*.sh script/*.zsh
plutil -lint \
  config/Info.plist \
  config/Lerro.entitlements \
  Sources/Lerro/Resources/PrivacyInfo.xcprivacy
swift package describe --type json
```

Metal 组件缺失时：

```zsh
xcodebuild -downloadComponent MetalToolchain
xcrun metal --version
```

## 自动测试

完整门禁：

```zsh
swift build
swift test
```

focused tests 示例：

```zsh
swift test --filter LerroCoreTests
swift test --filter LerroIntelligenceTests
swift test --filter LerroMacTests
swift test --filter LerroTests
```

身份与数据迁移的最窄门禁：

```zsh
swift test --filter ApplicationDataMigratorTests
swift test --filter AppSessionCoreFlowTests
swift test --filter CloudPromptComposerTests
swift test --filter OpenAICompatibleHTTPClientTests
swift test --filter IntelligenceSettingsDraftTests
swift test --filter LerroThemeAccessibilityTests
swift test --filter LerroPressFeedbackTests
swift test --filter DictionaryLearning
swift test --filter V16SystemAdapterTests
swift test --filter CaptureHUDVisualStateTests
swift test --filter OnboardingV16FlowTests
```

迁移 suite 覆盖整根同卷移动、模型 inode 保留、重复执行、lock、journal
恢复、receipt 更新、并存目录去重、独有 Audio 移动、冲突零变更和 recovery
report。AppSession suite 覆盖迁移后的登录项收尾与 app 回到前台后的两项权限刷新。

Swift Testing 的 filter 匹配当前生成的 test spec。筛选结果为空时运行 `swift test list` 查看完整名称，并把最终使用的筛选命令记录在交付说明中。

测试文件统一使用 `*Tests.swift` 命名。CI 会把 `Tests/**/*Tests.swift` 与 `swift package describe --type json` 中的 test target source 做集合比较，发现未接入 SwiftPM 的文件。

测试数量与 suite 数量从本次 `swift test` 输出读取，文档不维护固定计数。

### Vendor 下载栈测试

修改 `Vendor/swift-huggingface` 的缓存、下载、恢复或进度代码时运行：

```zsh
swift test --package-path Vendor/swift-huggingface --filter HubCacheTests
swift test --package-path Vendor/swift-huggingface --filter FileOperationsTests
swift test --package-path Vendor/swift-huggingface
```

`HubCacheTests` 对临时 source 的门禁包括：首次 blob 完整提交后消费、已有 blob 完整提交后消费、snapshot commit 故障时保留 source、ref commit 故障时保留 source。两项故障注入测试还要确认保留内容与原始下载一致。截断 blob 恢复测试预置较短的同 ETag blob，验证完整 staging 原子替换、snapshot 内容正确、source 最终消费且无 `.partial` 残留。

`FileOperationsTests` 还覆盖显式 destination fallback、`X-Linked-Size` 截断 cache 拦截、Apple task 安装前取消、取消错误归一和下载后 `tempURL` 全出口清理。注入 snapshot commit failure 后，`downloadFile(..., to:)` 仍返回指定路径，destination 内容与 HTTP payload 完全一致。

恢复测试覆盖 `<etag>.incomplete` 的 Range 合并、`<etag>.resume-data` 的安全路径，以及 runtime
checkpoint 恢复和停止清理。URLSession 真实 resume data 的生成、跨请求恢复和 app 重启后的
实际续传仍需要 Release 实机记录；服务端或系统拒绝 resume data 时会清除断点并完整重试。

更新 `Vendor/swift-transformers` 源码或任一 package manifest 时运行：

```zsh
swift test --package-path Vendor/swift-transformers
swift package show-dependencies --format json
```

依赖图必须只解析到仓库内的 `Vendor/swift-huggingface` 与 `Vendor/swift-transformers`。Swift 6.2 会选择 `swift-transformers/Package@swift-6.1.swift`；该文件与普通 `Package.swift` 需要同步维护。最后运行根包全量测试与 Release 门禁。

## 自动化覆盖地图

| 能力 | 主要测试 |
| --- | --- |
| legacy 文本清洗规则（生产模型链路已绕过） | [`TextPipelineTests.swift`](../Tests/LerroCoreTests/TextPipelineTests.swift) |
| local prompt 上下文、语言、glossary 范围 | [`PromptComposerTests.swift`](../Tests/LerroCoreTests/PromptComposerTests.swift) |
| remote 七例 prompt、原始 transcript、80/40 上下文、六类开关、最多 12 个匹配词典 | [`CloudPromptComposerTests.swift`](../Tests/LerroCoreTests/CloudPromptComposerTests.swift) |
| raw/local/remote 路由、原文保持、生成、流、空结果、错误传播、连接测试 | [`PipelineIntelligenceServiceTests.swift`](../Tests/LerroCoreTests/PipelineIntelligenceServiceTests.swift) |
| OpenAI-compatible URL、headers/body、DeepSeek thinking、SSE、连接测试、取消、响应大小、重定向与错误脱敏 | [`OpenAICompatibleHTTPClientTests.swift`](../Tests/LerroIntelligenceTests/OpenAICompatibleHTTPClientTests.swift) |
| 模型下载进度边界与单调性、暂停 checkpoint、停止清理、公开下载无凭据、显式启用的真实缓存模型生成 | [`MLXLanguageModelRuntimeTests.swift`](../Tests/LerroIntelligenceTests/MLXLanguageModelRuntimeTests.swift) |
| 设备内存/磁盘/平台建议与 API 配置就绪策略 | [`LocalAIReadinessTests.swift`](../Tests/LerroCoreTests/LocalAIReadinessTests.swift) |
| Hub progress、已有 partial 的 Range 合并、取消、temp cleanup、staged atomic blob、截断恢复、metadata 失败保留 source、显式 destination fallback | [`FileOperationsTests.swift`](../Vendor/swift-huggingface/Tests/HuggingFaceTests/HubTests/FileOperationsTests.swift)、[`HubCacheTests.swift`](../Vendor/swift-huggingface/Tests/HuggingFaceTests/HubTests/HubCacheTests.swift) |
| 偏好 raw 默认、AI 排序、自动词典开启条件、Quick Dictate 默认关闭、remote 配置、模型与录音 | [`UserPreferencesTests.swift`](../Tests/LerroCoreTests/UserPreferencesTests.swift)、[`IntelligenceProviderModelsTests.swift`](../Tests/LerroCoreTests/IntelligenceProviderModelsTests.swift) |
| AI 修正分类、严格 JSON 0–3 条、source containment、置信度、专名接受与语义编辑拒绝 | [`PipelineIntelligenceServiceTests.swift`](../Tests/LerroCoreTests/PipelineIntelligenceServiceTests.swift) |
| JSON 历史分页、查询、snapshot 缓存、多实例文件协调、紧凑格式兼容、词典、偏好 `0600`、竞态和 retention | [`FileRepositoriesTests.swift`](../Tests/LerroCoreTests/FileRepositoriesTests.swift) |
| CSV 基本导入与错误 | [`SettingsAndPersistenceLogicTests.swift`](../Tests/LerroCoreTests/SettingsAndPersistenceLogicTests.swift) |
| 音频 buffer、转换、CAF 写入 | [`AudioLifecycleTests.swift`](../Tests/LerroMacTests/AudioLifecycleTests.swift) |
| 麦克风测试 session 隔离 | [`MicrophoneLevelTesterTests.swift`](../Tests/LerroMacTests/MicrophoneLevelTesterTests.swift) |
| 被动 HUD 的 key/main window 能力、非激活交互区域与主 actor 更新 | [`FloatingPanelControllerTests.swift`](../Tests/LerroMacTests/FloatingPanelControllerTests.swift) |
| secure capture context、应用/元素/value/selection/secure state 严格校验、Command-V commit、提交前取消、剪贴板多 item/type 条件恢复与并发事务 | [`AccessibilityTextDelivererTests.swift`](../Tests/LerroMacTests/AccessibilityTextDelivererTests.swift) |
| 同字段 60 秒观察、800 ms debounce、最小 diff、唯一 delivered range、漂移/超时/secure quiet exit、恢复复制与应用 catalog | [`V16SystemAdapterTests.swift`](../Tests/LerroMacTests/V16SystemAdapterTests.swift) |
| Apple progressive Dictation、最多 100 个 app 相关 contextual strings、Quick Dictate 首声/静音/恢复/单次 endpoint | [`AppleSpeechServiceTests.swift`](../Tests/LerroMacTests/AppleSpeechServiceTests.swift) |
| 单修饰键 hold/toggle、Fn 前缀升级、精确 modifier、Fn 63/Globe 179 实体生命周期、重复 flags、key-only 与混合重排、keyboard-only `0x1C00` mask、reset drain、tap-disabled 完整重建与 stop generation、Secure Input watchdog、自产 Command-V 透传 | [`GlobalHotkeyMonitorTests.swift`](../Tests/LerroMacTests/GlobalHotkeyMonitorTests.swift) |
| 录制器自动开始、窗口级 modifier 事件、monitor 清理、peak chord、无效候选隔离、单修饰键、三键上限、日常输入保护与系统保留组合 | [`ShortcutRecorderPolicyTests.swift`](../Tests/LerroTests/ShortcutRecorderPolicyTests.swift) |
| 主窗口四级字号、tracking、1 pt 按下反馈、Reduce Motion 几何稳定性 | [`LerroPressFeedbackTests.swift`](../Tests/LerroTests/LerroPressFeedbackTests.swift) |
| Aqua、Dark Aqua 与高对比外观下的灰阶解析、正文对比度、边界强度、hover/selection 区分 | [`LerroThemeAccessibilityTests.swift`](../Tests/LerroTests/LerroThemeAccessibilityTests.swift) |
| 菜单栏图片分辨率与进程内缓存 | [`LerroMenuBarPresentationTests.swift`](../Tests/LerroTests/LerroMenuBarPresentationTests.swift) |
| 原始/remote/local 听写、实时 partial/final、Quick Dictate 开关、词典注入、严格写入、失败恢复、AI 自动学习、remote 快照、FIFO trigger、hold identity、toggle 竞态、模型回退、翻译、提交前取消与 stale result 隔离 | [`AppSessionCoreFlowTests.swift`](../Tests/LerroTests/AppSessionCoreFlowTests.swift) |
| HUD short/medium/long、单调扩宽、居中、两行、Reduce Motion、recovery 与 learned 状态 | [`CaptureHUDVisualStateTests.swift`](../Tests/LerroTests/CaptureHUDVisualStateTests.swift) |
| 八步操作型 Onboarding、Apple-only/remote/local 完成条件与 AI 顺序 | [`OnboardingV16FlowTests.swift`](../Tests/LerroTests/OnboardingV16FlowTests.swift) |
| Provider 表单校验、预设切换、view-local Key draft 与六项开关 | [`IntelligenceSettingsDraftTests.swift`](../Tests/LerroTests/IntelligenceSettingsDraftTests.swift) |

## 场景化听写基准

v1.3 固定基准位于
[`benchmarks/contextual-dictation-v1.3.json`](../benchmarks/contextual-dictation-v1.3.json)，
包含 Mail、Messages、Notes、Xcode 与 Terminal 的 60 条中文、英文和中英混合样例。
同一 v1.3 release line 保持语料不变，local、remote 与外部产品使用相同输入。

```zsh
python3 script/benchmark_contextual_dictation.py --validate
python3 script/test_contextual_benchmark.py
python3 script/benchmark_contextual_dictation.py \
  --results path/to/results.json \
  --output path/to/report.json
```

报告记录 exact match、文本相似度、受保护名称/数字/代码片段准确率、格式准确率，以及
端到端延迟 p50/p95。缺失或多余 case ID 会使评分失败。

## 真实缓存模型 smoke

[`MLXLanguageModelRuntimeTests.swift`](../Tests/LerroIntelligenceTests/MLXLanguageModelRuntimeTests.swift) 中的 `liveCachedModelSmoke` 默认处于 disabled。常规 `swift test`、CI 和 `verify_release.sh` 不会加载模型、执行生成或触发约 3.03 GB 下载。标准显式入口是 [`test_live_model.sh`](../script/test_live_model.sh)。

先完成 `verify_release.sh` 以准备 Release `default.metallib`，退出正在运行的 `Lerro` 以释放 MLX 内存。在用户已经授权真实模型验证、缓存目录包含目标模型且机器具备足够内存时运行：

```zsh
LERRO_LIVE_MODEL_CACHE="$HOME/Library/Application Support/app.lerro.mac/Models" \
LERRO_LIVE_MODEL_ID='mlx-community/Qwen3.5-4B-MLX-4bit' \
LERRO_LIVE_MODEL_OFFLINE=1 \
./script/test_live_model.sh
```

脚本先运行 `MLXLanguageModelRuntimeTests` 的确定性部分，定位测试 binary，为它临时链接 Release `default.metallib`，随后仅对 `liveCachedModelSmoke` 设置 `LERRO_LIVE_MODEL_SMOKE=1`。`LERRO_LIVE_MODEL_OFFLINE=1` 直接在内核网络禁用 sandbox 中运行已经编译好的 Swift Testing binary，避免 SwiftPM 的构建 sandbox 产生嵌套冲突。退出时会恢复或移除自己创建的 Metal symlink。调用者无需设置或导出 `LERRO_LIVE_MODEL_SMOKE`。

`LERRO_LIVE_MODEL_CACHE` 可以省略，默认值是 `ApplicationPaths.modelsDirectory` 对应路径。`LERRO_LIVE_MODEL_ID` 可以省略，此时测试使用 `mlx-community/Qwen3.5-4B-MLX-4bit`。Release Metal library 位于其他路径时显式设置 `LERRO_MLX_METALLIB`。离线模式下缓存缺失会立即失败；省略离线变量时，缓存缺少文件可能触发 Hugging Face 下载。公共 HubClient 始终使用空 bearer token。

通过条件：

- 加载指定模型并执行合成中文到英文的 translate 请求。
- 输出去除空白后仍有内容，disposition 为 `.insert`。
- 结果记录的模型 ID 与输入一致，runtime 最终状态为 `.loaded`。
- 测试日志出现 `LERRO_LIVE_MODEL_OUTPUT=` 前缀；只保留合成输入对应的有限输出。

交付记录需要写明实际命令、缓存路径类型、模型 ID、网络状态、耗时与结果。跳过时记录用户授权、缓存、硬件或时间边界中的具体原因。

## 真实 BYOK Provider smoke

[`OpenAICompatibleHTTPClientTests.swift`](../Tests/LerroIntelligenceTests/OpenAICompatibleHTTPClientTests.swift)
中的 `liveDeepSeekSmoke` 默认 disabled。获得明确授权并把 Key 写入被 git 忽略且权限为
`0600` 的 `.env.deepseek.local` 后运行。脚本也接受已经导出的 `DEEPSEEK_API_KEY`：

```zsh
./script/test_live_remote.sh
```

通过条件：产品 runtime 的固定连接测试成功；`deepseek-v4-flash` 返回非空合成结果；英文
自我修正句保留 Wednesday 并移除 Tuesday；生产七例 prompt 能整理带错别字、口头停顿和
重复确认的中文 Apple Speech 样本，并修复明显误词。输出只包含延迟与通过标记。测试
不得打印 API Key、Authorization header、请求 JSON 或真实用户上下文。

### CSV 当前契约

[`DictionaryCSVParser.swift`](../Sources/LerroCore/Services/DictionaryCSVParser.swift) 支持：

- UTF-8 BOM。
- 可选 `phrase,replacement` 表头。
- `phrase` 单列。
- 第一处分隔逗号后的全部内容作为 replacement。
- 空行和空 phrase 跳过，无有效词条时报告错误。

当前 parser 不实现 RFC 4180 引号、引号内逗号或转义双引号。测试和产品说明禁止声称已支持 quoted CSV。需要该能力时先扩展 parser 与覆盖测试。

## App bundle 门禁

Release bundle：

```zsh
./script/build_and_run.sh --release --no-launch

codesign --verify --deep --strict --verbose=2 dist/Lerro.app
codesign -dvvv --entitlements - dist/Lerro.app
lipo -archs dist/Lerro.app/Contents/MacOS/Lerro
xcrun dwarfdump --uuid dist/Lerro.app/Contents/MacOS/Lerro
xcrun dwarfdump --uuid dist/Lerro.app.dSYM
plutil -lint \
  dist/Lerro.app/Contents/Info.plist \
  dist/Lerro.app/Contents/Resources/PrivacyInfo.xcprivacy
```

`./script/build_and_run.sh --verify` 会先执行全量测试，再构建并启动 app，最后用 `pgrep` 确认进程存在。该命令只提供启动 smoke，不提供窗口和核心链路断言。

最终 ZIP 的统一复验命令为：

```zsh
./script/verify_release.sh
```

该命令会先运行 Brand Kit 确定性资产校验，再执行全量测试并调用
`package_release.sh`，随后验证 checksum、manifest、独立解压、arm64、binary/dSYM
UUID、资源、Metal library、签名、inert home fixture 与真实 HUD panel fixture。脚本缺失或失败时，Release 门禁未完成。
详见 [`release.md`](release.md)。

## Release 文本交付探针

本机 T4 验收可用一次性 UUID 参数启用文本交付探针。它把固定合成文本
`Lerro delivery probe 7F3C2A` 放入 `lastResult`，并只监听带该 UUID 的随机分布式通知。
通知调用生产 `AccessibilityContextService` 与 `AccessibilityTextDeliverer`，不会启动
麦克风、Speech 或模型，也不会写入历史或录音。每次进程只消费一次通知。

先用稳定 development identity 构建，再生成 UUID 并启动唯一探针实例：

```zsh
LERRO_SIGNING_MODE=development ./script/build_and_run.sh --release --no-launch

probe_token="$(/usr/bin/uuidgen)"
/usr/bin/pkill -x Lerro >/dev/null 2>&1 || true
/usr/bin/open -n "$PWD/dist/Lerro.app" \
  --args --lerro-delivery-probe-token "$probe_token"
```

确认 Lerro 启动后，在终端安排五秒后的单次通知，并在倒计时内把光标放入目标应用的
空白测试输入框：

```zsh
( /bin/sleep 5
  LERRO_DELIVERY_PROBE_TOKEN="$probe_token" /usr/bin/swift -e '
import Foundation

guard let token = ProcessInfo.processInfo.environment["LERRO_DELIVERY_PROBE_TOKEN"] else {
    exit(2)
}
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("app.lerro.mac.delivery-probe." + token),
    object: nil,
    deliverImmediately: true
)
' ) &
```

查看脱敏交付阶段：

```zsh
/usr/bin/log show --last 2m --info --style compact \
  --predicate 'process == "Lerro" AND subsystem == "app.lerro.mac" AND category == "text-delivery"'
```

通过条件：目标输入框出现一次完整固定文本；日志以 `delivery-complete stage=paste` 结束；
原剪贴板 item/type 指纹保持一致。此探针证明“已有文本 → 当前输入框”的真实 Release 边界。物理 Fn、麦克风、
Speech 与模型仍由各自的 T4/T5 行验证。另一个目标需要使用新 UUID 重新启动探针实例。
正式启动不传入 `--lerro-delivery-probe-token`。

## Fixture 与视觉测试

先构建 Debug app：

```zsh
./script/build_and_run.sh --debug --no-launch
/usr/bin/pkill -x Lerro >/dev/null 2>&1 || true
```

合成 Hub 数据：

```zsh
open -F -n \
  --env LERRO_FIXTURE_MODE=1 \
  dist/Lerro.app
```

双语视觉 fixture 使用同一份 inert 组合。`LERRO_FIXTURE_LANGUAGE` 只在
`LERRO_FIXTURE_MODE=1` 时覆盖界面语言，支持 `en` 与 `zh-Hans`：

```zsh
open -F -n --env LERRO_FIXTURE_MODE=1 --env LERRO_FIXTURE_LANGUAGE=en dist/Lerro.app
open -F -n --env LERRO_FIXTURE_MODE=1 --env LERRO_FIXTURE_LANGUAGE=zh-Hans dist/Lerro.app
```

该覆盖不写入 `preferences.json`。Speech 听写语言与翻译目标语言继续由各自设置决定。

Onboarding：

```zsh
open -F -n \
  --env LERRO_FIXTURE_MODE=1 \
  --env LERRO_FIXTURE_ONBOARDING=1 \
  dist/Lerro.app
```

Onboarding 的八个状态按 `OnboardingStep.allCases` 验收：`privacy`、`speech`、`ai`、
`shortcut`、`dictation`、`recovery`、`dictionary`、`tone`。每一步都需要对应操作结果解锁；
fixture process 使用 inert adapters，手动在页面内前进并保存逐步截图。

独立 HUD 示例：

```zsh
open -F -n \
  --env LERRO_FIXTURE_MODE=1 \
  --env LERRO_FIXTURE_PRESENTATION=hud-recording \
  --env LERRO_FIXTURE_PANEL_ONLY=1 \
  dist/Lerro.app
```

启动等待态使用同一 inert fixture：

```zsh
open -F -n \
  --env LERRO_FIXTURE_MODE=1 \
  --env LERRO_FIXTURE_PRESENTATION=hud-waiting \
  --env LERRO_FIXTURE_PANEL_ONLY=1 \
  dist/Lerro.app
```

V1.6 实时转写、失败恢复与自动学习提示：

```zsh
open -F -n --env LERRO_FIXTURE_MODE=1 --env LERRO_FIXTURE_PRESENTATION=hud-dictating --env LERRO_FIXTURE_PANEL_ONLY=1 dist/Lerro.app
open -F -n --env LERRO_FIXTURE_MODE=1 --env LERRO_FIXTURE_PRESENTATION=hud-recovery --env LERRO_FIXTURE_PANEL_ONLY=1 dist/Lerro.app
open -F -n --env LERRO_FIXTURE_MODE=1 --env LERRO_FIXTURE_PRESENTATION=hud-dictionary-learned --env LERRO_FIXTURE_PANEL_ONLY=1 dist/Lerro.app
```

fixture adapter 必须保持 inert。fixture 运行中出现系统权限提示、真实音频设备、真实 pasteboard 写入、用户历史或网络请求时，立即视为回归。

主窗口视觉契约：

- 在 1080×750 与 988×658 检查主窗口、Onboarding 和设置。
- 在 Aqua、Dark Aqua、Increase Contrast 与 Reduce Transparency 检查自适应黑白灰。
- 浅色正文层级为 `#292929`、`#5D5D5D`、`#9E9E9E`；必要的 12 pt 小字使用
  `#6B6B6B`。
- 字号只使用 24 / 14 / 13 / 12 pt，tracking 为 `-0.15`。
- 导航图标与圆角为 14 / 8 pt；卡片图标与圆角为 20 / 16 pt；主要 CTA 为 pill。
- hover 在 150 ms 内完成表面反馈；pointer-down 同帧下沉 1 pt；Reduce Motion 下
  取消位移并保留静态或透明度反馈。
- HUD 以居中动态布局为新基线：约 120–420 pt 单调扩宽、两行截断、对称按钮槽、
  processing 保持中心、成功隐藏、recovery/learned 后处理和 Reduce Motion fade。

视觉矩阵、Apple-native 设计规则和资产验证见
[`Brand/README.md`](../Brand/README.md) 与
[`brand-guidelines.md`](../Brand/guidelines/brand-guidelines.md)。

Logo、App Icon、菜单栏或公开模板变化时先执行：

```zsh
./Brand/scripts/generate-assets.sh
./Brand/scripts/verify-assets.sh
```

生成入口会同步 `Sources/Lerro/Resources/icon.icns` 和八个菜单栏 template PNG；验证入口
会检查完整 ICNS 表示层以及 Brand export 与运行时资源逐字节一致性。

## 变更到门禁的映射

| 改动 | Focused | 完整自动化 | 额外证明 |
| --- | --- | --- | --- |
| Core 模型、文本、prompt | 对应 Core suite | `swift test` | 边界样例 |
| JSON repository | FileRepositories | `swift test` | 分页边界、查询筛选、缓存 mutation、同路径多实例、旧格式读取、零写入 retention、临时目录重开与并发 |
| AppSession | LerroTests | `swift test` | Release 实机受影响流程 |
| Speech/Audio | Audio/Microphone suites | `swift test` | 真实设备成功、取消、失败、静音恢复 |
| AX validation / clipboard transaction | Accessibility suite | `swift test` | 原生 TextEditor、Chrome textarea、secure field、焦点切换、剪贴板多类型 |
| Global hotkey | GlobalHotkey + ShortcutRecorder suites | `swift test` | 内置/外接键盘的单修饰键、组合键、hold/toggle、吞键、Escape 与 tap reset |
| MLX | Intelligence suites | `swift test` | 用户授权后的真实下载、加载、生成、缓存 |
| Vendor Hub / Tokenizers | vendored HubCache/FileOperations tests | vendored packages + `swift test` | 单一本地依赖来源、显式缓存模型 smoke、Release LICENSE/UPSTREAM 非空且 byte-identical |
| 主窗口 UI / tokens | `LerroThemeAccessibilityTests` + `LerroPressFeedbackTests` | `swift test` | 尺寸与外观矩阵、fixture PNG、Release 窗口、HUD 基线对比 |
| Brand / App Icon / Menu Bar | `generate-assets.sh` + `verify-assets.sh` | `swift test` | 16/32/64 px 验证板 + Finder/Dock/真实状态栏 |
| Sparkle 更新器 | `AppExternalLinksTests`、`distribution/npm test` | `swift test`、`npm test` | Keychain 签名、公证 ZIP、公开 appcast、真实 N 到 N+1 安装 |
| 构建/签名/资源 | shell/plist | `swift test` | package + `verify_release.sh` |

## 真实 Release 人工矩阵

使用最终 ZIP 独立解压后的 app。开发阶段若需要稳定 TCC 身份，使用 development signing，并把 app 放在稳定路径。每项记录系统版本、app 版本/build、签名模式、目标应用和实际结果。

| 场景 | 操作 | 通过条件 |
| --- | --- | --- |
| 首次启动 | 启动 clean profile | 八步操作型引导出现；privacy、Speech、AI、shortcut、dictation、recovery 的状态准确；每步由真实操作解锁 |
| AI 引导分流 | 分别在 8 GB 与 16 GB+ Apple silicon 测试 clean profile | 选项顺序为 Apple、remote、local；展示芯片、内存、可用空间；受限设备推荐 API；设备信息保持本机进程内 |
| Apple-only Onboarding | 选择 Apple，完成权限、资源、麦克风、快捷键、真实写入和恢复复制 | recovery 完成后直接进入首页；manual dictionary 与 Apple contextual recognition 可用；AI 能力显示启用入口 |
| 本地模型后台下载 | Onboarding 启动下载，关闭页面后观察进度，再执行暂停、继续、停止和重启 | 下载在 app 运行时继续；暂停后字节不增长且重启可续；停止清理未完成断点并保留完整 blob；下载期间 Dictate 使用 Apple raw |
| Onboarding API 配置 | 引导内填写 Provider、Model、Key 与上下文开关，测试并保存 | 只发送固定合成消息；测试通过后才能保存启用；Key 存入 `0600` preferences；站点 origin 变化会清空旧 Key |
| 快捷键录制 | 在 Onboarding 与设置分别录入 Fn、Option、Command 和组合键；切换 hold/toggle 并重复按下 | keycap 在 down/up 时立即变化；候选保存；配置测试期间无麦克风、HUD、历史和文本交付；退出后全局触发恢复 |
| Fn 系统动作隔离 | 系统键盘设置选择“按下 Fn/Globe 键：显示表情与符号”；Lerro 退出时按一次作控制组；启动最终 Release app 后在 TextEdit 分别点按内置 Fn、外接 Globe，并连续执行两轮 | 控制组打开系统字符面板；Lerro 运行时每轮只触发配置 action，`CharacterPaletteIM` 不出现；第二轮仍可正常开始和完成；松开后普通输入与未配置系统 chord 正常 |
| 原始听写 hold | 选择 Apple raw，在 TextEdit 按住已配置键说话后松开 | 无模型下载或 API；Apple transcript 写入 capture 时绑定的 app/element/value/selection；completed history；成功后 HUD 立即消失 |
| Quick Dictate | 确认默认关闭，再开启开关，使用 toggle 说一句并保持自然静音 | 关闭时必须第二次按键；开启后首声前静音不结束，约 1.2 秒连续静音只完成一次；插入完成后 HUD 收起；环境噪声不产生空交付 |
| 居中实时预览 | 在 TextEdit 和浏览器普通文本框说短、中、长句，并等待 final revision | target app、transcript、waveform 居中；宽度从约 120 pt 单调增长到 420 pt；最多两行保留最新内容；processing 中心不变；Reduce Motion/Transparency/Contrast 与 VoiceOver 可用 |
| 严格写入成功 | toggle 开始、说话、再次 toggle；期间不切换 app/field 或编辑目标值 | 只写入一次；capture fingerprint 校验通过；原 pasteboard item/type 条件恢复；completed history；成功后无回执和后续框 |
| 写入失败恢复 | 结束录音前切换 app、输入框、选区或修改目标值 | Command-V 不提交；final text 自动在 clipboard；failed history 保留 final；恢复卡显示目标 app、再次复制、关闭；按钮不抢焦点 |
| 自动词典专名 | remote/local AI Dictate 写入“乐若”，在同一字段改为“Lerro”，等待 800 ms | 60 秒观察内 AI 接受专名；保存 app-scoped learned entry；提示可撤销；下一次 Apple Speech context 与 AI prompt 都命中 |
| 自动词典语义拒绝 | 把刚写入的“明天开会”改为“昨天开会”，再测试增删句和大段重写 | AI 返回零候选；词典无新条目；history/log 不保存 diff；观察继续或安静结束 |
| 自动词典边界 | 写入后切 app/field、进入 secure input、撤销 AX、等待超时或使用不支持 AX value 的编辑器 | 无远端分类请求、无词条、无错误弹窗；observer 安静结束 |
| 空转写 | 选择原始听写，保持静音后结束录音 | 进入 HUD-only empty transcription 失败状态；无主窗口 alert、Dock attention 和应用音效；无文本交付、无 completed history、`lastResult` 为空；无未索引 CAF |
| 本地 AI 听写 | 产品内确认模型，重复听写 | 模型状态可见；原始 transcript 进入模型；生成后插入；history `wasEnhanced` 正确 |
| API 配置 | 选择 Provider，填写 Key/Model，逐项切换上下文并测试连接，再保存启用 | 连接测试只发送合成消息；成功状态和延迟内联显示；重启后配置恢复；`preferences.json` 为 `0600`、根目录为 `0700` |
| API 听写 | 选择 API 模型完成一段带口头修正和列表的听写 | 请求使用 capture 时冻结的配置；模型结果插入当前光标；history `wasEnhanced` 正确；日志无 Key 和内容 |
| API Dictate 失败 | 使用无效配额或可控失败 endpoint 完成 Dictate | 原始 Apple Speech transcript 通过严格目标交付；Translate 与 tone preview 同类失败保留明确错误 |
| 清除 API Key | 设置页清除已保存 Key 后重启 | JSON 中 Key 为空；模式切换到原始听写；再次启用 API 需要重新填写 Key |
| 翻译 | 分别选择 remote/local AI，使用翻译快捷键说中文 | 输出目标语言；严格写入 capture 目标；translation history 正确；raw 模式提示启用 AI |
| 应用语气 | 个性化 Grid 搜索真实 app、选择并填写 tone、运行 preview 后保存 | 真实 icon/name/bundle 正确；remote/local preview 成功后保存；后续 AI Dictate 命中该 app tone |
| HUD 锁定 | hold 录音中通过 HUD 显式进入锁定，再次触发或点击完成 | 状态切换稳定；Speech 只停止一次 |
| Escape | listening、enhancing 分别取消 | 无交付、无 completed history、无幽灵录音、输出音量恢复 |
| 重复 toggle | enhancing/inserting 连续触发 | 处理中无二次 stop、无重复交付 |
| 安全输入框 | 在密码框启动听写 | 开始阶段 fail closed；无麦克风、无文本、无 clipboard 变化 |
| 焦点切换 | 普通听写录音后切换到另一 app 或输入框 | 新焦点不接收文本；final text 进入 clipboard；恢复卡出现；原目标也不被晚到结果修改 |
| 合成交付探针 | 对原生 TextEditor 与浏览器 textarea 发送固定探针 | 两者都通过 HID event stream clipboard transaction 成功；目标身份与前台状态正确；浏览器 DOM 值精确；原剪贴板 item/type 指纹保持一致 |
| 粘贴上次结果 | 预置文本、富文本和文件 pasteboard item | 交付成功；500ms 后恢复普通插入可读取的归档类型 |
| 录音 opt-in | 开启保存音频并完成听写 | 生成 CAF；history 只存相对文件名；导出可播放 |
| 音频删除 | 删除带 CAF 历史、修改 retention | 音频先删除，随后索引变化；失败时保留可恢复状态 |
| 重启恢复 | 修改设置、历史、词典后退出重启 | 数据与 UI 恢复；损坏偏好报告错误并保留原文件 |
| 多显示器/Space | 在不同显示器和全屏 Space 触发 HUD、recovery 与 learned toast | panel 跟随目标屏幕且不抢焦点；按钮可点击；中心和宽度更新稳定 |
| 登录启动 | 稳定路径安装后切换设置并登录 | SMAppService 状态与偏好一致；失败可回滚 |
| 模型缓存 | 首次下载后暂停并退出，重启后继续；完成后断网再次使用 | 断点状态恢复；继续下载复用可用 resume data；完整缓存识别正确；离线加载成功；闲置后释放内存 |
| Sparkle 主动检查 | 从 `/Applications` 启动上一公开版本，在 Home 或设置点“检查更新” | appcast 读取成功；可见新版本、版本号、发布日期与安装说明；断网时保留可恢复错误 |
| Sparkle 更新提示 | 从上一公开版本启动并等待静默探测 | 发现更新时左下角出现蓝色下载图标；没有弹出下载窗口；没有后台下载 ZIP |
| Sparkle 点击更新 | 点击蓝色下载图标并完成安装 | archive Ed25519 签名验证成功；重启为新 build；历史、偏好与权限身份保持可用 |
| 官网直连下载 | 从 `https://lerroapp.com` 点击下载，在独立目录解压并启动 | HTTPS 下载落到当前 stable ZIP；SHA-256 与 manifest 一致；Developer ID、staple 和 Gatekeeper 通过 |

真实模型下载和系统权限会产生网络、磁盘或 TCC 状态变化，必须由用户授权或在专用验收账户中执行。

## CI 边界

[CI](../.github/workflows/ci.yml) 当前执行：

1. toolchain 报告。
2. shell 语法。
3. Metal toolchain 准备。
4. 以 ad-hoc 模式运行 `verify_release.sh`；该脚本内部执行 test source discovery、全量测试、Release build、打包、独立解压、签名/资源/manifest/dSYM 校验和 inert fixture smoke。

CI 不设置 `LERRO_LIVE_MODEL_SMOKE=1` 或 `LERRO_LIVE_REMOTE_SMOKE=1`，因此真实 MLX 与第三方 Provider 调用继续位于显式验收边界。CI 也不拥有目标 Mac 的真实 TCC、麦克风、输入设备、用户剪贴板、模型下载授权、Provider Key 或 Developer ID/notary 凭据。Release 实机矩阵和分发门禁保留在本地或专用发布环境。

## 交付证据模板

```text
Commit / tree state:
Toolchain:
Focused tests:
Vendor baselines / upstream PR snapshot:
Vendored package tests:
Full swift test:
Release build:
Signing mode / identity:
App architecture:
Binary UUID / dSYM UUID:
Release manifest:
SHA256SUMS:
verify_release:
Fixture states:
Manual Release matrix rows:
Model download executed:
Live cached model smoke command / result:
TCC/hardware checks executed:
Remaining boundaries:
```

## 文档检查

内部 Markdown 链接检查：

```zsh
python3 - <<'PY'
import pathlib
import re
import urllib.parse

root = pathlib.Path.cwd().resolve()
files = [root / "AGENTS.md", *sorted((root / "docs").rglob("*.md"))]
missing = []
for source in files:
    text = source.read_text()
    for raw in re.findall(r"\[[^]]+\]\(([^)]+)\)", text):
        target = urllib.parse.unquote(raw.split("#", 1)[0])
        if not target or "://" in target or target.startswith("mailto:"):
            continue
        resolved = (source.parent / target).resolve()
        if not resolved.exists():
            missing.append(f"{source.relative_to(root)} -> {raw}")
if missing:
    raise SystemExit("Missing links:\n" + "\n".join(missing))
print(f"Checked {len(files)} Markdown files")
PY
```

交付前还要扫描仓库沟通约定中禁止的先否定后肯定对照句式，并人工复读结果；扫描表达式本身不要写进受扫描文档。
