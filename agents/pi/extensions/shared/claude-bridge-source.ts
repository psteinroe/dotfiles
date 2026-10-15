import { createHash } from "node:crypto";
import { cpSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import * as path from "node:path";

// Source overlay for the exact bridge revision pinned in both settings files.
// No managed package or Nix-store files are modified. Remove this overlay when
// upstream exposes typed terminal rejections and safe tool-result continuation.
export const BRIDGE_INDEX_SHA256 = "e13fb578f0ace3a677fb7cbefe55ebca009d7ef28fffea93c4bbb77df84f8fad";

function replaceOnce(source: string, before: string, after: string): string {
  if (source.split(before).length !== 2) throw new Error("Claude Bridge source overlay no longer matches the pinned bridge; review before upgrading.");
  return source.replace(before, after);
}

export function patchClaudeBridgeSource(source: string): string {
  if (createHash("sha256").update(source).digest("hex") !== BRIDGE_INDEX_SHA256) {
    throw new Error("Claude Bridge source differs from the reviewed pin; refusing to install usage-wait overlay.");
  }
  source = replaceOnce(source,
    '\t\t\tresultError = resultErrorText(message);',
    `\t\t\t// A rejection belongs to this result only, including successful results.
\t\t\tconst rejection = queryCtx.rateLimitRejection;
\t\t\tqueryCtx.rateLimitRejection = null;
\t\t\tif (queryCtx.turnOutput) delete (queryCtx.turnOutput as any).claudeUsageLimit;
\t\t\tresultError = resultErrorText(message);`);
  source = replaceOnce(source,
    `\t\t\t\tif (queryCtx.rateLimitRejection) {
\t\t\t\t\tresultError = describeRateLimitFailure(queryCtx.rateLimitRejection, resultError);
\t\t\t\t\tqueryCtx.rateLimitRejection = null;
\t\t\t\t}`,
    `\t\t\t\tif (rejection) {
\t\t\t\t\tresultError = describeRateLimitFailure(rejection, resultError);
\t\t\t\t\tif (queryCtx.turnOutput) (queryCtx.turnOutput as any).claudeUsageLimit = { ...rejection };
\t\t\t\t}`);
  source = replaceOnce(source,
    '\t\t\tif (info?.status === "rejected") {',
    '\t\t\tif (info?.status !== "rejected") queryCtx.rateLimitRejection = null;\n\t\t\tif (info?.status === "rejected") {');
  source = replaceOnce(source,
    '\t\t\tcase "assistant":\n\t\t\t\tprocessAssistantMessage(message, model, customToolNameToPi, queryCtx);',
    `\t\t\tcase "assistant":
\t\t\t\t// A typed permanent API error wins over an earlier quota event.
\t\t\t\tif ((message as any).error && !["rate_limit", "unknown"].includes((message as any).error)) queryCtx.rateLimitRejection = null;
\t\t\t\t// CC's synthetic failure prose is diagnostic, not model output. Do not
\t\t\t\t// stream it as partial content when a fresh rejection identifies it.
\t\t\t\tif (queryCtx.rateLimitRejection && (message as any).message?.model === "<synthetic>") break;
\t\t\t\tprocessAssistantMessage(message, model, customToolNameToPi, queryCtx);`);
  source = replaceOnce(source,
    '\tif (lastMsg?.role === "toolResult") {',
    '\tif (lastMsg?.role === "toolResult" && !(options as any)?.claudeUsageRetry) {');
  source = replaceOnce(source,
    '\tconst syncResult = syncSharedSession(context.messages, cwd, customToolNameToSdk, cliModel);',
    `\t// A retry resumes from Pi's authoritative context, including completed tool
\t// results. Never re-deliver MCP results or resume CC's failed synthetic turn.
\tif ((options as any)?.claudeUsageRetry && sharedSession) sharedSession = { ...sharedSession, needsRebuild: true, forceRotate: true };
\tconst syncResult = syncSharedSession(context.messages, cwd, customToolNameToSdk, cliModel);`);
  return source;
}

export function prepareClaudeBridgeSource(entryPath: string): { entryPath: string; dispose: () => void } {
  const patched = patchClaudeBridgeSource(readFileSync(entryPath, "utf8"));
  const root = mkdtempSync(path.join(tmpdir(), "pi-claude-bridge-source-"));
  const dispose = () => rmSync(root, { recursive: true, force: true });
  try {
    // Copy, not symlink, source modules: QueryContext must be isolated per session.
    cpSync(path.dirname(entryPath), path.join(root, "src"), { recursive: true });
    writeFileSync(path.join(root, "src/index.ts"), patched);
    const statePath = path.join(root, "src/query-state.ts");
    const stateSource = readFileSync(statePath, "utf8");
    if (createHash("sha256").update(stateSource).digest("hex") !== "001e947f1b52bac2bb6733f5c5463bbd1fe8df245d65e29cb843749e82ea9258") {
      throw new Error("Claude Bridge query state differs from the reviewed pin; refusing usage-wait overlay.");
    }
    writeFileSync(statePath, replaceOnce(stateSource,
      '\tresetTurnState(model: Model<any>): void {',
      '\tresetTurnState(model: Model<any>): void {\n\t\tthis.rateLimitRejection = null;'));
    symlinkSync(path.resolve(path.dirname(entryPath), "../node_modules"), path.join(root, "node_modules"), "dir");
    writeFileSync(path.join(root, "package.json"), '{"type":"module"}\n');
    return { entryPath: path.join(root, "src/index.ts"), dispose };
  } catch (error) {
    dispose();
    throw error;
  }
}
