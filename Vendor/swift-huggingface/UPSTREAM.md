# swift-huggingface vendoring record

This directory vendors `huggingface/swift-huggingface` for macOS download
progress, cancellation, cache validation, and temporary-file lifecycle fixes
required by the Lerro local model flow.

- Upstream repository: `https://github.com/huggingface/swift-huggingface`
- Upstream release baseline: `0.9.0`
- Upstream baseline commit: `b721959445b617d0bf03910b2b4aced345fd93bf`
- Imported progress-fix commit: `4abcf1485f3e06456140a1e0d33e72fa0bff273a`
- Imported patch source: upstream pull request `#50`
- Progress tracking snapshot: upstream pull request
  [`#50`](https://github.com/huggingface/swift-huggingface/pull/50) was Open on
  2026-07-30.
- Temporary-file tracking snapshot: upstream issue
  [`#52`](https://github.com/huggingface/swift-huggingface/issues/52) was Open on
  2026-07-30.
- Local patch: completed downloads are installed through a unique staging file
  in the blobs directory. The installer attempts a same-volume hard link,
  falls back to a staging copy, verifies sizes, and atomically publishes or
  replaces the final blob before committing snapshot/ref metadata. The source
  is consumed only after metadata succeeds.
- Local cancellation patch: the Apple download bridge uses a lock-backed
  `DownloadTaskBox` to remember cancellation requested before the
  `URLSessionDownloadTask` is installed. The delegate maps
  `URLError.cancelled` to `CancellationError`.
- Local cleanup patch: both ETag-aware and generic download paths install a
  `defer` immediately after receiving a temporary URL, covering every later
  success and failure exit.
- Local cache-validation patch: `FileMetadata` reads `X-Linked-Size`. A
  positive linked size that differs from an existing ETag blob removes that
  blob before the cached-path fast path, allowing a complete download to
  replace the truncated entry.
- Resume boundary: automatic Range merging starts from an existing
  `<etag>.incomplete` file. A first network interruption or cancellation does
  not persist response bytes or `URLSession` resume data for a later request or
  app launch.

The progress import owns the Apple `hfAsyncDownload` bridge and its original
progress tests. The Lerro-local patch owns the bridge cancellation
guard and error normalization, post-download temporary-URL cleanup,
`X-Linked-Size` preflight validation, `HubCache.storeFile(consumeSource:)`, the
download call-site opt-in, first-write/duplicate-blob source-consumption tests,
snapshot/ref commit failure-injection tests, truncated-blob recovery, and the
explicit-destination fallback after snapshot failure. Snapshot or ref failure
keeps the original temporary source available to `HubCache`; `HubClient` can
move that payload to an explicit destination when cache publication misses.
Keep those ownership boundaries and the resume boundary explicit while
comparing future upstream releases.

The upstream Apache 2.0 license remains in [`LICENSE`](LICENSE). Before updating
this directory, compare the new upstream release with the two fixes above,
remove superseded local changes, run the vendored package tests, then run the
Lerro Release gate and the opt-in live model smoke test.
