# Upstream

Vendored from [`@parke.dev/pi-background-terminals@0.1.0`](https://github.com/LukasParke/pi-extensions/tree/2626ae9e80f41c86ac5ee8eb00e8cd357927ba6b/packages/pi-background-terminals) at commit `2626ae9e80f41c86ac5ee8eb00e8cd357927ba6b`.

Copyright © 2026 Luke Parke. Distributed under the MIT license in `LICENSE`.

Local changes:

- renamed the extension entry point to `index.ts` and adjusted its relative manager import;
- added Pi prompt metadata for explicit parallel background starts;
- expanded one TypeScript parameter property for Node's strip-only test runner;
- copied the bundled skill to `agents/skills/background-terminals` and corrected its runtime descriptions;
- made completion delivery lifecycle-aware so terminals that settle after the agent becomes idle still resume it, with deduplication, retry, and shutdown-safe timer cleanup.
