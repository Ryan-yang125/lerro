# Lerro 名称与产品身份预查

- 冻结日期：2026-07-30
- 产品名：Lerro
- 推荐读音：LEH-ro（/ˈlɛroʊ/）
- 结论：用于本地开发和开源准备，公开发布前保留一次由专业人士执行的正式商标检索。

## 冻结身份

| 项目 | 冻结值 |
| --- | --- |
| App / executable | `Lerro` |
| Swift package | `Lerro` |
| Core target | `LerroCore` |
| Intelligence target | `LerroIntelligence` |
| macOS target | `LerroMac` |
| App target | `Lerro` |
| 计划仓库名 | `lerro` |
| Bundle ID | `app.lerro.mac` |
| 环境变量前缀 | `LERRO_` |
| Application Support | `~/Library/Application Support/app.lerro.mac/` |
| 品牌描述 | Local-first voice writing for macOS |

这些值是 Phase 0–4 的统一输入。后续修改需要新增 ADR，并同步数据迁移、TCC、登录项、构建和发布文档。

## 2026-07-30 公开数据库预查

| 范围 | 方法 | 结果 |
| --- | --- | --- |
| GitHub | GitHub Search API，仓库名精确匹配 `lerro` | 0 个精确仓库名 |
| Mac App Store | Apple Search API，`entity=macSoftware`，产品名精确匹配 | 0 个精确产品名 |
| Homebrew | `brew search '/^lerro$/'` | 0 个精确 formula/cask |
| `lerro.app` | Identity Digital RDAP | HTTP 404 / Object not found；查询时未显示注册对象 |
| `lerro.com` | Verisign RDAP | 已注册，注册时间 1997-07-04，到期时间 2028-07-03 |
| 同名商业主体 | 公开网页与政府合同资料 | The Lerro Corporation 从事广播、硬件与技术供应；存在邻近科技语境 |
| 软件与语音品类网页 | 精确词组搜索 | 未发现名为 Lerro 的 macOS 听写或语音写作产品 |
| 商标公开索引 | USPTO、EUIPO、WIPO 精确词组的公开搜索引擎索引 | 未发现可核实的精确软件/语音类记录；公开索引覆盖不完整 |

## 风险判断

- `Lerro` 同时是姓氏，也是巴斯克语中与“行、列、文本行”相关的词，独创性处于中等水平。
- `lerro.com` 已被同名技术公司持有，官网和邮件识别需要使用其他域名。
- 当前公开检索未发现 macOS 听写同品类直接冲突，适合继续本地工程改造与开源准备。
- 正式公开发布、商标申请或商业推广前，应检索至少 Nice 9、35、38、41、42 类及主要目标市场，并保留律师书面意见。
- 域名注册会产生外部费用，本阶段记录可用性，不执行购买。

## 可复验命令

```zsh
gh api 'search/repositories?q=lerro+in:name'
curl -fsSL 'https://itunes.apple.com/search?term=lerro&entity=macSoftware&limit=200'
curl -i 'https://rdap.identitydigital.services/rdap/domain/lerro.app'
curl -fsSL 'https://rdap.verisign.com/com/v1/domain/lerro.com'
brew search '/^lerro$/'
```

## Phase 0 放行记录

- 名称、读音、仓库名、Bundle ID、target、环境变量与数据根已冻结。
- 同品类公开预查已完成并记录时间与复验方式。
- 域名购买与正式法律意见作为公开发布前的外部事项保留。
- 私有研究仓库的提交与 tag 不进入公开导出；公开仓库从独立空历史开始。
