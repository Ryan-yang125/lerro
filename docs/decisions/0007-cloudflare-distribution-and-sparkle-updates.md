# 0007：Cloudflare 分发与 Sparkle 更新

- 状态：accepted
- 日期：2026-08-02
- 决策人：Lerro maintainers
- 关联任务/PR：应用内更新与官网直连下载
- 替代：无

## 背景

Lerro 需要由 `lerroapp.com` 提供官网直连下载，并让已安装的公开版本能发现、下载并在退出后安装后续版本。现有 preview 产物没有内嵌更新器，Home 与设置中的“检查更新”只会打开外部发布页。

公开 macOS ZIP 还必须保持 Developer ID、Hardened Runtime、Apple notarization、staple、Gatekeeper 与独立归档签名的完整链路。更新私钥、Apple 签名身份、notary 凭据和 Cloudflare 配置都属于维护环境数据。

## 决策驱动因素

- 用户从官网获得稳定的 HTTPS 下载地址。
- 更新归档在下载前可由应用内公钥验证。
- 发布元数据与大文件可以独立更新，并且公开读取面尽量小。
- transcript、上下文、API Key 与用户数据不能进入分发服务。
- 发布失败时继续服务已发布版本。

## 方案

应用接入 Sparkle 2。`AppUpdateController` 在正常应用生命周期启动 `SPUStandardUpdaterController`，Home 和设置的“检查更新”调用 Sparkle 的检查动作；`LERRO_FIXTURE_MODE=1` 与 XCTest 环境禁止初始化更新器。

`Info.plist` 固定以下公开配置：

- HTTPS feed：`https://updates.lerroapp.com/appcast/stable.xml`。
- Sparkle Ed25519 公钥。
- 应用启动时及每 24 小时静默探测一次；发现更新后显示蓝色下载入口。
- 下载与安装由用户点击更新入口后启动。
- Sparkle 自带的定时检查和自动下载保持关闭。

归档私钥仅存于维护者 macOS Keychain。`package_release.sh` 在 Developer ID 归档完成公证和 staple 后，通过 `sign_update` 签署最终 ZIP，并把签名和 ZIP 长度写入 release manifest。非公开签名模式不生成归档签名。

Cloudflare 拓扑：

```text
lerroapp.com         -> lerro-site Worker
www.lerroapp.com     -> lerro-site Worker，308 到 apex
updates.lerroapp.com -> lerro-distribution Worker
                         -> 私有 R2：不可变 ZIP
                         -> 私有 D1：release、artifact、stable head
```

`lerro-distribution` 只处理 `GET` 与 `HEAD`，提供 stable head 的 appcast、最新下载重定向和不可变历史 ZIP。它从 D1 选择当前 stable head 的已发布记录，再从私有 R2 读取对应对象。数据库和 R2 没有公开写入接口。

发布脚本执行以下顺序：

1. 部署官网 changelog，并确认公开页面返回 200 且包含待发布版本。
2. 验证 Developer ID、公证、manifest、SHA-256、ZIP 字节数与 Sparkle 签名。
3. 上传 `releases/<version>/<build>/Lerro-macOS-arm64.zip`，读回并校验 SHA-256。
4. 用一个带 generation 比较条件的 D1 batch 写入 release、artifact 和 stable channel head。
5. 请求 appcast、release notes、最新下载和不可变地址，确认新 build 对外可读。

R2 key 已存在时只接受相同 SHA-256。D1 batch 失败时 stable head 保持上一条发布记录；遗留的不可变 R2 对象无法被公开路由访问。Sparkle build 在同一 channel、平台和架构内保持唯一。

## 备选方案

- GitHub Releases：继续作为源码协作和可选镜像渠道，不承担官网直连下载和更新 feed 的服务职责。
- Cloudflare Pages：本次官网采用 Worker custom domain，与分发 Worker 的运行和路由模型保持一致。
- 自建下载服务器：增加运维面、证书与对象存储管理，当前规模没有必要。

## 后果

### 收益

- 官网下载、更新 feed 和二进制分发全部由 `lerroapp.com` 域名体系承载。
- 每个公开 ZIP 同时受到 Apple 代码签名/公证和 Sparkle 归档签名保护。
- 发布人员只需执行受控脚本，不需要把 Keychain 私钥或 Cloudflare 凭据写进仓库。

### 成本与风险

- 第一个带 Sparkle 的版本需要用户手动安装；旧 preview 没有内置更新器。
- 真实 N 到 N+1 的点击下载、安装和重启需要在独立安装环境记录。
- Cloudflare custom domain 的 DNS/TLS 生效时间由 Cloudflare 控制。

## 隐私与安全

更新检查仅访问 `updates.lerroapp.com`，服务端接收常规 HTTPS 连接元数据与用于选择更新的应用版本/平台信息。该请求不包含音频、transcript、焦点文本、词典、API Key、prompt 或模型回答。

更新 feed 与 ZIP 使用 HTTPS；应用以 `SUPublicEDKey` 验证 ZIP 的 Ed25519 签名。R2、D1、Keychain 和 notary profile 均不进入公开导出。日志不得记录更新签名、下载 URL query、凭据或用户内容。

## 迁移与兼容

安装旧 preview 的用户从官网手动安装第一个带更新器的 Developer ID 公证版本。之后的版本递增 `CFBundleVersion`，Sparkle 使用 stable appcast 发现更新。撤回版本时将 stable head 移到已验证的较早发布记录，历史 ZIP 继续保留以维持不可变链接。

## 验证

- `swift test` 覆盖 fixture/XCTest 环境不启动更新器。
- `build_and_run.sh` 和 `verify_release.sh` 验证 Sparkle framework、签名顺序、arm64、rpath、Info.plist 和许可证。
- Developer ID 打包验证 notarization、staple、Gatekeeper、Sparkle ZIP 签名与 release manifest。
- distribution 单元测试验证 appcast、XML 转义、Range、ETag、HEAD、缓存和发布 batch。
- 公开端点验证官网、appcast、最新下载和 ZIP SHA-256。
- 下一次公开版本在独立安装的上一版本中完成真实检查、下载、退出安装和重启验收。

## 文档同步

- `README.md`
- `docs/architecture.md`
- `docs/testing.md`
- `docs/release.md`
- `docs/privacy-security.md`
- `PRIVACY.md`
- `Sources/Lerro/Resources/PrivacyPolicy.html`
- `Sources/Lerro/Resources/TermsOfUse.html`
