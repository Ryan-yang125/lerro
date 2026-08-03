# 0002：冻结 Lerro 产品与工程身份

- 状态：accepted
- 日期：2026-07-30
- 决策人：项目维护者
- 关联任务/PR：本地 Phase 0–4 品牌与开源改造
- 替代：无

## 背景

项目将以独立开源 macOS 产品交付，需要统一品牌、模块、Bundle、数据目录、权限身份和公开仓库命名。名称实时预查记录位于 [`../name-clearance.md`](../name-clearance.md)。

## 决策驱动因素

- 简洁、易读、两个音节的公开名称
- 稳定的 Bundle ID 与 TCC 身份
- 清晰的 Swift target 边界
- 可回滚、无模型重复副本的数据迁移
- 可从研究仓库导出的干净公开历史

## 方案

产品名冻结为 `Lerro`，读音为 LEH-ro。工程身份统一为：

```text
Lerro -> LerroIntelligence -> LerroCore
  |                           ^
  +----------> LerroMac ------+
```

Bundle ID 使用 `app.lerro.mac`，数据根使用 `~/Library/Application Support/app.lerro.mac/`，环境变量统一使用 `LERRO_` 前缀。公开仓库计划名为 `lerro`。

品牌资产使用固定 Ink Black / Soft White。主 UI 使用自适应黑白灰、SF Pro / 苹方 /
SF Mono、克制材质与原生 macOS 行为；success、warning、error 保留系统状态色。
浅色正文层级冻结为 `#292929`、`#5D5D5D`、`#9E9E9E`，必要的 12 pt 小字使用
`#6B6B6B`。字号冻结为 24 / 14 / 13 / 12 pt，tracking 为 `-0.15`；导航图标与圆角
为 14 / 8 pt，卡片图标与圆角为 20 / 16 pt，主要 CTA 使用 pill。hover 为 150 ms，
pointer-down 下沉 1 pt。HUD 继续使用既有外壳、声线、processing、状态切换与静音反馈。

品牌符号采用 A4 平面结构：`L` 输入起点、双 `rr` 声音节奏与开放 `o` 光标切口。

## 后果

### 收益

- 用户可见品牌和工程身份一致。
- 系统权限、日志、Pasteboard UTI、登录项与发布产物可从稳定 Bundle ID 派生。
- target 名称直接表达架构职责。
- 公开导出可以通过旧品牌扫描形成可自动验证的边界。

### 成本与风险

- 新 Bundle ID 会建立新的 TCC 身份，最终签名 app 需要重新授权麦克风与辅助功能。
- 旧数据需要在 repositories 和模型 runtime 初始化前迁移。
- `lerro.com` 已由同名技术公司持有，正式商业发布仍需专业商标意见与域名策略。

## 隐私与安全

迁移只处理本机 Application Support 内容，不上传设置、历史、词典、录音或模型。日志记录迁移阶段与结果，避开文本内容、音频内容、凭据和个人路径。

## 迁移与兼容

- 从 `com.ryanyang.typelessnative` 旧根迁移至 `app.lerro.mac`。
- 同一卷内优先使用原子移动，保持约 3.03 GB 模型单副本。
- 迁移使用 lock、receipt 与恢复信息保证幂等。
- 新旧根同时存在时，先校验并合并小型数据，再按内容身份复用模型资源。
- 新 app 启动时清理旧登录项注册，再注册 Lerro 登录项。

## 验证

- 迁移 focused tests：仅旧根、仅新根、两者并存、中断恢复、重复执行、模型单副本。
- 全量 `swift test`。
- Release bundle 的 Bundle ID、模块、资源、签名与环境变量扫描。
- 最终签名 app 的两项权限、物理 Fn、真人语音、跨 app 写入与断网模型测试。

## 文档同步

同步 architecture、core-flow、testing、release、privacy-security、troubleshooting、Brand Kit 和开源治理文档。
