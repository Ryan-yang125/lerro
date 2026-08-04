# Open-source publication

The public Lerro repository is produced from an explicit file allowlist after
the product, migration, UI, tests, and release documentation pass their gates.
The research workspace remains a private engineering archive.

## Publication boundary

The public repository contains the source package, tests, vendored source with
provenance, application configuration, build and release scripts, governance,
public documentation, project-level Claude/Codex agent entrypoints, GitHub
templates, licensed brand assets, and the website source under `site/`.

It excludes research captures, comparison material, reverse-engineering notes,
third-party product screenshots, local manifests, personal data, credentials,
signing identities, build output, release archives, dSYMs, model weights, test
recordings, logs, caches, website dependencies and generated output, and the
source repository's Git object database. Website exclusions include
`node_modules`, `dist`, `out`, `.wrangler`, `.next`, `.vinext`, `coverage`,
`outputs`, `work`, and generated `next-env.d.ts` files.

Release-machine labels and local paths live in the ignored
`config/maintainer.local.env`. The tracked `config/maintainer.env.example`
contains placeholders only.

## License map

| Material | License or policy |
| --- | --- |
| First-party source code and configuration | Apache-2.0, [`LICENSE`](../../LICENSE) |
| First-party documentation, screenshots, website public assets, and reusable templates | CC BY 4.0, [`LICENSES/CC-BY-4.0.txt`](../../LICENSES/CC-BY-4.0.txt) |
| Lerro name, logo, wordmark, and app icon | [`TRADEMARKS.md`](../../TRADEMARKS.md) |
| Vendored packages and dependencies | Their upstream licenses and [`THIRD_PARTY_NOTICES.md`](../../THIRD_PARTY_NOTICES.md) |
| Models downloaded at runtime | Model-specific license and model card |
| Other assets | `Brand/licenses/ASSET-LICENSES.json` |

## Governance

- [Contributing](../../CONTRIBUTING.md)
- [Code of Conduct](../../CODE_OF_CONDUCT.md)
- [Security Policy](../../SECURITY.md)
- [Privacy](../../PRIVACY.md)
- [Support](../../SUPPORT.md)
- [Changelog](../../CHANGELOG.md)

The export and scan procedure is documented in
[`clean-export.md`](clean-export.md). A public release still requires the full
Developer ID, notarization, Gatekeeper, quarantine, SBOM, checksum, manifest,
and artifact-attestation gates in [`../release.md`](../release.md).
