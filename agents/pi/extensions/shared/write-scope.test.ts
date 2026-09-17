import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { createWorkerWriteScopeExtension } from "./write-scope.ts";

function handlerFor(scopes: string[]) {
  let handler: ((event: any, ctx: any) => unknown) | undefined;
  createWorkerWriteScopeExtension(scopes)({
    on(event: string, candidate: typeof handler) {
      if (event === "tool_call") handler = candidate;
    },
  } as any);
  assert.ok(handler);
  return handler;
}

test("allows structured writes inside scope and blocks outside or malformed paths", () => {
  const root = mkdtempSync(join(tmpdir(), "worker-write-gate-"));
  const allowed = join(root, "src");
  mkdirSync(allowed);
  try {
    const handler = handlerFor([allowed]);
    const ctx = { cwd: root };
    assert.equal(handler({ toolName: "write", input: { path: "src/file.ts" } }, ctx), undefined);
    assert.match(
      (handler({ toolName: "edit", input: { path: "README.md" } }, ctx) as any).reason,
      /outside its declared scope/,
    );
    assert.match(
      (handler({ toolName: "write", input: { path: null } }, ctx) as any).reason,
      /valid path/,
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("blocks writes through a symlink that points outside the scope", () => {
  const root = mkdtempSync(join(tmpdir(), "worker-write-symlink-"));
  const allowed = join(root, "allowed");
  const outside = join(root, "outside");
  mkdirSync(allowed);
  mkdirSync(outside);
  symlinkSync(outside, join(allowed, "escape"));
  try {
    const result = handlerFor([allowed])(
      { toolName: "write", input: { path: "allowed/escape/file.ts" } },
      { cwd: root },
    ) as any;
    assert.match(result.reason, /outside its declared scope/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
