import assert from "node:assert/strict";
import test from "node:test";

test("preserves Finder's public schema and reconnaissance prompt", async () => {
  const { FinderParams } = await import("./finder-core.ts");
  const { buildFinderSystemPrompt, buildFinderUserPrompt } = await import(
    "./finder-prompts.md.ts"
  );
  const description = (FinderParams as any).properties.query.description as string;
  assert.equal((FinderParams as any).type, "object");
  assert.equal((FinderParams as any).required.includes("query"), true);
  assert.match(description, /end goal for reconnaissance/);
  assert.match(description, /do not request grep or find/);
  assert.match(buildFinderSystemPrompt(), /You are Finder, an evidence-first workspace scout\./);
  assert.match(buildFinderSystemPrompt(), /may only use the provided tools \(bash\/read\)/);
  assert.equal(
    buildFinderUserPrompt("  map the auth entrypoint  "),
    "Task: perform one-shot reconnaissance in the workspace and return an evidence-backed map that answers the query and minimizes follow-up scouting.\nFollow the system instructions for tools, citations, and output format.\nRespond with findings directly; skip rephrasing the task.\n\nQuery:\nmap the auth entrypoint",
  );
});
