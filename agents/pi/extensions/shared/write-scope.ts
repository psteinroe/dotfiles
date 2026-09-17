import type { ExtensionFactory } from "@earendil-works/pi-coding-agent";
import { isToolCallEventType } from "@earendil-works/pi-coding-agent";
import { canonicalizePath, pathWithinScopes } from "./write-scope-paths.ts";

export { canonicalizePath, pathWithinScopes } from "./write-scope-paths.ts";

/** Block structured Worker file mutations outside its declared coordination lease. */
export function createWorkerWriteScopeExtension(scopes: readonly string[]): ExtensionFactory {
  const canonicalScopes = scopes.map((scope) => canonicalizePath(scope));
  return (pi) => {
    pi.on("tool_call", (event, ctx) => {
      if (!isToolCallEventType("edit", event) && !isToolCallEventType("write", event)) return;
      const rawPath = (event.input as { path?: unknown }).path;
      if (typeof rawPath !== "string" || !rawPath.trim()) {
        return { block: true, reason: "Worker file mutation requires a valid path." };
      }
      const target = canonicalizePath(rawPath, ctx.cwd);
      if (!pathWithinScopes(target, canonicalScopes)) {
        return {
          block: true,
          reason: `Worker write is outside its declared scope: ${target}`,
        };
      }
    });
  };
}
