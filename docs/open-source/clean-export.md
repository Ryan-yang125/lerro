# Clean public export

`script/public_repo_allowlist.txt` is the publication boundary.
`script/export_public_repo.sh` copies only those entries into
`clean-public/lerro`, runs the content scan, initializes a new `main` Git
repository with no remote, and reruns the history-aware scan.

## Generate the local public repository

From the private research workspace:

```zsh
./script/export_public_repo.sh
```

The command refuses an existing destination by default. After reviewing the
current destination, an explicit replacement uses:

```zsh
./script/export_public_repo.sh --replace
```

The destination is fixed beneath `clean-public/` unless `--destination` names
another validated path beneath that directory. The source repository ignores
the entire `clean-public/` tree.

The export initializes an empty Git history and configures no remote. Creating
the first public commit, configuring the official remote, pushing, enabling
Private Vulnerability Reporting, and making the repository visible are separate
maintainer actions.

## Gates

The scanner checks:

- Every exported path is covered by the allowlist.
- Required governance and license files are present.
- Research, output, build, archive, database, recording, model-weight, and local
  workspace paths are absent.
- Common credential forms, private keys, signing identity values, certificate
  email addresses, Team IDs, and notary credentials are absent.
- Legacy identity strings occur only in explicitly allowlisted migration or
  compatibility files that also contain migration context.
- Vendored packages retain nonempty `LICENSE` and `UPSTREAM.md` files.
- `script/generate_sbom.py` and `script/verify_sbom.py` are public source;
  generated `outputs/Lerro-macOS-arm64.cdx.json` remains a release artifact
  outside the export boundary.
- Brand assets have an asset-license manifest when the Brand directory exists.
- Binary executables and release containers are absent; approved source assets
  such as icons and images remain allowed in their designated directories,
  including first-party website assets under `site/public/`.
- Website source under `site/` is present while `.git`, `node_modules`, `dist`,
  `out`, `.wrangler`, `.next`, `.vinext`, `coverage`, `outputs`, and `work` are
  absent.
- Private Wrangler configuration files named `wrangler.toml` are absent. Public
  deployment structure is represented by committed `wrangler.toml.example` or
  `wrangler.jsonc` files only.
- Generated website type declarations such as `next-env.d.ts` are recreated by
  the website build and stay outside the clean source export.
- The new repository has no commits, no remotes, and no inherited Git objects.

Run the same scanner directly at any time:

```zsh
LERRO_LICENSE_SOURCE="$PWD" \
  ./script/scan_public_repo.sh clean-public/lerro
```

`LERRO_LICENSE_SOURCE` points at the private source workspace whose resolved
SwiftPM checkouts provide immutable license evidence. From inside the clean
public export, run `swift package resolve` first and omit the variable.

When `gitleaks` is installed, the scanner invokes it in addition to its built-in
rules. A missing optional scanner is reported and does not weaken the mandatory
built-in checks.

## Pre-publication review

1. Verify the source tree and parallel work are stable.
2. Run focused tests, full `swift test`, and the Release gate.
3. Generate the clean export and inspect its complete file inventory.
4. Run `git diff --no-index` or an equivalent comparison against the allowlist
   expectation.
5. Review every asset origin and license record.
6. Create the first commit from the clean directory using a public maintainer
   identity.
7. Configure the official remote and enable branch protection, secret scanning,
   Dependabot, code scanning, Private Vulnerability Reporting, and immutable
   releases.
8. Build the public release from a clean signed tag; generate and validate the
   CycloneDX SBOM from the current `Package.resolved` and resolved license evidence,
   then attach the source-bound manifest, SBOM, checksums, licenses, dSYM archive,
   and attestation.

The public repository's first commit should be treated as a release input. Any
change after scanning requires a fresh scan and release build.
