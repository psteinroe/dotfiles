import assert from "node:assert/strict";
import test from "node:test";
import {
  DelegateCapacity,
  DELEGATE_CONCURRENCY,
  DELEGATE_POLICIES,
  gitDiffArgs,
  truncateDelegateOutput,
} from "./policy.ts";

test("delegate routing keeps the coordinator out of routine implementation", () => {
  assert.deepEqual(DELEGATE_POLICIES.oracle, {
    model: "gpt-5.6-sol",
    thinking: "xhigh",
    maxTurns: 10,
    tools: ["read", "grep", "find", "ls", "git_diff"],
  });
  assert.deepEqual(DELEGATE_POLICIES.worker, {
    model: "gpt-5.6-luna",
    thinking: "high",
    maxTurns: 50,
    tools: ["read", "bash", "edit", "write", "grep", "find", "ls"],
  });
  assert.equal(DELEGATE_POLICIES.oracle.tools.includes("bash"), false);
  assert.equal(DELEGATE_POLICIES.oracle.tools.includes("edit"), false);
});

test("allows one oracle alongside four workers", () => {
  const oracleCapacity = new DelegateCapacity(DELEGATE_CONCURRENCY.oracle);
  const workerCapacity = new DelegateCapacity(DELEGATE_CONCURRENCY.worker);
  const releaseOracle = oracleCapacity.acquire();
  const releaseWorkers = Array.from({ length: 4 }, () => workerCapacity.acquire());

  assert.throws(() => oracleCapacity.acquire(), /At most 1 delegate/);
  assert.throws(() => workerCapacity.acquire(), /At most 4 delegates/);

  releaseOracle();
  releaseWorkers.forEach((release) => release());
  oracleCapacity.acquire()();
  workerCapacity.acquire()();
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
