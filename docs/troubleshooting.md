# 常见故障与排查

先运行最窄的只读检查，记录原始错误和环境。避免通过放宽安全检查、删除用户数据或重置全部 TCC 来掩盖根因。

## 通用采集

```zsh
git status --short
swift --version
xcodebuild -version
xcode-select -p
sw_vers
uname -m
zsh -n script/*.sh script/*.zsh
```

应用日志：

```zsh
./script/build_and_run.sh --logs
```

项目 subsystem：

```zsh
./script/build_and_run.sh --telemetry
```

日志不得复制 transcript、选区、focused text、prompt、回答或凭据到 issue/文档。

## 身份数据迁移安全停止

症状：启动页显示旧数据迁移错误，或共同父目录出现
`.lerro-data-migration-v1.recovery.json`。运行时会在 repositories 与 MLX
初始化前停止，旧根与新根保持可检查状态。

先做只读采集：

```zsh
support="$HOME/Library/Application Support"
ls -ld \
  "$support/com.ryanyang.typelessnative" \
  "$support/app.lerro.mac" \
  "$support"/.lerro-data-migration-v1.* 2>/dev/null
test -f "$support/.lerro-data-migration-v1.recovery.json" && \
  sed -n '1,200p' "$support/.lerro-data-migration-v1.recovery.json"
```

处理规则：

- 退出使用兼容迁移 Bundle ID 的旧构建，确认只有当前 Lerro 实例运行，再重新启动。
- 保留两个数据根、lock、journal、receipt、staging 与 recovery report；支持人员
  依据 report 中的相对路径判断冲突来源。
- journal 存在时由下次启动重放；过期 lock 由迁移器安全接管；receipt 存在后旧根
  再次出现会持续安全停止。
- 模型目录通过同卷 rename 移动；手工复制模型会增加磁盘占用并破坏 inode 验证证据。

涉及冲突文件的取舍、手工移动或删除前，先制作可恢复备份并获得用户明确确认。

## Metal compiler 缺失

症状：MLX Release build 报 Metal toolchain 或 `metal` 不可用。

检查与修复：

```zsh
xcrun metal --version
xcodebuild -downloadComponent MetalToolchain
xcrun metal --version
./script/build_and_run.sh --release --no-launch
```

确认 `xcode-select -p` 指向安装组件的 Xcode。

## 直接运行 executable 后资源或窗口异常

症状：无 Dock 图标、bundle identifier 警告、字体/模型 tokenizer 资源找不到、窗口未前置。

SwiftPM GUI 应用需要标准 `.app`。使用：

```zsh
./script/build_and_run.sh --debug
```

禁止把 `.build/.../Lerro` 裸 executable 当成产品启动方式。

## SwiftPM resource bundle 缺失

症状：SwiftTransformers、Crypto、MLX 等资源在 Debug 可用，Release app 中找不到。

检查：

```zsh
./script/build_and_run.sh --release --no-launch
find dist/Lerro.app/Contents/Resources \
  -maxdepth 1 -type d -name '*.bundle' -print | sort

find .build/out/Intermediates.noindex \
  -path '*/Release/*/DerivedSources/resource_bundle_accessor.swift' \
  -print
```

生成的 accessor 必须使用 `Bundle.main.resourceURL`。`.bundle` 保持在 `Contents/Resources`；app 根目录只能包含 `Contents`。修复组装脚本后重新签名，避免手工修改已签 app。

## SwiftPM 报 `swift-huggingface` identity 冲突

症状包含 `Conflicting identity for swift-huggingface`，依赖链同时列出仓库内 path 与 GitHub remote。常见原因是根 `Package.swift` 已切换到 Vendor，而 Swift 工具链选中的 `swift-transformers` variant manifest 仍声明远程 Hub 包。

检查：

```zsh
swift --version
rg -n 'swift-huggingface' \
  Package.swift \
  Vendor/swift-transformers/Package.swift \
  Vendor/swift-transformers/Package@swift-6.1.swift
swift package show-dependencies --format json
```

