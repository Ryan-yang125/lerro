# Lerro distribution Worker

这个目录承载 `updates.lerroapp.com` 的 Cloudflare Worker。它读取私有 R2 bucket
与 D1 发布元数据，向用户和 Sparkle 提供三个公开只读入口：

| Endpoint | 用途 | 缓存策略 |
| --- | --- | --- |
| `/appcast/stable.xml` | Sparkle 稳定渠道当前 head 的 appcast | 5 分钟 |
| `/download/macos/latest` | 官网的当前 arm64 macOS ZIP | 60 秒 |
| `/releases/<version>/<build>/<filename>.zip` | Sparkle 与历史下载的不可变 ZIP | 1 年 immutable |

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

## 发布事务

发布工具先将已公证的 ZIP 上传到不可变 R2 key：

```text
releases/<version>/<build>/Lerro-macOS-arm64.zip
```

随后受控发布脚本将 publication JSON 交给唯一的 SQL 生成入口：

```zsh
node distribution/bin/render-publication-sql.mjs publication.json > publication.sql
```

它输出三条分号分隔的 D1 语句：创建 release、创建 artifact、推进 channel head。生产脚本
将该文件作为一个 D1 batch 提交；`preparePublicationBatch(database, publication)` 也复用同一份
校验、SQL 模板与绑定顺序。受控发布脚本负责检查 release 元数据、R2 不可变对象和单调递增的
`generation`，并把读取到的 generation 作为 batch 内的比较条件。并发发布会整体失败，稳定
channel head 保持原值。每个 channel、平台和架构组合的 Sparkle build 也由唯一索引保护。

`release.minimum_macos` 可直接用于 CLI JSON；现有调用方也可继续使用
`release.minimumMacOS`。若两者同时存在，值必须一致。

`publication.artifact.sha256` 和 `publication.artifact.edSignature` 都由本机打包产物生成。
Sparkle 私钥不进入本目录、R2、D1 或 Worker 环境。

每个 stable item 使用三段式 `minimumSystemVersion`，并声明 `arm64` 硬件要求。
