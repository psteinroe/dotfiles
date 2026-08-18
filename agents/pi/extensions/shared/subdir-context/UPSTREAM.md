# Upstream

Vendored from [`pi-subdir-context` v1.1.7](https://github.com/default-anton/pi-subdir-context/tree/5d58a8b0533689eb91105b89f31d182199188d4e) at commit `5d58a8b0533689eb91105b89f31d182199188d4e`.

The behavior source is upstream [`src/index.ts`](https://github.com/default-anton/pi-subdir-context/blob/5d58a8b0533689eb91105b89f31d182199188d4e/src/index.ts). Copyright © 2026. Distributed under the MIT license in `LICENSE`.

Local changes:

- preserved the upstream default export as an `ExtensionFactory` and placed it under `agents/pi/extensions/shared/subdir-context/src/`; this nested path is intentionally not a top-level Pi extension and is not globally autoloaded;
- added `src/index.test.ts` characterization tests covering precedence, root-to-leaf order, deduplication and session reset, cwd/home confinement, failed and non-read results, manual context reads, appending results, and UI error notification.

No behavior changes were made to the vendored source.
