# Upstream

Vendored from [`pi-librarian` v1.3.7](https://github.com/default-anton/pi-librarian/tree/021057b5d50d0593b9e245076ae646c4c9e29146) at commit `021057b5d50d0593b9e245076ae646c4c9e29146`.

The behavior source is upstream [`extensions/librarian-core.ts`](https://github.com/default-anton/pi-librarian/blob/021057b5d50d0593b9e245076ae646c4c9e29146/extensions/librarian-core.ts), [`extensions/librarian-prompts.md.ts`](https://github.com/default-anton/pi-librarian/blob/021057b5d50d0593b9e245076ae646c4c9e29146/extensions/librarian-prompts.md.ts), and [`extensions/index.ts`](https://github.com/default-anton/pi-librarian/blob/021057b5d50d0593b9e245076ae646c4c9e29146/extensions/index.ts). Copyright © 2026. Distributed under the Apache-2.0 license in `LICENSE`.

Local changes:

- ported the public schema, prompts, normalization, isolated workspace, and read/bash research behavior into a local adapter;
- replaced upstream model selection with the fixed `openai-codex/gpt-5.6-luna` high policy;
- replaced the upstream child resource loading and progress/session handling with the shared local runtime, progress renderer, and child-only subdirectory-context extension;
- omitted upstream model-selection, release, package, and installation automation.
