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
outputs/Lerro-release-manifest.json
outputs/SHA256SUMS.txt
```

ZIP 和 dSYM ZIP 属于可再生产物，通常由 `.gitignore` 排除。manifest 与 checksum 是否纳入版本控制由发布策略决定；它们必须与同一次打包生成的二进制一致。

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
2. 使用同一 resolved signing mode 构建 Release app 与 dSYM。
3. 验证构建前后 source snapshot 一致。
4. 校验 app、plist 和隐私清单。
5. Developer ID 分支先提交 pending ZIP 公证。
6. staple app，再运行 codesign 与 Gatekeeper 检查。
7. 重新创建最终 app ZIP，并创建 dSYM ZIP。
8. 生成 release manifest 和 checksum。
9. 所有 pending 文件完成后原子替换 canonical 产物。

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
- 校验 `SHA256SUMS.txt` 中 app ZIP、dSYM ZIP 和 manifest。
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
- app ZIP、dSYM ZIP 的文件名、hash 和字节数。

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

## Phase 6 公开分发补充产物

当前脚本生成 app ZIP、dSYM ZIP、source-bound manifest 与 checksums。正式公开
发布还需要在独立发布流水线中生成并验证以下产物：

- 品牌化 DMG 与独立 quarantine 安装测试。
- 从同一 `Package.resolved`、Vendor 来源和模型记录生成的 SBOM。
- GitHub Release artifact attestation，以及与 tag 和 source manifest 的绑定。
- Developer ID、公证日志、staple 与 Gatekeeper 证据。

GitHub 仓库尚未创建时，artifact attestation 无法执行。Developer ID identity
或 notary profile 缺失时，签名与公证分支应保持未验收，并在交付记录中明确列出。

## Preview 手动更新

当前 preview 版本采用手动更新。Home 与设置页的“检查更新”统一打开完整的
[GitHub Releases](https://github.com/Ryan-yang125/lerro/releases) 列表，确保仍处于
prerelease 状态的最新构建可见。用户选择版本后下载对应的签名产物，并继续按本页的
checksum、签名、公证与 Gatekeeper 规则验证。稳定版自动更新属于后续发布能力。

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
- [ ] release manifest 与 checksums 已归档。
- [ ] 真实 Release 人工矩阵的受影响行已通过。
- [ ] 真实缓存模型 smoke 已通过，或交付记录已经列明跳过原因与剩余边界。
- [ ] 真实 BYOK Provider smoke 已通过，或交付记录已经列明跳过原因与剩余边界。
- [ ] Developer ID 分支已完成 notary、staple、Gatekeeper。
- [ ] 已记录仍未执行的模型、TCC、硬件或多显示器边界。
