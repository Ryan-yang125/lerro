# 0002：Lerro 产品与工程身份

- 状态：accepted
- 日期：2026-07-30
- 决策人：项目维护者

## 决策

产品名为 `Lerro`（读音 LEH-ro）。工程身份统一：

| 角色 | 值 |
| --- | --- |
| 可执行文件与 app | `Lerro` / `Lerro.app` |
| Swift target | `LerroCore`、`LerroIntelligence`、`LerroMac`、`Lerro` |
| Bundle ID | `app.lerro.mac` |
| 数据根 | `~/Library/Application Support/app.lerro.mac/` |
| 环境变量前缀 | `LERRO_` |
| 公开仓库 | `Ryan-yang125/lerro` |

日志 subsystem、剪贴板 session marker 类型和登录项身份都从 Bundle ID 派生。表中任一值变化都需要新的 ADR，
并重新审查权限、发布和文档。

主 UI 使用自适应黑白灰、SF Pro、苹方与 SF Mono，success、warning、error 使用系统状态色。品牌色与图标规则见
[`Brand/`](../../Brand/README.md)，后续视觉决策见 [ADR 0013](0013-brand-capsule-hud.md) 与
[ADR 0014](0014-main-window-rebuild.md)。

## 后果

- 用户可见品牌与工程身份一致，权限、日志和发布产物可从稳定 Bundle ID 派生。
- Bundle ID 或签名身份变化会让 macOS 建立新的 TCC 条目，用户需要重新授权麦克风和辅助功能。
- `lerro.com` 由同名技术公司持有，当前使用 `lerroapp.com`。商业推广前需要自行评估商标风险。
