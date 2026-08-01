# Upstream provenance

- Repository: <https://github.com/huggingface/swift-transformers>
- Release: `1.3.3`
- Commit: `2fa33e1f5e7131a7fc64c28e6d161dcec0d24820`
- Imported as a source archive on 2026-07-30.

The root package uses this local copy so its `swift-huggingface` dependency can
resolve to the adjacent patched package at `../swift-huggingface`. The imported
source is otherwise unchanged. Both `Package.swift` and the Swift 6.1 manifest
carry this path override because Swift 6.2 selects `Package@swift-6.1.swift`.
