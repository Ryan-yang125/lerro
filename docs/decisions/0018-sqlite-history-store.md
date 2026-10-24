# 0018：历史记录存进 SQLite

- 状态：accepted
- 日期：2026-10-24
- 决策人：Lerro maintainer
- 关联任务/PR：历史存储性能

## 背景

历史原来是 `history.json` 里的一个 JSON 数组，由 `JSONDocumentStore` 每次保存时整体重写，读取时整体解码，
搜索在内存里对每条记录做 `localizedCaseInsensitiveContains`。维护者的真实数据是 855 条、2.2 MB
（每条约 2.6 KB），保存一次 35 ms，冷启动读取加解码 39 ms，两者都随条数线性增长。按每年约 1,700 条计算，
五年后文件约 20 MB，保存约 350 ms，启动解码约 400 ms。`AppSession` 还有七处调用 `entries()` 读取全部历史，
其中大多数只需要几条记录、一个计数或一列路径。

## 决策

1. 历史存进 `history.sqlite`，由 `SQLiteHistoryRepository`（`LerroCore`）通过系统 `libsqlite3` 的 C API 访问。
   `LerroCore` 只依赖 Foundation 和系统 SQLite，不引入第三方库。
2. 表结构：每条记录一行。`id`（UUID 字符串，唯一）、`created_at`（`timeIntervalSinceReferenceDate`）、
   `mode`、`status`、`final_text`、`application_name`、`bundle_identifier`、`audio_relative_path` 是列，
   完整记录是 `entry` 列里的 JSON（`JSONEncoder` 默认日期格式，日期精确往返）。
   索引：`(created_at DESC, id)` 和 `(mode, created_at DESC, id)`。`PRAGMA user_version = 1`。
3. 日志模式 WAL，`synchronous = NORMAL`，busy timeout 5 秒。仓库是 actor，持有一个连接，首次调用时打开。
4. 搜索用 FTS5 外部内容表 `history_search`（`final_text`、`application_name`，`trigram` 分词，不区分大小写），
   由触发器与主表同步。查询不少于 3 个字符时用 `MATCH` 短语，即不区分大小写的子串匹配（Unicode 大小写折叠）；
   1–2 个字符时对同一张表用 `LIKE '%…%'`（只对 ASCII 字母不区分大小写，中文按原样匹配）。
   `%`、`_`、`"` 按字面匹配。
5. `page(_:)` 在数据库里分页：`count(*)` 给出总数，`LIMIT/OFFSET` 只解码当前页。
   `HistoryRepository` 新增定向查询：`entries(ids:)`、`entries(since:)`、`audioRelativePaths(createdBefore:)`、
   `bundleIdentifierCounts()`。`AppSession` 的调用点改为：
   - 侧栏计数和菜单栏最近记录：一次 `page(limit: 6)`，取 `entries` 和 `totalCount`；
   - 词典本周摘要：`entries(since: 7 天前)`；
   - AI 用量页按 ID 取记录、捕获失败时确认是否已保存：`entries(ids:)`；
   - 应用列表的听写次数：`bundleIdentifierCounts()`；
   - 删除全部、到期清理、孤儿录音对账：`audioRelativePaths(createdBefore:)`；
   - `entries()` 只留给一次性的每日用量补建（`usage-days.json` 为空时）。
6. 到期规则集中到 `HistoryRetention.cutoff(now:)`：早于截止时间的记录删除，数据库用同一个时间做 `DELETE`。
7. 旧数据只导入一次：打开数据库后若同目录下有 `history.json`，用 ISO 8601 日期解码，在一个事务里按 `id` upsert，
   提交后删除 JSON 文件。导入按 `id` 幂等，提交后、删除前崩溃时下次启动会重新导入同样的记录。
   JSON 解码失败时报错并保留文件。没有回退读取和双写。

## 备选方案

| 方案 | 未采用的原因 |
| --- | --- |
| GRDB 等封装库 | 只需要十来条固定 SQL、一个连接、一个事务助手；C API 加约 100 行封装即可，免去依赖、许可证记录和版本跟进 |
| Core Data / SwiftData | 需要模型定义和迁移体系，全文搜索仍要另外做，而且把存储语义交给框架 |
| JSON 分片或追加写日志 | 仍然要在内存里搜索和计数，需要自己实现压缩和崩溃恢复 |
| 把所有字段拆成列 | `HistoryEntry` 有嵌套的上下文回执、阶段耗时和 AI 调用记录，拆列只增加映射代码；查询只用到上面几列 |
| `LIKE` 加自定义 `localizedCaseInsensitiveContains` 函数 | 语义完全一致，但每次搜索都要全表扫描并把每行文字传回 Swift |

## 后果

- 保存一条记录只写一行和对应索引，冷启动只读第一页，搜索走索引。数字见下文「验证」。
- 搜索语义与原来的差别：`localizedCaseInsensitiveContains` 按当前语言做大小写比较，并把 Unicode 规范等价的写法
  视为相同。现在 3 个字符以上用 SQLite 的 Unicode 大小写折叠（不区分语言，土耳其语 `İ/i` 等特殊规则不适用），
  1–2 个字符只对 ASCII 不区分大小写；两种情况都区分组合字符与预组合字符（NFC/NFD）。重音仍然区分，与原来一致。
- 磁盘上多了 `history.sqlite-wal` 和 `history.sqlite-shm`，权限随主文件。
- `script/capture_latency_report.py` 改为只读打开 `history.sqlite`，从 `created_at` 列取时间。
- 不读旧版本的 `history.json`，降级到旧版本会看到空历史。

## 隐私与安全

- 数据库文件创建时为 `0600`，每次打开时再设一次；SQLite 用主文件的权限创建 `-wal`、`-shm`。根目录仍是 `0700`。
- `historyRetention == .never` 时不保存记录；仓库在首次读取时会创建空数据库文件。
- 删除带录音的记录仍是先删音频再删行。
- 错误信息只含 SQLite 返回码和 `sqlite3_errmsg`，不含记录内容；仓库不写日志。

## 验证

`SQLiteHistoryRepositoryTests`：增删改与重新打开、分页边界、搜索（含 Unicode 大小写、2 字中文、通配符字面匹配）、
模式过滤、排序平局规则、定向查询、到期边界、日期精确往返、一次性导入与失败时保留文件、文件权限、
两个实例共享文件、并发保存与删除。`python3 script/test_capture_latency_report.py`。

临时基准测试（已删除）：5,000 条合成记录，每条约 2.6 KB（JSON 文件 13 MB），release 构建，7 次取中位数。

| 操作 | `history.json` | `history.sqlite` |
| --- | --- | --- |
| 冷启动后第一页（50 条） | 57.6 ms | 1.5 ms |
| 冷启动读取全部 `entries()` | 57.3 ms | 62.2 ms |
| 保存一条 | 68.2 ms | 0.23 ms |
| 第一页（已打开） | 0.10 ms（内存缓存） | 0.65 ms |
| 偏移 4,000 的一页 | 0.07 ms | 0.81 ms |
| 搜索 `kubernetes`（100 条命中） | 47.4 ms | 1.5 ms |
| 搜索 `预算`（2 字，500 条命中） | 94.6 ms | 23.5 ms |
| 模式过滤 | 0.93 ms | 0.69 ms |
| 一次性导入 `history.json` | — | 695 ms |

已打开后的分页比内存缓存慢，原因是每页都要查询和解码 50 条 JSON，仍在 1 ms 以内。全量读取只剩每日用量补建一处调用。
