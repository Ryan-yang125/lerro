# Release、签名与产物验证

真实 Release 由三个层次组成：标准 `.app`、可分发 ZIP 与可追溯证据。构建和发布逻辑以
[`build_and_run.sh`](../script/build_and_run.sh)、
[`signing_support.zsh`](../script/signing_support.zsh) 和
[`package_release.sh`](../script/package_release.sh) 为准；统一复验入口是
[`verify_release.sh`](../script/verify_release.sh)，真实缓存模型入口是
[`test_live_model.sh`](../script/test_live_model.sh)。

## 发布产物

`package_release.sh` 成功后应生成：

```text
dist/Lerro.app
dist/Lerro.app.dSYM
outputs/Lerro-macOS-arm64.zip
outputs/Lerro-macOS-arm64.dSYM.zip
outputs/Lerro-macOS-arm64.cdx.json
outputs/Lerro-release-manifest.json
outputs/SHA256SUMS.txt
```

`Lerro-macOS-arm64.cdx.json` 是本次 release 的 CycloneDX JSON SBOM；它从本次
`Package.resolved` 锁定图和第三方许可证证据生成。ZIP、dSYM ZIP 与 SBOM 都属于可再生产物，
通常由 `.gitignore` 排除。manifest 与 checksum 是否纳入版本控制由发布策略决定；它们必须与同一次打包生成的二进制一致。

## 前置条件

```zsh
swift --version
xcodebuild -version
xcode-select -p
xcrun metal --version
zsh -n script/*.sh script/*.zsh
plutil -lint \
  config/Info.plist \
  config/Lerro.entitlements \
  Sources/Lerro/Resources/PrivacyInfo.xcprivacy
```

Metal toolchain 缺失时：

```zsh
xcodebuild -downloadComponent MetalToolchain
xcrun metal --version
```

发布前记录工作树：

```zsh
git status --short
git rev-parse HEAD
```

打包脚本允许 dirty tree，并把状态、HEAD、tree、文件内容摘要写入 release manifest。构建期间任何 source tree 变化都会触发退出码 75。Release 证据需要可复现时，使用已提交且静止的工作树。

### Vendor 依赖前置检查

模型下载栈使用两个本地包。发布前确认来源记录、许可证和实际依赖图：

```zsh
test -f Vendor/swift-huggingface/UPSTREAM.md
test -f Vendor/swift-huggingface/LICENSE
test -f Vendor/swift-transformers/UPSTREAM.md
test -f Vendor/swift-transformers/LICENSE
rg -n 'swift-huggingface' \
  Vendor/swift-transformers/Package.swift \
  Vendor/swift-transformers/Package@swift-6.1.swift
swift package show-dependencies --format json
```

