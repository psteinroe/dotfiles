import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

function expandHome(candidate: string): string {
  if (candidate === "~") return os.homedir();
  return candidate.startsWith("~/") ? path.join(os.homedir(), candidate.slice(2)) : candidate;
}

/** Canonicalize the nearest existing ancestor, then append any missing suffix. */
export function canonicalizePath(candidate: string, cwd = process.cwd()): string {
  const absolute = path.resolve(cwd, expandHome(candidate.replace(/^@/, "")));
  const missing: string[] = [];
  let existing = absolute;
  while (!fs.existsSync(existing)) {
    const parent = path.dirname(existing);
    if (parent === existing) break;
    missing.unshift(path.basename(existing));
    existing = parent;
  }
  let canonical = existing;
  try {
    canonical = fs.realpathSync.native(existing);
  } catch {
    canonical = path.resolve(existing);
  }
  return path.join(canonical, ...missing);
}

export function pathWithinScopes(candidate: string, scopes: readonly string[]): boolean {
  return scopes.some((scope) =>
    candidate === scope || candidate.startsWith(`${scope}${path.sep}`));
}
