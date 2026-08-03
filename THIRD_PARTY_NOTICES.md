# Third-party notices

Lerro depends on open-source packages and optional model assets. Exact revisions
for a source checkout are recorded in `Package.resolved`; vendored source origins
and local patches are recorded in each `Vendor/*/UPSTREAM.md`. Release artifacts
carry the license files collected from the resolved checkouts and vendored
packages. The source-bound manifest identifies the inputs used for that build;
the Phase 6 public-distribution pipeline must attach an SBOM derived from the
same resolved graph.

## Source-package inventory

`script/scan_public_repo.sh` reads every identity in `Package.resolved`, locates
the corresponding resolved checkout `LICENSE*`, detects the license from its
actual text, and compares the result with this table. It applies the same check
to every local package under `Vendor/`. The export uses the private workspace's
resolved checkouts as license evidence, while a fresh public checkout gains the
same evidence after dependency resolution.

| Package identity | Verified license | Evidence packaged for release |
| --- | --- | --- |
| `eventsource` | MIT | Resolved `LICENSE.md` |
| `mlx-swift` | MIT | Resolved `LICENSE` |
| `mlx-swift-lm` | MIT | Resolved `LICENSE` |
| `sparkle` | MIT | Resolved binary artifact `LICENSE` |
| `swift-argument-parser` | Apache-2.0 | Resolved `LICENSE.txt` |
| `swift-asn1` | Apache-2.0 | Resolved `LICENSE.txt` and `NOTICE.txt` |
| `swift-atomics` | Apache-2.0 | Resolved `LICENSE.txt` |
| `swift-collections` | Apache-2.0 | Resolved `LICENSE.txt` |
| `swift-crypto` | Apache-2.0 | Resolved `LICENSE.txt` and `NOTICE.txt` |
| `swift-huggingface` | Apache-2.0 | Vendored `LICENSE` and `UPSTREAM.md` |
| `swift-jinja` | Apache-2.0 | Resolved `LICENSE` |
| `swift-nio` | Apache-2.0 | Resolved `LICENSE.txt` and `NOTICE.txt` |
| `swift-numerics` | Apache-2.0 | Resolved `LICENSE.txt` |
| `swift-syntax` | Apache-2.0 | Resolved `LICENSE.txt` |
| `swift-system` | Apache-2.0 | Resolved `LICENSE.txt` |
| `swift-transformers` | Apache-2.0 | Vendored `LICENSE` and `UPSTREAM.md` |
| `yyjson` | MIT | Resolved `LICENSE` |

`Package.resolved` remains authoritative for remote identities and revisions.
Dependency updates must refresh this verified table, the packaged license and
notice inventory, and the Phase 6 release SBOM together. Upstream `NOTICE` files are
distributed alongside their corresponding licenses when present.

## Default model

Lerro can download `mlx-community/Qwen3.5-4B-MLX-4bit` after explicit user
consent. The model is stored in the user's local cache and is not committed to
this repository or bundled in the application archive. Its model page declares
Apache-2.0 and records the upstream model and conversion metadata:

- <https://huggingface.co/mlx-community/Qwen3.5-4B-MLX-4bit>

Model selection changes must record the model ID, source revision, expected
size, license, and any additional use restrictions before release.

## Apple platform resources

Lerro calls Apple frameworks and uses system-provided typography and symbols.
Those SDK and system resources remain subject to Apple's applicable terms and
are outside the project's Apache-2.0 and CC BY 4.0 grants.

## Website interaction components

The press, ripple, and disclosure interactions under
`site/app/components/interior/` are adapted from
[ddoemonn/interior](https://github.com/ddoemonn/interior) at commit
`3fd448863aac098c474a072bbc1630712504dd0d`. Interior is Copyright (c) 2026 ozzy
and licensed under MIT. The complete license text is preserved in [`NOTICE`](NOTICE).

## Project documentation and brand assets

First-party documentation, screenshots, and reusable templates are licensed
under CC BY 4.0 unless their file-level metadata says otherwise. The Lerro name
and logo remain governed by [TRADEMARKS.md](TRADEMARKS.md). Asset-specific origin
and license data belongs in `Brand/licenses/ASSET-LICENSES.json`.