通过条件：根包、`swift-transformers` 和当前 Swift 工具链实际选择的 manifest 都解析到仓库内的 `Vendor/swift-huggingface`；输出中没有 conflicting identity 警告。来源基线以两个 `UPSTREAM.md` 为准。上游 [PR #50](https://github.com/huggingface/swift-huggingface/pull/50) 与临时文件 [Issue #52](https://github.com/huggingface/swift-huggingface/issues/52) 的状态会变化，发布记录需要附带复核日期与链接。

## 签名模式

`LERRO_SIGNING_MODE` 支持四个值，解析规则由
[`signing_support.zsh`](../script/signing_support.zsh) 实现。

| 模式 | 身份 | 用途 | Hardened Runtime | Timestamp / Notary |
| --- | --- | --- | --- | --- |
| `auto` | 显式 identity 优先；随后尝试 Apple Development；最终回退 ad-hoc | 本机默认 | 取决于解析结果 | 取决于解析结果 |
| `ad-hoc` | `-` | 单机自用和无证书构建 | 当前脚本不添加 runtime option | 无 timestamp，无公证 |
| `development` | `Apple Development: ...` | 本机开发、稳定签名和 TCC 实机验收 | 开启 | 无 timestamp，无公证 |
| `developer-id` | `Developer ID Application: ...` | 离站分发 | 开启 | timestamp + 必须公证 |

查看本机有效身份：

```zsh
security find-identity -v -p codesigning
```

显式 identity 必须存在于当前 keychain 且前缀与模式匹配。脚本会在构建前拒绝以下组合：

- development 配 Developer ID identity。
- developer-id 配 Apple Development identity。
- ad-hoc 配非 `-` identity。
- developer-id 缺少 notary profile。
- 非 developer-id 模式携带 notary profile。

### 本机 ad-hoc

```zsh
LERRO_SIGNING_MODE=ad-hoc \
LERRO_CODESIGN_IDENTITY=- \
./script/package_release.sh
```

### Apple Development

自动选择第一个有效 Apple Development identity：

```zsh
LERRO_SIGNING_MODE=development \
./script/package_release.sh
```

显式选择：

```zsh
LERRO_SIGNING_MODE=development \
LERRO_CODESIGN_IDENTITY='Apple Development: NAME (TEAMID)' \
./script/package_release.sh
```

Development signing 适合在固定 app 路径进行真实权限回归。TCC 仍由用户授权，签名只提供更稳定的代码身份。

### Developer ID 与公证

先在 keychain 创建 `notarytool` profile，再运行：

```zsh
LERRO_SIGNING_MODE=developer-id \
LERRO_CODESIGN_IDENTITY='Developer ID Application: NAME (TEAMID)' \
LERRO_NOTARY_PROFILE='<notarytool-profile>' \
./script/package_release.sh
```

脚本流程：

1. 生成临时 source snapshot。
2. 使用同一 resolved signing mode 构建 Release app 与 dSYM，通过 compiler prefix map 清除源码路径，并在 dSYM 生成后剥离 app binary 的调试与本地符号。
3. 验证构建前后 source snapshot 一致。
4. 校验 app、plist 和隐私清单。
5. Developer ID 分支先提交 pending ZIP 公证。
6. staple app，再运行 codesign 与 Gatekeeper 检查。
7. 重新创建最终 app ZIP，并创建 dSYM ZIP。
8. 生成 release manifest 和 checksum。
9. 所有 pending 文件完成后原子替换 canonical 产物。

`verify_release.sh` 会按原始字节扫描最终 app binary；出现当前构建用户 Home 路径时立即失败，避免公开产物携带本机绝对路径。公开 ZIP 使用 `--norsrc`，并拒绝 `__MACOSX` AppleDouble 元数据条目。

失败发生在原子替换前，上一份 canonical 产物继续保留。

## 构建真实 `.app`

只生成 Release app，不启动：

```zsh
./script/build_and_run.sh --release --no-launch
```

显式模式可传递给同一入口：

```zsh
LERRO_SIGNING_MODE=development \
./script/build_and_run.sh --release --no-launch
```

脚本验证：

- SwiftBuild app-aware resource accessor。
- app 根目录只有 `Contents`。
- executable 为 arm64。
- dSYM DWARF 为 arm64。
- executable UUID 与 dSYM UUID 一致。
- Info.plist 与 entitlements 格式。
- 深度严格 codesign。

## Bundle 内容

标准布局：

```text
Lerro.app/
└── Contents/
    ├── Info.plist
    ├── MacOS/Lerro
    ├── Resources/
    │   ├── *.bundle
    │   ├── PrivacyInfo.xcprivacy
    │   ├── PrivacyPolicy.html
    │   ├── TermsOfUse.html
    │   ├── ThirdPartyLicenses/
    │   └── icon.icns
    └── _CodeSignature/
```

SwiftPM dependency bundles 的实际集合随依赖图变化。发布验证应比较 SwiftBuild binary directory 与 `Contents/Resources` 中的 `.bundle` 集合，避免只维护固定名称。

## 本地结构验证

```zsh
app=dist/Lerro.app
binary="$app/Contents/MacOS/Lerro"
dsym=dist/Lerro.app.dSYM

test -x "$binary"
test "$(lipo -archs "$binary")" = arm64
test "$(lipo -archs "$dsym/Contents/Resources/DWARF/Lerro")" = arm64
codesign --verify --deep --strict --verbose=2 "$app"
codesign -dvvv --entitlements - "$app"
plutil -lint \
  "$app/Contents/Info.plist" \
  "$app/Contents/Resources/PrivacyInfo.xcprivacy"
xcrun dwarfdump --uuid "$binary"
xcrun dwarfdump --uuid "$dsym"

test -f "$app/Contents/Resources/PrivacyPolicy.html"
test -f "$app/Contents/Resources/TermsOfUse.html"
test -d "$app/Contents/Resources/ThirdPartyLicenses"
test -s "$app/Contents/Resources/ThirdPartyLicenses/swift-huggingface-LICENSE"
test -s "$app/Contents/Resources/ThirdPartyLicenses/swift-huggingface-UPSTREAM.md"
test -s "$app/Contents/Resources/ThirdPartyLicenses/swift-transformers-LICENSE"
test -s "$app/Contents/Resources/ThirdPartyLicenses/swift-transformers-UPSTREAM.md"
cmp -s \
  Vendor/swift-huggingface/LICENSE \
  "$app/Contents/Resources/ThirdPartyLicenses/swift-huggingface-LICENSE"
cmp -s \
  Vendor/swift-huggingface/UPSTREAM.md \
  "$app/Contents/Resources/ThirdPartyLicenses/swift-huggingface-UPSTREAM.md"
cmp -s \
  Vendor/swift-transformers/LICENSE \
  "$app/Contents/Resources/ThirdPartyLicenses/swift-transformers-LICENSE"
cmp -s \
  Vendor/swift-transformers/UPSTREAM.md \
  "$app/Contents/Resources/ThirdPartyLicenses/swift-transformers-UPSTREAM.md"
```

## 打包与统一复验

生成全部产物：

```zsh
./script/package_release.sh
```

验证 checksum：

```zsh
(cd outputs && shasum -a 256 -c SHA256SUMS.txt)
```

最终统一命令：

```zsh
./script/verify_release.sh
```

`verify_release.sh` 的契约：

- 检查 shell、plist、Brand Kit 确定性资产和 SwiftPM test source discovery。
- 校验 Brand ICNS、菜单栏导出与 `Sources/Lerro/Resources` 逐字节一致。
- 运行全量 `swift test` 并调用 `package_release.sh` 生成当前产物。
- 读取 `outputs/Lerro-release-manifest.json`。
- 生成并校验 `outputs/Lerro-macOS-arm64.cdx.json`：CycloneDX 格式、
  `Package.resolved` 锁定图、已解析依赖身份、Vendor 来源记录和许可证证据必须一致。
- 校验 `SHA256SUMS.txt` 中 app ZIP、dSYM ZIP、SBOM 和 manifest。
- 解压到 `mktemp -d` 创建的隔离目录。
- 验证 app 根布局、Info.plist、PrivacyInfo、资源、许可证和 executable。
- 验证本地 Vendor 的 `swift-huggingface` 与 `swift-transformers` 许可证及来源记录非空，并与仓库源文件 byte-identical。
- 验证 MLX `default.metallib` 存在、可读且文件类型有效。
- 验证 app 与 dSYM 都是 arm64，UUID 与 manifest 一致。
- 验证 binary、package resolution、entitlements 和产物 hash 与 manifest 一致。
- 运行严格 codesign。
- 按 manifest signing mode 检查 ad-hoc、development 或 Developer ID 身份。
- manifest 标记 notarized 时运行 `spctl` 与 `stapler validate`。
- 启动 inert fixture，确认精确 PID 存活、无 TCP、日志无 CoreAudio/TCC 错误，再精确清理该 PID。
- 清理自己创建的临时目录。

该脚本缺失、未执行或失败时，发布状态保持未验收。手工命令可用于诊断，最终记录仍以统一复验命令为准。脚本默认不设置 `LERRO_LIVE_MODEL_SMOKE`，因此统一复验不包含真实模型加载和生成。

## Release manifest

manifest 是本次打包的机器可读证据，包含：

- 创建时间与 source snapshot。
- HEAD、HEAD tree、dirty 状态和 working tree 内容摘要。
- app 名称、bundle ID、版本、build、最低系统、架构。
- executable hash、binary UUID、dSYM UUID 和 resource bundles。
- requested/resolved signing mode、identity、authority、Team ID、CDHash、designated requirement、公证状态。
- Swift、Xcode、Metal 版本和 `Package.resolved` hash。
- app ZIP、dSYM ZIP、CycloneDX SBOM 的文件名、hash 和字节数，以及公开 Developer ID ZIP 的 Sparkle Ed25519 签名和长度。

文档或人工记录中的产物信息应引用 manifest，避免手动复制后与新产物漂移。

## 独立启动 smoke

结构复验完成后，从隔离目录或最终安装路径启动：

```zsh
/usr/bin/open -n /absolute/path/to/Lerro.app
/usr/bin/pgrep -x Lerro
```

进程存在只证明 launch smoke。真实核心功能按照
[`testing.md`](testing.md) 的 Release 人工矩阵验收。

## 真实缓存模型 Release smoke

模型下载栈、MLX 加载和生成需要单独的 T5 证据。先运行 `verify_release.sh`，退出正在运行的 `Lerro`，再由用户授权 [`test_live_model.sh`](../script/test_live_model.sh) 使用同一模型缓存：

```zsh
LERRO_LIVE_MODEL_CACHE="$HOME/Library/Application Support/app.lerro.mac/Models" \
LERRO_LIVE_MODEL_ID='mlx-community/Qwen3.5-4B-MLX-4bit' \
LERRO_LIVE_MODEL_OFFLINE=1 \
./script/test_live_model.sh
```

脚本会为测试 binary 临时链接 Release `default.metallib`，在最终 focused test 中设置 `LERRO_LIVE_MODEL_SMOKE=1`，退出时清理该链接。离线模式使用内核规则禁用网络，缓存不完整时直接失败。发布记录必须包含模型 ID、缓存目录类型、网络条件、测试输出与最终 runtime 状态。完整通过条件见 [`testing.md`](testing.md#真实缓存模型-smoke)。跳过该 smoke 时，Release 结构与签名门禁仍可完成，模型核心链路在交付记录中保持人工未验收。

## 真实 BYOK Provider Release smoke

获得 Provider 调用授权后，在 `0600` 的本地 `.env.deepseek.local` 中提供
`DEEPSEEK_API_KEY`，并运行：

```zsh
./script/test_live_remote.sh
```

该入口使用产品 OpenAI-compatible runtime 完成固定连接探针、英文自我修正生成和生产七例
prompt 的中文噪声转写整理。发布记录
保存 Provider、Model ID、延迟、合成输出结论和网络条件，排除 API Key、Authorization、
请求 JSON 与真实用户上下文。完整通过条件见
[`testing.md`](testing.md#真实-byok-provider-smoke)。

## Gatekeeper

Developer ID 公证产物：

```zsh
codesign --verify --deep --strict --verbose=2 dist/Lerro.app
spctl -a -vv dist/Lerro.app
xcrun stapler validate dist/Lerro.app
```

ad-hoc 和 Apple Development 产物不以 Gatekeeper 离站分发接受作为验收目标。

## Cloudflare 公开分发与应用内更新

公开 macOS 分发使用以下地址：

```text
官网：https://lerroapp.com
更新 feed：https://updates.lerroapp.com/appcast/stable.xml
最新下载：https://updates.lerroapp.com/download/macos/latest
不可变归档：https://updates.lerroapp.com/releases/<version>/<build>/Lerro-macOS-arm64.zip
```

`package_release.sh` 在 `developer-id` 模式完成公证和 staple 后，以维护者 Keychain 中的
Sparkle Ed25519 私钥签署最终 ZIP。`LERRO_SPARKLE_KEY_ACCOUNT` 可以指定 Keychain
profile 名；私钥不会写入 source tree、manifest、D1、R2 或公开配置。非公开签名模式的
归档签名字段必须为空。

发布命令：

```zsh
LERRO_SIGNING_MODE=developer-id \
LERRO_NOTARY_PROFILE='<maintainer-keychain-profile>' \
./script/package_release.sh

(cd site && npm run deploy)
curl --fail --silent --show-error https://lerroapp.com/changelog >/dev/null

./script/publish_cloudflare_release.sh
```

官网 changelog 先上线并通过公开 200 检查，随后发布 appcast 和归档。发布脚本在上传前
复验 ZIP 与 manifest 的 SHA-256、字节数、Developer ID、公证与 Sparkle
签名。ZIP 写入私有 R2 的不可变 key，读回校验后，通过 D1 batch 同时写入 release、artifact
和 stable channel head。batch 使用读取时的 generation 作为比较条件；并发发布失败时稳定
渠道保持上一条记录。每个 stable channel、平台和架构组合的 Sparkle build 必须唯一。公开 Worker
只接受读取请求；appcast 和下载路由只读取已发布的 stable head。发布完成后脚本以 cache-busting 请求复验 appcast enclosure 的版本、长度、
Ed25519 签名、不可变 URL，以及 latest 与不可变 ZIP 的 SHA-256。

发布 ZIP 属于普通二进制 application data。`r2 object put --pipe` 使用已复验的流式上传路径；
脚本必须从同一个不可变 key 读回完整对象并与 release manifest 的 SHA-256、字节数一致，
随后才允许写入 D1。Wrangler 仅输出 `Upload complete` 不能作为上传成功证据。

Sparkle framework 在 `dist/Lerro.app/Contents/Frameworks` 内签名并随 app 分发。`Info.plist`
固定 `SUFeedURL`、`SUPublicEDKey`，并关闭 Sparkle 自带的定时检查和自动下载。应用在启动
时及每 24 小时静默探测 feed；发现新版本后显示蓝色下载入口，用户点击后进入 Sparkle
下载与安装流程。第一次安装带更新器的版本由用户从官网完成。真实上一版本到下一版本的
检查、点击下载、安装和重启属于每次新公开版本的实机验收。

`distribution/wrangler.toml` 是维护环境私有配置，包含 D1 资源标识，必须保持在 Git 与公开
导出之外。公开导出脚本会排除所有名为 `wrangler.toml` 的文件，扫描器遇到残留文件会失败。
`distribution/wrangler.toml.example` 只提供结构模板。完整架构、撤回与失败策略见
[ADR-0007](decisions/0007-cloudflare-distribution-and-sparkle-updates.md)。

## GitHub 公开镜像

Cloudflare 保持官网、appcast 和应用下载的 canonical 分发源。每次 Cloudflare 发布及公开
SHA-256 复验完成后，同步执行以下 GitHub 镜像流程：

1. 从 [`public_repo_allowlist.txt`](../script/public_repo_allowlist.txt) 重新生成 clean export，
   完成公开扫描后同步到公开仓库 `main`，保留公开仓库已有历史。
2. 在该公开 commit 创建 `v<version>` annotated tag。
3. 创建稳定 GitHub Release，并上传同一次打包产生的
   `Lerro-macOS-arm64.zip`、`Lerro-macOS-arm64.dSYM.zip`、
   `Lerro-macOS-arm64.cdx.json`、`Lerro-release-manifest.json` 与
   `SHA256SUMS.txt`。
4. 通过 GitHub API 读回这五个 asset 的名称、字节数与 `digest`，逐项确认与 canonical
   本地产物及 `SHA256SUMS.txt` 相同；`releases/latest` 必须解析到新稳定版本。

GitHub Release 文案链接 canonical 下载与官网 changelog。GitHub 自动生成的 tag source
archive 提供源码快照，`outputs/Lerro-public-source.zip` 不重复上传。

## 版本发布检查表

- [ ] `config/Info.plist` 的 version/build 已更新。
- [ ] Release Notes 已更新。
- [ ] `Package.resolved` 符合预期。
- [ ] 两个 Vendor 来源记录、许可证、toolchain variant manifest 和单一本地 `swift-huggingface` 依赖图已复核；app 内四份记录非空且与源码 byte-identical。
- [ ] 上游 swift-huggingface PR #50 状态已按发布日期重新核对。
- [ ] 上游 swift-huggingface Issue #52 与本地临时文件消费补丁已按发布日期重新核对。
- [ ] vendored package tests 通过。
- [ ] `swift test` 全量通过。
- [ ] `build_and_run.sh --release --no-launch` 通过。
- [ ] 实际 signing mode 与目标一致。
- [ ] `package_release.sh` 通过且 source tree 在构建期间稳定。
- [ ] `verify_release.sh` 通过。
- [ ] CycloneDX SBOM 已从当前 `Package.resolved` 和许可证证据生成并通过校验。
- [ ] release manifest、SBOM 与 checksums 已归档。
- [ ] 真实 Release 人工矩阵的受影响行已通过。
- [ ] 真实缓存模型 smoke 已通过，或交付记录已经列明跳过原因与剩余边界。
- [ ] 真实 BYOK Provider smoke 已通过，或交付记录已经列明跳过原因与剩余边界。
- [ ] Developer ID 分支已完成 notary、staple、Gatekeeper。
- [ ] Developer ID ZIP 的 Sparkle Ed25519 签名和长度已写入 manifest 并通过复验。
- [ ] `publish_cloudflare_release.sh` 已完成 R2 读回、D1 batch 与公开 appcast/download SHA-256 验证。
- [ ] `lerroapp.com` 和 `www.lerroapp.com` 已返回预期站点，`updates.lerroapp.com` 已返回预期 feed。
- [ ] clean export 已同步到 GitHub `main`，公开扫描与 CI 已通过。
- [ ] GitHub tag、稳定 Release、五个镜像资产和 `releases/latest` 已复验；每个 asset 的名称、字节数和 digest 均与 canonical 产物及 checksum 一致。
- [ ] 已记录当前版本的首次手动安装边界，以及下一版本的真实 Sparkle N 到 N+1 验收计划。
- [ ] 已记录仍未执行的模型、TCC、硬件或多显示器边界。