Swift 6.2 会读取 `Vendor/swift-transformers/Package@swift-6.1.swift`。普通 manifest 和 6.1 variant 都应通过 `path: "../swift-huggingface"` 指向相邻 Vendor；根包继续通过 `Vendor/swift-huggingface` 引用同一份源码。修复后重新运行 dependency graph、vendored tests 和根包 `swift test`，确认警告消失。禁止通过删除根包的直接 Hub 依赖来隐藏 identity 冲突，这会让 `LerroIntelligence` 失去明确的 patched package 来源。

## dSYM 缺失或 UUID 不一致

```zsh
./script/build_and_run.sh --release --no-launch
xcrun dwarfdump --uuid dist/Lerro.app/Contents/MacOS/Lerro
xcrun dwarfdump --uuid dist/Lerro.app.dSYM
lipo -archs dist/Lerro.app.dSYM/Contents/Resources/DWARF/Lerro
```

两个 UUID 必须相同，DWARF 必须是 arm64。失败通常来自复用旧 dSYM、错误配置目录或未同步 thin 操作。

## 签名模式解析失败

查看身份：

```zsh
security find-identity -v -p codesigning
```

显式构建示例：

```zsh
LERRO_SIGNING_MODE=ad-hoc \
LERRO_CODESIGN_IDENTITY=- \
./script/build_and_run.sh --release --no-launch
```

允许模式和 identity 组合见 [`release.md`](release.md)。常见原因：

- identity 前缀与模式不匹配。
- 证书过期、私钥缺失或 keychain 未解锁。
- Developer ID 打包缺少 `LERRO_NOTARY_PROFILE`。
- 非 Developer ID 模式带入 notary profile。

## codesign 失败

```zsh
codesign --verify --deep --strict --verbose=4 dist/Lerro.app
codesign -dvvv --entitlements - dist/Lerro.app
plutil -lint \
  dist/Lerro.app/Contents/Info.plist \
  dist/Lerro.app/Contents/Resources/PrivacyInfo.xcprivacy
```

签名后修改任何 `Contents` 文件都会破坏 seal。重新运行构建脚本完成资源组装和签名。

## Gatekeeper 拒绝

```zsh
spctl -a -vv dist/Lerro.app
xcrun stapler validate dist/Lerro.app
codesign -dvvv dist/Lerro.app
```

Gatekeeper 接受是 Developer ID + 公证流程的目标。ad-hoc 和 Apple Development 产物用于本机，不以离站分发接受为门禁。

## 打包提示 source tree changed

`package_release.sh` 会比较构建前后 source snapshot。并行 agent、格式化器、生成文件或编辑器保存都可能触发退出码 75。

处理：

1. 使用 `git status --short` 确认改动来源。
2. 等待并行写入结束。
3. 保留所有合法改动。
4. 从稳定工作树重新运行打包。

发布期间禁止启动会修改 source tree 的任务。

## `verify_release.sh` 失败

```zsh
./script/verify_release.sh
```

按失败阶段分类：

- tests：定位第一个真实测试失败。
- build：编译、Metal、resource accessor 或 dSYM。
- manifest/checksum：产物来自不同打包批次或被修改。
- unzip/layout：ZIP 结构或资源漏装。
- architecture/UUID：thin 或 dSYM 对应错误。
- signing：resolved mode、identity、seal 或 entitlements。
- fixture smoke：bundle launch、inert fixture 或窗口启动。
- notarization：profile、Developer ID、notary/staple/Gatekeeper。

保留失败输出。重新运行 `package_release.sh` 前确认 canonical 产物是否仍是上一份有效版本。

## 应用进程存在但窗口看不到

检查：

```zsh
/usr/bin/pgrep -fal Lerro
/usr/bin/open -n dist/Lerro.app
```

随后检查：

- `LerroApp` 的 singleton main Window。
- AppDelegate 的 activation policy 与 activate 调用。
- `showInDock` 偏好是否切换到 accessory。
- 窗口是否位于其他 Space 或显示器。
- fixture 是否使用 panel-only presentation。

