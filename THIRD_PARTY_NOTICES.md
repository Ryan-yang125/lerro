# Third-party notices

Lerro's only Swift package dependency is Sparkle, used for in-app updates. The
exact revision is recorded in `Package.resolved`. Release artifacts carry the
license file collected from the resolved Sparkle checkout. The release manifest
identifies the inputs used for that build. `script/generate_sbom.py` writes the
release CycloneDX JSON SBOM as `outputs/Lerro-macOS-arm64.cdx.json` from the
`Package.resolved` lock graph and the license evidence checked by
`script/check_third_party_licenses.py`. `script/verify_sbom.py` rechecks that
binding before the SBOM is released.

## Source-package inventory

The license check reads every identity in `Package.resolved`, locates the
corresponding resolved checkout `LICENSE*`, detects the license from its actual
text, and compares the result with this table.

| Package identity | Verified license | Evidence packaged for release |
| --- | --- | --- |
| `sparkle` | MIT | Resolved binary artifact `LICENSE` |

`Package.resolved` remains authoritative for remote identities and revisions.
A dependency update must refresh this table, the packaged license inventory, and
the release SBOM together.

## Apple platform resources

Lerro calls Apple frameworks and uses system-provided typography and symbols.
Those SDK and system resources remain subject to Apple's applicable terms and
are outside the project's Apache-2.0 and CC BY 4.0 grants.

## Website and tooling

The website under `site/` uses npm packages (Astro, TypeScript, Wrangler and
their dependencies) at build time. They are not part of the macOS app. Versions
are pinned in `site/package-lock.json`, and each package carries its own license.
The update Worker under `distribution/` has no npm dependencies.

## Project documentation and brand assets

First-party documentation, screenshots, and reusable templates are licensed
under CC BY 4.0 unless their file-level metadata says otherwise. The Lerro name
and logo remain governed by [TRADEMARKS.md](TRADEMARKS.md). Asset-specific origin
and license data belongs in `Brand/licenses/ASSET-LICENSES.json`.
