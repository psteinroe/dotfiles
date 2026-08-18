import assert from "node:assert/strict";
import test from "node:test";
import { formatToolCall, shorten, type DelegateToolCall } from "./progress.ts";

function call(name: string, args: unknown): DelegateToolCall {
  return { id: name, name, args, startedAt: 0 };
}

test("formats delegate tool activity without dumping file contents", () => {
  assert.equal(formatToolCall(call("read", { path: "src/a.ts", offset: 4, limit: 3 })), "read src/a.ts:4-6");
  assert.equal(formatToolCall(call("grep", { pattern: "needle", path: "src" })), "grep needle in src");
  assert.equal(formatToolCall(call("edit", { path: "src/a.ts", edits: [{}, {}] })), "edit src/a.ts (2 changes)");
  assert.equal(formatToolCall(call("write", { path: "out.txt", content: "secret text" })), "write out.txt (11 chars)");
  assert.equal(formatToolCall(call("git_diff", { target: "staged" })), "git diff staged");
});

test("shortens long activity labels", () => {
  assert.equal(shorten("abcdef", 4), "abcd…");
  assert.equal(shorten("abc", 4), "abc");
});
