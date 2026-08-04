# Release evidence template

复制本文件到 `work/release-evidence/v<version>.md`，填入本次真实输出。公开 Release Notes 从这份记录提炼产品变化与公开校验，排除签名身份详情、Team ID、证书邮箱、凭据标签、token 和个人路径。

## Source

```text
Version / build:
Release date:
Private source commit:
Private source tree clean:
Public source commit:
Annotated tag / tag object:
Package.resolved SHA-256:
Toolchain / Xcode / Metal:
```

## Change and focused validation

```text
User-visible changes:
Affected targets and adapters:
Focused test commands / results:
Vendor tests / upstream state:
Website commands / results:
Distribution commands / results:
Agent workspace validation:
Documentation and ADR updates:
```

## Full deterministic gates

```text
swift test:
Test count / suite count:
verify_release command:
Signing mode:
App architecture:
Binary UUID:
dSYM UUID:
Fixture states:
Brand assets:
Public export scan:
git diff --check:
```

## Canonical artifacts

```text
Application ZIP bytes / SHA-256 / Sparkle signature:
dSYM ZIP bytes / SHA-256:
SBOM format / components / bytes / SHA-256:
Release manifest SHA-256:
SHA256SUMS verification:
Notary submission accepted:
Stapler validation:
Gatekeeper result:
Independent extraction result:
```

## Real system matrix

```text
Mac model / keyboard:
macOS version / build:
Installed app path:
Microphone and Speech:
Fn / Globe and Emoji isolation:
Accessibility and secure input:
TextEdit / browser delivery:
Clipboard restoration:
HUD / Ask / multi-display:
MLX live smoke:
BYOK live smoke:
Sparkle N -> N+1:
```

## Website and Cloudflare

```text
Website Worker version:
English / Chinese route checks:
Changelog checks:
Screenshot object checks:
Distribution publication result:
R2 immutable key readback:
D1 stable generation:
Appcast version / build / length / signature:
Latest ZIP SHA-256:
Immutable ZIP SHA-256:
```

## GitHub mirror

```text
Public export source:
Public scan result:
Main push:
Tag push:
GitHub Release URL:
Five asset byte/digest readback:
Main CI URL / result:
Tag CI URL / result:
README and screenshot live checks:
```

## Remaining boundaries

```text
Skipped checks and concrete reasons:
Manual follow-up owner:
Rollback / recovery state:
Final App download URL:
Final website changelog URL:
Final GitHub Release URL:
```
