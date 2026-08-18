import assert from "node:assert/strict";
import test from "node:test";
import { buildLibrarianSystemPrompt, buildLibrarianUserPrompt } from "./prompt.ts";

test("preserves the evidence-first system prompt contract", () => {
  const prompt = buildLibrarianSystemPrompt(10, "/tmp/pi-librarian/run-test", 30);
  assert.match(prompt, /You are Librarian, an evidence-first GitHub scout\./);
  assert.match(prompt, /may only use the provided tools \(bash\/read\)/);
  assert.match(prompt, /Turn budget: at most 10 turns total/);
  assert.match(prompt, /Tool use is disabled on the final allowed turn/);
  assert.match(prompt, /Keep workspace changes scoped to cache files under `repos\//);
  assert.match(prompt, /Output format \(Markdown, exact section order\)/);
});

test("preserves user prompt scope and limit instructions", () => {
  const prompt = buildLibrarianUserPrompt("locate symbol", ["acme/repo"], ["acme"], 7);
  assert.match(prompt, /Query: locate symbol/);
  assert.match(prompt, /Repository filters: acme\/repo/);
  assert.match(prompt, /Owner filters: acme/);
  assert.match(prompt, /Always pass --limit 7 to gh search code/);
});
