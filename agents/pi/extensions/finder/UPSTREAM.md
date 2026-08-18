# Upstream

Vendored from [`default-anton/pi-finder` v1.5.8](https://github.com/default-anton/pi-finder/tree/be44e311a0d35f57b44058f45a5e824fc48a05fe) at commit `be44e311a0d35f57b44058f45a5e824fc48a05fe`.

The behavior source is upstream [`extensions/finder-core.ts`](https://github.com/default-anton/pi-finder/blob/be44e311a0d35f57b44058f45a5e824fc48a05fe/extensions/finder-core.ts), [`extensions/finder-prompts.md.ts`](https://github.com/default-anton/pi-finder/blob/be44e311a0d35f57b44058f45a5e824fc48a05fe/extensions/finder-prompts.md.ts), and the Finder tool in [`extensions/index.ts`](https://github.com/default-anton/pi-finder/blob/be44e311a0d35f57b44058f45a5e824fc48a05fe/extensions/index.ts). Distributed under the Apache-2.0 license in `LICENSE`.

Local changes:

- preserved the upstream Finder schema, description, and prompt;
- replaced upstream model selection with the local fixed `openai-codex/gpt-5.6-luna` medium policy;
- adapted child-session lifecycle, progress tracking/rendering, cancellation, and shutdown cleanup to the local shared APIs;
- installed the vendored subdirectory-context extension only in Finder's isolated child loader;
- omitted upstream model-selection and release/package automation.