`pgrep` 只证明进程状态。

## 权限已经勾选，应用仍报告未授权

常见原因：

- app 路径或签名身份发生变化。
- 当前运行的是旧 bundle。
- 系统设置尚未刷新进程状态。
- Input Monitoring event tap 创建失败。

检查：

```zsh
codesign -dvvv dist/Lerro.app
plutil -p dist/Lerro.app/Contents/Info.plist
/usr/bin/pgrep -fal Lerro
```

使用稳定路径和 Apple Development 签名做重复 TCC 测试。系统设置中的开关已经打开且应用仍报告未授权时，按以下顺序迁移授权身份：

1. 用 `codesign -dvvv` 确认当前 Release app 的 Apple Development 签名，并确认实际启动路径与计划长期使用的路径一致。
2. 退出当前运行的 `Lerro`。
3. 打开“系统设置 → 隐私与安全性 → 辅助功能”和“输入监控”，删除名称为 **Lerro** 的旧条目。旧条目可能绑定了旧签名身份或旧 app 路径。
4. 从稳定路径启动当前 Apple Development 签名的 `Lerro.app`，由应用重新请求 Accessibility 和 Input Monitoring。
5. 打开新出现的 **Lerro** 条目，退出并重新启动 `Lerro`，再刷新应用内权限状态。

需要重置单项 TCC 时由用户明确确认，并且只针对 bundle ID `app.lerro.mac` 和目标服务；禁止执行全局重置。

## SpeechTranscriber 不可用或语言资源失败

症状可能包括系统版本不支持、locale 不支持、资源下载失败或无输入格式。

检查：

- `sw_vers` 确认为 macOS 26.0+。
- 设置中的识别语言与系统 Speech 支持一致。
- 网络可支持首次 Apple 语言资源安装。
- 麦克风设备仍存在，sample rate 和 channel count 大于零。
- Speech 与麦克风 TCC 已授权。

日志与错误入口位于
[`AppleSpeechService.swift`](../Sources/LerroMac/Speech/AppleSpeechService.swift)。禁止通过跳过 locale/assets 检查继续分析。

## 麦克风切换失败

```zsh
system_profiler SPAudioDataType
```

在设置中刷新设备列表。已保存 UID 不存在时 AppSession 会回退默认设备并保存偏好。外接设备热插拔需要完成开始、停止、取消三种实机测试。

## 录音后系统声音仍保持静音

这是核心资源恢复故障，优先级高。

复现并分别检查：

- 正常完成。
- Escape 取消。
- Speech 启动失败。
- analyzer 运行中失败。
- 空转写。

相关代码：

- [`CoreAudioHardware.swift`](../Sources/LerroMac/Audio/CoreAudioHardware.swift)
- [`AppleSpeechService.swift`](../Sources/LerroMac/Speech/AppleSpeechService.swift)

确保所有出口调用 `restoreOutputAudioIfNeeded()`，并且快照只恢复原设备的原 mute 值。

## 单修饰键或组合快捷键无响应

先在 Onboarding 或设置中打开录制器。录制器准备完成后会直接显示“按键检测中”，并通过
当前窗口的 AppKit local event monitor 读取修饰键；暂停检测按钮会恢复 Tab/Return 导航。
这一步可以单独验证键盘是否向 macOS 送出目标事件。

全局快捷键依赖 Input Monitoring、Accessibility 和生产 event tap。检查运行日志：

```zsh
./script/build_and_run.sh --logs
```

随后验证：

- 在快捷键录制器中按下目标键，确认 keycap 的 pressed/released 状态实时变化；按钮持有
  first responder 时仍应收到事件。
