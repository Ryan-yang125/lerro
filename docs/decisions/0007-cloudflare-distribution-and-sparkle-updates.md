# 0007：Cloudflare 分发与 Sparkle 更新

- 状态：accepted
- 日期：2026-08-02
- 决策人：Lerro maintainers

## 背景

`lerroapp.com` 提供官网直连下载，并让已安装的版本发现、下载并安装后续版本。公开 ZIP 保持 Developer ID、Hardened Runtime、
Apple notarization、staple、Gatekeeper 与独立的归档签名。更新私钥、Apple 签名身份、notary 凭据和 Cloudflare 配置属于维护者环境数据。

## 决策

应用接入 Sparkle 2。`AppUpdateController` 在正常应用生命周期启动 `SPUStandardUpdaterController`；设置和首页的「检查更新」调用
Sparkle；fixture 与 XCTest 进程不创建它。[`Info.plist`](../../config/Info.plist) 固定 HTTPS feed
`https://updates.lerroapp.com/appcast/stable.xml` 与 Ed25519 公钥。Sparkle 自带的定时检查每 4 小时
（`SUScheduledCheckInterval`）检查一次，使用 Sparkle 为菜单栏应用提供的温和提醒（gentle reminders）：用户正在使用 Lerro 时
直接显示 Sparkle 的更新窗口；Lerro 在后台时不打断听写，改为在菜单栏图标加圆点、菜单栏面板首行和主窗口侧边栏显示更新入口。
下载与安装由用户点击后启动，自动下载保持关闭。

归档私钥存于维护者的 macOS Keychain。`package_release.sh` 在 Developer ID 归档完成公证和 staple 后用 `sign_update` 签署最终 ZIP，
把签名和长度写入 release manifest。

```text
lerroapp.com         -> lerro-site Worker（静态站）
www.lerroapp.com     -> 308 到 apex
updates.lerroapp.com -> lerro-distribution Worker
                         -> 私有 R2：不可变 ZIP
                         -> 私有 D1：release、artifact、stable head
```

`lerro-distribution` 只处理 `GET` 与 `HEAD`：stable head 的 appcast、最新下载重定向和不可变历史 ZIP。数据库和 R2 没有公开写入接口。

发布顺序（[`publish_cloudflare_release.sh`](../../script/publish_cloudflare_release.sh)）：

1. 官网 changelog 已上线。
2. 校验 Developer ID、公证、manifest、SHA-256、字节数与 Sparkle 签名。
3. 上传 `releases/<version>/<build>/Lerro-macOS-arm64.zip`，读回并校验 SHA-256。
4. 一个带 generation 比较条件的 D1 batch 写入 release、artifact 和 stable channel head。
5. 请求 appcast、最新下载和不可变地址，确认新 build 对外可读。

R2 key 已存在时只接受相同 SHA-256。D1 batch 失败时 stable head 保持上一条记录。同一 channel、平台和架构内 Sparkle build 唯一。
撤回版本时把 stable head 移回较早的已验证记录，历史 ZIP 保留以维持不可变链接。

## 备选方案

- GitHub Releases 作为更新 feed：GitHub Release 保留为源码协作渠道，官网下载和 feed 由 Cloudflare 提供。
- 自建下载服务器：运维面和证书管理成本超出当前规模需要。

## 隐私与安全

更新检查只访问 `updates.lerroapp.com`，服务端看到常规 HTTPS 元数据以及用于选择更新的应用版本和平台。请求不包含音频、transcript、
焦点文本、词典、API Key、提示词或模型回答。应用用 `SUPublicEDKey` 验证 ZIP 的 Ed25519 签名。R2、D1、Keychain 和 notary profile
不进入仓库，`distribution/wrangler.toml` 由 `.gitignore` 排除。

## 后果

- 第一个带 Sparkle 的版本需要用户手动安装。
- 发布依赖维护者机器上的 Keychain 与 Cloudflare 登录状态。

## 验证

`distribution` 的 node 测试覆盖 appcast、XML 转义、Range、ETag、HEAD、缓存和发布 batch；`verify_release.sh` 验证 Sparkle framework、
签名、manifest；发布脚本在上传后读回公开端点并比对 SHA-256。
