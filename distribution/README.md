# Lerro distribution Worker

这个目录承载 `updates.lerroapp.com` 的 Cloudflare Worker。它读取私有 R2 bucket
与 D1 发布元数据，向用户和 Sparkle 提供公开只读入口：

| Endpoint | 用途 | 缓存策略 |
| --- | --- | --- |
| `/appcast/stable.xml` | Sparkle 稳定渠道当前 head 的 appcast，条目始终指向 ZIP | 5 分钟 |
| `/download/macos/latest` | 官网的当前 arm64 macOS DMG（`Lerro-macOS-arm64.dmg`） | 60 秒 |
| `/releases/<version>/<build>/<filename>.zip` | Sparkle 使用的不可变 ZIP | 1 年 immutable |
| `/releases/<version>/<build>/<filename>.dmg` | 历史 DMG 下载 | 1 年 immutable |

请求路径只匹配上述白名单。Worker 从 D1 的 stable channel head 读取 `status = 'published'`
记录，再以数据库中的 `r2_key` 读取对象。用户输入从未拼接为 R2 key。R2 bucket 保持私有，避免
配置 `r2.dev` 或其他公开 bucket 入口。

## 本地检查

本目录没有运行时 npm 依赖，Node 22 即可执行路由单元测试：

```zsh
cd distribution
npm run check
npm test
```

## Cloudflare 绑定

创建受控资源后复制配置模板：

```zsh
cd distribution
cp wrangler.toml.example wrangler.toml
```

在 `wrangler.toml` 填入新建 D1 的 ID，并保留以下绑定名称：

- `DB`：D1 database `lerro-releases`
- `RELEASES`：私有 R2 bucket `lerro-releases`
- `PUBLIC_BASE_URL`：`https://updates.lerroapp.com`

随后应用迁移：

```zsh
npx wrangler@4.118.0 d1 migrations apply lerro-releases --remote
```

取消 `[[routes]]` 三行的注释，确认现有 DNS 记录适合该 custom domain，再部署：

```zsh
npx wrangler@4.118.0 deploy
```

发布后确认 `updates.lerroapp.com` 仅指向此 Worker。

## 发布顺序

仓库没有独立的 Worker 部署脚本。发布脚本与下面的命令都使用 `site/node_modules/.bin/wrangler`
和私有的 `distribution/wrangler.toml`。引入 DMG 的版本按以下顺序操作：

1. 对远端 D1 应用 `0003_disk_image_artifacts.sql`（一次性，重建 `artifacts` 表以允许 `macos-dmg`）：

   ```zsh
   site/node_modules/.bin/wrangler d1 migrations apply lerro-releases \
     --remote --config distribution/wrangler.toml
   ```

2. 运行 `script/publish_cloudflare_release.sh`，写入 R2、D1 并推进 stable head。
3. 部署 Worker，让 `/download/macos/latest` 开始返回 DMG：

   ```zsh
   cd distribution
   ../site/node_modules/.bin/wrangler deploy --config wrangler.toml
   ```

先部署新 Worker 会让 `/download/macos/latest` 在 head 尚无 DMG 行时返回 404，所以 Worker 部署排在发布之后。
旧 Worker 在步骤 2 之后仍从 `macos-zip` 行提供 latest 下载与 appcast，Sparkle 更新不受影响。

## 发布事务

发布工具先将已公证的 ZIP 与 DMG 上传到不可变 R2 key：

```text
releases/<version>/<build>/Lerro-macOS-arm64.zip
releases/<version>/<build>/Lerro-macOS-arm64.dmg
```

两者都是普通二进制 application data；上传命令使用经过复验的 `r2 object put --pipe`
流式路径。发布脚本随后从同一个 key 读回全部字节并核对 release manifest SHA-256，读回成功前不会
创建 D1 release 或推进 stable channel head。key 已存在且字节不同时发布终止。

随后受控发布脚本将 publication JSON 交给唯一的 SQL 生成入口：

```zsh
node distribution/bin/render-publication-sql.mjs publication.json > publication.sql
```

它输出四条分号分隔的 D1 语句：创建 release、创建 ZIP artifact、创建 DMG artifact、推进 channel head。生产脚本
将该文件作为一个 D1 batch 提交；`preparePublicationBatch(database, publication)` 也复用同一份
校验、SQL 模板与绑定顺序。受控发布脚本负责检查 release 元数据、R2 不可变对象和单调递增的
`generation`，并把读取到的 generation 作为 batch 内的比较条件。并发发布会整体失败，稳定
channel head 保持原值。每个 channel、平台和架构组合的 Sparkle build 也由唯一索引保护。

`release.minimum_macos` 可直接用于 CLI JSON；现有调用方也可继续使用
`release.minimumMacOS`。若两者同时存在，值必须一致。

`publication.artifact.sha256` 和 `publication.artifact.edSignature` 都由本机打包产物生成。
`publication.diskImage` 描述 DMG（`macos-dmg`，`application/x-apple-diskimage`），没有 Sparkle
签名，D1 中 `sparkle_ed_signature` 为空字符串；表约束只在 `macos-zip` 行要求非空签名。
Sparkle 私钥不进入本目录、R2、D1 或 Worker 环境。

发布脚本写入后依次核对公开端点（网络瞬时错误自动重试）：appcast 仍指向 ZIP 且长度与签名匹配，
`/download/macos/latest` 与不可变 DMG URL 的 SHA-256 等于 DMG，不可变 ZIP URL 的 SHA-256 等于 ZIP。

每个 stable item 使用三段式 `minimumSystemVersion`，并声明 `arm64` 硬件要求。