- Fn、Control、Option、Shift、Command 单键的 `flagsChanged`。
- Fn + Shift 与 Fn + Space 的 exact-modifier 匹配，包括 Fn 已保持超过 120 ms 后再补按第二个键。
- hold 的 down → began → up → ended。
- toggle 的第一次点按开始与第二次点按完成。
- 命中普通键的 down、repeat 与 up 全部被吞掉，常用系统 chord 保持透传。
- Escape。
- event tap timeout 后自动 re-enable。

快捷键使用统一的数据驱动匹配器，modifier 集合必须精确相等。单修饰键在 120 ms
意图确认窗口内遇到另一个键时取消候选，使 Command-C 等系统 chord 保持原行为。
录制器拒绝单独字母、数字、空格、重音符、超过三键的组合和已知系统保留组合。

如果按下能启动、松开无法结束，检查权限刷新是否重复重建 event tap。相同 definitions
的 `update` 与重复 `start` 必须保持幂等，并保留已经收到的 key-down 状态。

如果文本交付时自定义 Command-V 类快捷键被意外触发，检查 `eventSourceUserData` marker。
Lerro 自产粘贴事件必须透传，物理按键继续按配置匹配。Secure Input 结束后还需对账当前
modifier 与已 claim key state，确保 physical drain 可以退出。watchdog 先完成对账后仍要
保留 recovery generation；左右 Shift/Command/Option/Control 的局部 release 依据具体
keyCode 物理状态继续 drain。

如果权限刷新发生在 hold capture 中，确认 AppSession 先取消 capture，再停止 event tap。
Accessibility 与 Input Monitoring 必须同时可用才启动监听。

## 热键产生重复 stop 或幽灵录音

检查 `AppSession` 的 `isStartingCapture`、`captureGeneration`、`activeSession` 和阶段分支。自动测试入口：

```zsh
swift test --filter LerroTests
```

必须覆盖 Speech start 挂起时取消、程序化启动期快捷键、cleaning 期间 toggle 奇偶与显式
cancel、删除 definition 后的旧队列事件、enhancing 时取消、处理中重复 toggle 和 idle
cancel。

## Ask 结束录音后立即崩溃

先查看崩溃前的 AppKit 统一日志。若出现 `canBecomeKeyWindow`、`canBecomeMainWindow` 或
`NSInternalInconsistencyException`，检查 [`FloatingPanelController`](../Sources/LerroMac/Panels/FloatingPanelController.swift)：

- interactive Ask panel 必须显式允许成为 key window。
- Ask panel 保持 `canBecomeMain == false`，只调用 `makeKeyAndOrderFront`。
- 被动 HUD 保持不可成为 key/main window。
- Timer 回调通过 `Task { @MainActor in ... }` 更新面板，避免使用同步 executor 假设。

最窄自动验证：

```zsh
swift test --filter FloatingPanelControllerTests
LERRO_FIXTURE_MODE=1 LERRO_FIXTURE_PRESENTATION=ask \
  dist/Lerro.app/Contents/MacOS/Lerro
```

最终 Release 门禁会从独立解压的 App 各运行一次 home 与 Ask fixture；两者都必须持续存活，
保持零 TCP socket，并且日志中没有系统集成错误或崩溃标记。

## 文本写入错误应用

记录 Command-V 提交瞬间的前台 app 与键盘焦点，内容使用合成文本。

检查：

- 处理期间是否主动切换了应用或输入框。
- HUD 与 Ask panel 是否保持非激活窗口语义。
- `delivery-complete stage=paste mode=current-focus` 是否出现。
- 选区改写时 PID/bundle 与 selected text 是否一致。

自动测试：

```zsh
swift test --filter LerroMacTests
swift test --filter LerroTests
```

普通插入遵循当前键盘焦点；选区改写继续使用捕获目标绑定。

## 转写成功但当前输入框没有文本

先确认失败历史已经保存最终文本，再只观察脱敏交付日志：

```zsh
/usr/bin/log stream --info --style compact \
  --predicate 'process == "Lerro" AND subsystem == "app.lerro.mac" AND category == "text-delivery"'
```

