import assert from "node:assert/strict";
import test from "node:test";

test("exposes Mapper's WHERE/WHAT schema and strict read-only mapping prompt", async () => {
  const { FinderParams } = await import("./finder-core.ts");
  const { buildFinderSystemPrompt, buildFinderUserPrompt } = await import(
    "./finder-prompts.md.ts"
  );
  const description = (FinderParams as any).properties.query.description as string;
  const systemPrompt = buildFinderSystemPrompt();
  assert.equal((FinderParams as any).type, "object");
  assert.equal((FinderParams as any).required.includes("query"), true);
  assert.match(description, /WHERE\/WHAT/);
  assert.match(description, /Oracle analysis is required/);
  assert.match(systemPrompt, /You are Mapper/);
  assert.match(systemPrompt, /strictly WHERE\/WHAT/);
  assert.match(systemPrompt, /read, grep, find, and ls/);
  assert.doesNotMatch(systemPrompt, /bash|Executor MCP/);
  assert.match(systemPrompt, /must not diagnose root cause/);
  assert.match(systemPrompt, /Oracle analysis is required/);
  assert.equal(
    buildFinderUserPrompt("  map the auth entrypoint  "),
    "Task: map the requested WHERE/WHAT facts in the workspace and return an evidence-backed file-and-line map.\nFollow the system instructions: use only read/search tools, do not analyze WHY or correctness, and state that Oracle analysis is required for requests outside Mapper's scope.\nRespond with findings directly; skip rephrasing the task.\n\nQuery:\nmap the auth entrypoint",
  );
});
