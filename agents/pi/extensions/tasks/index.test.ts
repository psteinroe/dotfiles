import assert from "node:assert/strict";
import test from "node:test";
import installTasks from "./index.ts";

type Handler = (event: any, context: any) => unknown;

function harness() {
  const handlers = new Map<string, Handler[]>();
  const tools = new Map<string, any>();
  const messages: any[] = [];
  const pi = {
    on(name: string, handler: Handler) {
      handlers.set(name, [...(handlers.get(name) ?? []), handler]);
    },
    registerTool(tool: any) { tools.set(tool.name, tool); },
    registerCommand() {},
    sendMessage(message: any, options: any) { messages.push({ message, options }); },
    getAllTools() { return []; },
  };
  installTasks(pi as any);
  return { handlers, tools, messages };
}

async function emit(handlers: Map<string, Handler[]>, name: string, context: any) {
  for (const handler of handlers.get(name) ?? []) await handler({ type: name }, context);
}

async function waitFor(predicate: () => boolean) {
  const deadline = Date.now() + 2_000;
  while (!predicate()) {
    if (Date.now() > deadline) throw new Error("Timed out waiting for task completion");
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
}

function context() {
  return {
    cwd: process.cwd(),
    mode: "print",
    hasUI: false,
    isIdle: () => true,
    hasPendingMessages: () => false,
    ui: { setStatus() {}, setWidget() {}, theme: { fg: (_name: string, text: string) => text } },
  };
}

test("registers one consolidated task surface", async () => {
  const h = harness();
  assert.deepEqual([...h.tools.keys()].sort(), [
    "start_background_command",
    "start_subagent",
    "task_cancel",
    "task_list",
    "task_result",
    "task_status",
  ]);
  for (const legacy of ["bg_start", "bg_status", "bg_list", "bg_kill", "finder", "librarian", "oracle", "worker"]) {
    assert.equal(h.tools.has(legacy), false);
  }
  await emit(h.handlers, "session_shutdown", context());
});

test("subagent guidance makes delegated scope an ownership lease", async () => {
  const h = harness();
  const start = h.tools.get("start_subagent");
  const guidance = [start.description, start.promptSnippet, ...start.promptGuidelines].join("\n");
  assert.match(guidance, /delegated scope.*owned by (?:that|the) subagent/i);
  assert.match(guidance, /disjoint work/i);
  assert.match(guidance, /end the turn/i);
  assert.match(guidance, /write_scope is Worker-only/i);
  assert.match(start.description, /Mapper=where\/what/);
  assert.match(start.description, /Oracle=why\/correctness\/what should change/);
  assert.match(start.description, /Worker=execution\/implementation/);
  assert.match(start.description, /Librarian=GitHub research/);
  assert.match((start.parameters as any).properties.agent.description, /Mapper=where\/what/);

  const cancel = h.tools.get("task_cancel");
  assert.match(cancel.description, /requirements change/i);
  assert.match(cancel.description, /duplicat(?:e|ed|ion).*not.*reason/i);
  await emit(h.handlers, "session_shutdown", context());
});

test("live task widget omits elapsed time while explicit status computes it on demand", async () => {
  const h = harness();
  const ctx = context();
  const widgets: unknown[] = [];
  ctx.hasUI = true;
  ctx.ui.setWidget = (_key: string, value: unknown) => widgets.push(value);
  await emit(h.handlers, "session_start", ctx);
  await h.tools.get("start_background_command").execute(
    "call",
    { command: "sleep 1", title: "timing fixture" },
    undefined,
    undefined,
    ctx,
  );

  const activeWidget = [...widgets].reverse().find((value) => Array.isArray(value) && value.length > 0) as string[];
  assert.ok(activeWidget, "active task widget was not rendered");
  assert.doesNotMatch(activeWidget[0], /\s(?:\d+s|\d+m\d+s|\d+h\d+m)$/);

  const status = await h.tools.get("task_status").execute("status", { id: "task-1" });
  assert.match(status.content[0].text, /\s(?:\d+s|\d+m\d+s|\d+h\d+m)(?:\n|$)/);
  await emit(h.handlers, "session_shutdown", ctx);
});

test("background command launch returns before completion and delivers once", async () => {
  const h = harness();
  const ctx = context();
  await emit(h.handlers, "session_start", ctx);
  const startedAt = Date.now();
  const launch = await h.tools.get("start_background_command").execute(
    "call",
    { command: "sleep 0.25; printf complete", title: "fixture" },
    undefined,
    undefined,
    ctx,
  );
  assert.ok(Date.now() - startedAt < 100);
  assert.match(launch.content[0].text, /Started task-1/);
  assert.equal(h.messages.length, 0);
  const live = await h.tools.get("task_status").execute("status", { id: "task-1" });
  assert.match(live.content[0].text, /Background command running/);

  await waitFor(() => h.messages.length === 1);
  assert.deepEqual(h.messages[0].options, { deliverAs: "followUp", triggerTurn: true });
  assert.match(h.messages[0].message.content, /complete/);
  await emit(h.handlers, "session_shutdown", ctx);
});

test("rejects profile-incompatible fields and unsafe Worker scopes", async () => {
  const h = harness();
  const ctx = context();
  await emit(h.handlers, "session_start", ctx);
  await assert.rejects(
    h.tools.get("start_subagent").execute(
      "call",
      { agent: "mapper", task: "map", write_scope: ["src"] },
      undefined,
      undefined,
      ctx,
    ),
    /write_scope applies only to Worker/,
  );
  await assert.rejects(
    h.tools.get("start_subagent").execute(
      "call",
      { agent: "worker", task: "edit", write_scope: ["."] },
      undefined,
      undefined,
      ctx,
    ),
    /entire repository/,
  );
  await emit(h.handlers, "session_shutdown", ctx);
});

test("rejects a background command while a Worker is active", async () => {
  const h = harness();
  const ctx = context();
  await emit(h.handlers, "session_start", ctx);
  const workerLaunch = h.tools.get("start_subagent").execute(
    "call",
    {
      agent: "worker",
      task: "hold the Worker lease",
      write_scope: ["agents/pi/extensions/tasks/index.ts"],
    },
    undefined,
    undefined,
    ctx,
  );
  await assert.rejects(
    h.tools.get("start_background_command").execute(
      "call",
      { command: "sleep 1", title: "blocked" },
      undefined,
      undefined,
      ctx,
    ),
    /Worker .* is active/,
  );
  await workerLaunch;
  await emit(h.handlers, "session_shutdown", ctx);
});

test("rejects a Worker while a background command is active", async () => {
  const h = harness();
  const ctx = context();
  await emit(h.handlers, "session_start", ctx);
  await h.tools.get("start_background_command").execute(
    "call",
    { command: "sleep 1", title: "active" },
    undefined,
    undefined,
    ctx,
  );
  await assert.rejects(
    h.tools.get("start_subagent").execute(
      "call",
      {
        agent: "worker",
        task: "must be excluded by the command",
        write_scope: ["agents/pi/extensions/tasks/index.ts"],
      },
      undefined,
      undefined,
      ctx,
    ),
    /background command .* is active/,
  );
  await emit(h.handlers, "session_shutdown", ctx);
});

test("Mapper launch returns a handle without requiring Executor MCP", async () => {
  const h = harness();
  const ctx = context();
  await emit(h.handlers, "session_start", ctx);
  const launch = await h.tools.get("start_subagent").execute(
    "call",
    { agent: "mapper", task: "map the fixture" },
    undefined,
    undefined,
    ctx,
  );
  assert.match(launch.content[0].text, /Started task-1/);
  assert.match(launch.content[0].text, /scope is now owned by the mapper/i);
  assert.match(launch.content[0].text, /disjoint work/i);
  assert.match(launch.content[0].text, /end the turn/i);
  await emit(h.handlers, "session_shutdown", ctx);
});