日志只包含策略、bundle、PID/bundle 是否匹配、AX element 可用性、安全状态、模式和阶段，
禁止加入 transcript、focused text 或 selected text。

- 没有 `delivery-start`：`AppSession` 尚未调用交付器，先检查 result disposition、session generation 和取消状态。
- `delivery-failed stage=privacy`：捕获上下文是安全输入。
- `delivery-failed stage=target`：只属于 `.replaceSelection`，检查 `delivery-target observed`、PID/bundle、focused element 与原选区。
- 普通 `.insert` 即使 `element=false` 或选区状态为 `unavailable` 也会继续走 current-focus paste。
- `delivery-failed stage=paste`：普通插入检查 pasteboard 写入与事件创建；Rewrite 还要检查临时内容所有权和条件恢复。
- `delivery-complete stage=paste mode=current-focus`：普通插入的 Command-V 已提交到当前键盘焦点；目标控件中的固定探针文本提供消费证据。

用 [`testing.md`](testing.md#release-文本交付探针) 的固定合成探针分离物理 Fn、麦克风、
Speech、模型与文本交付。原生 TextEditor 与浏览器 textarea 分别验证 AppKit 和 Chromium 的 clipboard transaction。测试期间只插入固定探针文本，并记录目标应用、签名模式、
完成阶段与剪贴板指纹。

## 剪贴板未恢复

普通插入在 500ms 后恢复 best-effort 归档，期间产生的新剪贴板内容会被归档覆盖。Rewrite 只在仍拥有 session marker、change count、唯一临时 item、transient type 和文本时恢复；期间发生用户修改会保留新剪贴板。

若无并发修改仍未恢复：

- 普通插入检查 best-effort archive 与 500ms completion。
- Rewrite 检查 snapshot 是否保存全部 item/type data，以及 marker 是否写入。
- 检查 Command-V 失败路径是否执行对应恢复。
- 使用多 item 和富文本 fixture 复现。

## 模型一直下载、加载失败或无输出

检查：

- 产品内模型授权已确认。
- `~/Library/Application Support/app.lerro.mac/Models` 可写且磁盘空间足够。
- Hugging Face 可访问。
- 当前模型标识与缓存 marker 一致。
- `xcrun metal --version` 可用。
- 日志 category `model-cache`。

应用固定无 bearer token，禁止读取或复制用户 Hugging Face 凭据排障。

空输出行为：Dictate 使用 Apple Speech 原始 transcript；translate、rewrite、answer 返回错误。该契约由
[`PipelineIntelligenceServiceTests.swift`](../Tests/LerroCoreTests/PipelineIntelligenceServiceTests.swift) 维护。

## 模型下载进度停滞、回退或临时文件累积

Apple 平台下载进度由 vendored `swift-huggingface` 承担。当前 Vendor 基于 `0.9.0`，导入了 [上游 PR #50](https://github.com/huggingface/swift-huggingface/pull/50) 的进度修复，并针对 [Issue #52](https://github.com/huggingface/swift-huggingface/issues/52) 增加 `consumeSource` 临时文件生命周期补丁。

先确认当前构建真正使用本地 Vendor：

```zsh
swift package show-dependencies --format json
rg -n 'hfAsyncDownload|consumeSource' \
  Vendor/swift-huggingface/Sources/HuggingFace/Hub
```

随后运行最窄回归：

```zsh
swift test --package-path Vendor/swift-huggingface --filter HubCacheTests
swift test --package-path Vendor/swift-huggingface --filter FileOperationsTests
swift test --filter LerroIntelligenceTests
```

生命周期契约：URLSession 下载完成后，临时文件只在 Hub 提交路径使用 `consumeSource: true`。blob 安装在 blobs 目录使用唯一 `.partial` staging：同卷尝试 hard-link，链接失败时复制 source；校验 size 后原子 rename 或 replace 到最终 blob。随后提交 snapshot 和可选 ref，完整成功后删除临时源。调用者拥有的普通 source 使用默认 `false`。ETag-aware 与 generic 路径都为已持久化 `tempURL` 安装 scope cleanup，响应校验或 cache 发布失败也会在调用退出时清理。

同 ETag blob 的 size 与完整 source 不同时，安装器必须在 snapshot 发布前原子替换旧 blob，并验证最终 size。发现 `.partial` 长期残留、snapshot 指向截断内容或 source 在 metadata 完成前消失时，停止 Release 验收并运行 `HubCacheTests`。尺寸相同只证明长度一致，排障时继续核对 ETag、下载响应和模型加载错误。

`HubCache.storeFile` 的 snapshot 或 ref commit 报错时，传入 source 必须在该调用返回时保持内容不变。`HubClient` 随后可用它完成显式 destination fallback；下载调用最终退出时由 scope cleanup 清理 URLSession temp。cache 中可能已经存在完整 blob，ref 失败前也可能已经生成 snapshot，这些工件支持后续安全重试。

调用者提供显式 destination 时，snapshot commit failure 会让 cache lookup miss，`HubClient` 随后把保留的临时 payload 转移到 destination。若 destination 文件完整，下载调用可以成功返回，同时把 cache metadata 故障留给后续重试；cache-only 调用没有 destination 时继续返回 path resolution 错误。用 `FileOperationsTests` 的显式 destination fallback 用例区分 payload 交付与 cache 发布问题。

自动 Range 合并只覆盖调用开始前已有 `<etag>.incomplete` 的情况。首次网络中断或取消不会持久化 URLSession resume data，也不会自动生成供下一次调用使用的 `.incomplete`；跨请求或 app 重启后通常重新下载当前文件。排查时把该行为单独记录，避免把预置 partial 的自动测试当作首次中断续传证明。

只读检查应用模型目录中的未完成文件：

```zsh
model_cache="$HOME/Library/Application Support/app.lerro.mac/Models"
find "$model_cache" -type f \
  \( -name '*.incomplete' -o -name '*.tmp' -o -name '*.partial' \) \
  -print
```

进行检查前先确认路径属于 Lerro。用户未授权时保留现有模型缓存和未完成文件；排障记录只保存文件名、大小、mtime 和错误类型，避免收集其他目录内容。

## 真实缓存模型 smoke 被跳过或失败

常规测试看到 `liveCachedModelSmoke` disabled 属于预期行为。标准入口 [`test_live_model.sh`](../script/test_live_model.sh) 会检查缓存、Release `default.metallib` 和运行中的 `Lerro`，随后只对最终 focused test 设置启用变量：

```zsh
LERRO_LIVE_MODEL_CACHE="$HOME/Library/Application Support/app.lerro.mac/Models" \
LERRO_LIVE_MODEL_ID='mlx-community/Qwen3.5-4B-MLX-4bit' \
LERRO_LIVE_MODEL_OFFLINE=1 \
./script/test_live_model.sh
```

失败时依次核对：

- cache 路径是应用 `Models` 目录，目标模型文件完整；成功加载后 marker 与目标模型一致。
- `LERRO_LIVE_MODEL_ID` 与缓存模型一致；省略时使用默认 Qwen 模型。
- Metal toolchain、内存和磁盘满足真实 MLX 加载要求。
- `verify_release.sh` 已生成可读的 Release `default.metallib`；自定义路径通过 `LERRO_MLX_METALLIB` 传入。
- `Lerro` 已退出，模型内存已经释放。
- 离线模式会在已经编译好的 Swift Testing binary 上应用内核网络禁用规则；不要把整个 `swift test` 命令包进另一个 `sandbox-exec`。
- 缓存缺失文件时网络可访问 Hugging Face；下载客户端保持无 bearer token。
- 输出包含 `LERRO_LIVE_MODEL_OUTPUT=`，随后断言 runtime 为 `.loaded`。

真实 smoke 会加载模型并可能补充下载。只在用户授权或专用验收账户中执行；常规 CI 与 `verify_release.sh` 继续保持该环境变量未设置。调用者无需预先导出 `LERRO_LIVE_MODEL_SMOKE`。脚本退出后会恢复或移除自己创建的测试 Metal symlink。

## API 模型连接失败、认证失败或无输出

先在“设置 → 智能处理”确认 Provider、Model ID、Base URL 和 API Key，然后使用页面内
“测试连接”。该探针只发送固定合成消息。失败信息按认证、余额、模型、限流、服务、超时和
网络类别显示，并排除 Provider 响应正文。

检查：

- DeepSeek 预设为 `https://api.deepseek.com` 与 `deepseek-v4-flash`。
- OpenAI 和 Gemini 的 Model ID 已填写，且账户拥有目标模型权限。
- Custom URL 指向标准 Chat Completions base 或完整 `/chat/completions` endpoint。
- 公网 endpoint 使用 HTTPS；HTTP 只允许 localhost、`127.0.0.0/8` 或 `::1`。
- URL 没有 userinfo、query 或 fragment，重定向保持同 scheme/host/port。
- Provider 账户有可用余额、配额与网络访问。

确定性回归与显式真实 smoke：

```zsh
swift test --filter OpenAICompatibleHTTPClientTests
./script/test_live_remote.sh
```

`.env.deepseek.local` 保持 git ignored 与 `0600`。排障输出只记录错误类别、Provider、Model ID
和延迟；API Key、Authorization、请求 JSON、转写、工作区和 Provider 原始响应都不进入
终端、日志、issue 或支持邮件。

Dictate 的 API 错误按产品契约交付 Apple Speech 原文。Translate、Ask 和 Rewrite 显示
明确失败。若配置页连接成功而捕获仍失败，检查 capture 开始后 Provider 配置是否发生变化；
当前 session 使用开始时冻结的快照，新配置从下一次 capture 生效。

## JSON 数据损坏

先备份具体文件，禁止删除整个 Application Support 目录。

```zsh
data_root="$HOME/Library/Application Support/app.lerro.mac"
stat -f '%Sp %N' "$data_root" "$data_root/preferences.json"
plutil -lint "$data_root/preferences.json" 2>/dev/null || true
```

根目录应为 `drwx------`，preferences 应为 `-rw-------`。完整 pretty-print 会暴露明文 API
Key，排障时只做语法校验，或先在内存中将 `remoteProvider.apiKey` 替换为 `<redacted>` 再显示。
偏好损坏时应用使用安全默认值并保留原文件；历史索引损坏时停止孤儿音频清理。

## CSV 导入与预期不符

当前 parser 是轻量两列格式：可选 header，第一处分隔逗号前是 phrase，后面是 replacement。它不解析 RFC 4180 quoted fields 或转义双引号。

建议输入：

```csv
phrase,replacement
lerro,Lerro
code x,Codex
```

含 quoted comma 的数据需先转换为当前简单格式，或扩展 parser 和测试后再导入。

## Fixture 触发系统权限或真实 IO

这是 fixture 隔离回归。检查
[`AppDependencies.fixture()`](../Sources/Lerro/App/AppDependencies.swift) 是否全部为 inert adapters。fixture 中禁止出现：

- `AppleSpeechService`
- `AccessibilityContextService`
- `AccessibilityTextDeliverer`
- `GlobalHotkeyMonitor`
- `MacPermissionService`
- `MacLoginItemManager`
- 文件 repository 或 MLX runtime

修复后重新运行 fixture smoke，并确认 Application Support mtime、TCC、pasteboard 和网络无变化。

## 多个 Lerro 构建同时运行

```zsh
/usr/bin/pgrep -fal Lerro
```

确认每个 PID 的 app 路径和签名身份。完成记录后，可结束名称精确匹配的 Lerro
进程，再从本次验收的稳定路径启动唯一实例：

```zsh
/usr/bin/pkill -x Lerro >/dev/null 2>&1 || true
```

执行前确认命令只会命中本项目进程。迁移验收期间也要确认旧版和新版没有同时
监听全局 Fn。
