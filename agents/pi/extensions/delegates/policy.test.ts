import assert from "node:assert/strict";
import test from "node:test";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import delegatesExtension, { ORACLE_SYSTEM_PROMPT } from "./adapter.ts";
import {
  DELEGATE_POLICIES,
  gitDiffArgs,
  truncateDelegateOutput,
} from "./policy.ts";

test("delegate routing keeps the coordinator out of routine implementation", () => {
  assert.deepEqual(DELEGATE_POLICIES.oracle, {
    model: "openai-codex/gpt-6-astra",
    thinking: "xhigh",
    maxTurns: 10,
    tools: ["read", "grep", "find", "ls", "git_diff"],
  });
  assert.deepEqual(DELEGATE_POLICIES.worker, {
    model: "claude-bridge/claude-opus-5-5",
    thinking: "high",
    maxTurns: 50,
    tools: ["read", "bash", "edit", "write", "grep", "find", "ls"],
  });
  assert.equal(DELEGATE_POLICIES.oracle.tools.includes("bash"), false);
  assert.equal(DELEGATE_POLICIES.oracle.tools.includes("edit"), false);
});

test("Worker tool wording reflects the Claude default without changing its role", () => {
  const tools: Array<{ name: string; description: string; promptSnippet?: string }> = [];
  const pi: Pick<ExtensionAPI, "registerTool" | "on"> = {
    registerTool: (tool) => { tools.push(tool); },
    on: () => () => {},
  };
  delegatesExtension(pi as ExtensionAPI);
  const worker = tools.find((tool) => tool.name === "worker");
  assert.ok(worker);
  assert.match(worker.description, /Claude Opus 5\.5 high worker/);
  assert.match(worker.description, /does not commit or push/);
  assert.match(worker.promptSnippet ?? "", /Claude Opus 5\.5 worker/);
  assert.doesNotMatch(`${worker.description} ${worker.promptSnippet}`, /GPT|Sol/i);
});

test("Oracle is the default read-only analysis role", () => {
  assert.match(ORACLE_SYSTEM_PROMPT, /default read-only analyst/);
  assert.match(ORACLE_SYSTEM_PROMPT, /WHY, correctness, root cause, architecture, planning, tradeoffs, and review/);
  assert.match(ORACLE_SYSTEM_PROMPT, /state what should change/);
  assert.match(ORACLE_SYSTEM_PROMPT, /evidence-proportional and scoped to the request/);
  assert.match(ORACLE_SYSTEM_PROMPT, /simplest direct change/);
  assert.match(ORACLE_SYSTEM_PROMPT, /only for a concrete failure mode/);
  assert.match(ORACLE_SYSTEM_PROMPT, /low-probability risks when their impact is high/);
  assert.match(ORACLE_SYSTEM_PROMPT, /decisive recommendation rather than cataloging possibilities/);
  assert.doesNotMatch(ORACLE_SYSTEM_PROMPT, /second opinion|do not use for routine work/i);
});

test("git diff targets use fixed non-shell argv", () => {
  assert.deepEqual(gitDiffArgs("working"), ["diff", "--no-ext-diff", "--"]);
  assert.deepEqual(gitDiffArgs("staged"), [
    "diff",
    "--cached",
    "--no-ext-diff",
    "--",
  ]);
  assert.deepEqual(gitDiffArgs("head"), [
    "show",
    "--format=fuller",
    "--no-ext-diff",
    "HEAD",
    "--",
  ]);
});

test("delegate output truncation is explicit", () => {
  assert.deepEqual(truncateDelegateOutput("short", 10), {
    text: "short",
    truncated: false,
  });
  const result = truncateDelegateOutput("12345678901", 10);
  assert.equal(result.truncated, true);
  assert.match(result.text, /^1234567890/);
  assert.match(result.text, /truncated/);
});
