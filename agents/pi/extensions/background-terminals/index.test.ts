import assert from "node:assert/strict";
import test from "node:test";

const { default: installBackgroundTerminals } = await import("./index.ts");

type Handler = (event: any, context: any) => unknown;

function createHarness() {
  const handlers = new Map<string, Handler[]>();
  const tools = new Map<string, any>();
  const messages: Array<{ message: any; options: any }> = [];
  const pi = {
    on(name: string, handler: Handler) {
      handlers.set(name, [...(handlers.get(name) ?? []), handler]);
    },
    registerTool(tool: any) {
      tools.set(tool.name, tool);
    },
    registerCommand() {},
    sendMessage(message: any, options: any) {
      messages.push({ message, options });
    },
  };

  installBackgroundTerminals(pi as any);
  return { handlers, messages, pi, tools };
}

async function emit(handlers: Map<string, Handler[]>, name: string, event: any, context: any) {
  for (const handler of handlers.get(name) ?? []) await handler(event, context);
}

async function waitFor(predicate: () => boolean) {
  const deadline = Date.now() + 1_000;
  while (!predicate()) {
    if (Date.now() >= deadline) throw new Error("Timed out waiting for background terminal delivery");
    await new Promise((resolve) => setTimeout(resolve, 1));
  }
}

test("updates the displayed age while a terminal is running", async () => {
  const { handlers, tools } = createHarness();
  let widget: string[] | undefined;
  const context = {
    cwd: process.cwd(),
    hasUI: true,
    isIdle: () => true,
    hasPendingMessages: () => false,
    ui: {
      theme: { fg: (_color: string, text: string) => text },
      setStatus() {},
      setWidget(_key: string, value: string[] | undefined) {
        widget = value;
      },
    },
  };

  try {
    await emit(handlers, "session_start", { reason: "startup" }, context);
    await tools.get("bg_start").execute(
      "call-age",
      { command: "sleep 2", title: "age terminal" },
      undefined,
      undefined,
      context,
    );

    assert.match(widget?.[0] ?? "", /\(0s\)/);
    await new Promise((resolve) => setTimeout(resolve, 1_100));
    assert.match(widget?.[0] ?? "", /\(1s\)/);
  } finally {
    await emit(handlers, "session_shutdown", {}, context);
  }
});

test("does not deliver during a run that was already active at session start", async () => {
  const { handlers, messages, tools } = createHarness();
  let idle = false;
  const context = {
    cwd: process.cwd(),
    hasUI: false,
    isIdle: () => idle,
    hasPendingMessages: () => false,
    ui: { setStatus() {}, setWidget() {} },
  };

  try {
    await emit(handlers, "session_start", { reason: "reload" }, context);
    await tools.get("bg_start").execute(
      "call-reload",
      { command: "sleep 0.1; printf completion", title: "reload terminal" },
      undefined,
      undefined,
      context,
    );

    await new Promise((resolve) => setTimeout(resolve, 450));
    assert.equal(messages.length, 0);

    idle = true;
    await emit(handlers, "agent_settled", {}, context);
    await waitFor(() => messages.length > 0);
    assert.equal(messages.length, 1);
  } finally {
    await emit(handlers, "session_shutdown", {}, context);
  }
});

test("settlement rechecks live state even when agent_start was missed", async () => {
  const { handlers, messages, tools } = createHarness();
  let idle = true;
  const context = {
    cwd: process.cwd(),
    hasUI: false,
    isIdle: () => idle,
    hasPendingMessages: () => false,
    ui: { setStatus() {}, setWidget() {} },
  };

  try {
    await emit(handlers, "session_start", { reason: "startup" }, context);
    await tools.get("bg_start").execute(
      "call-missed-start",
      { command: "sleep 0.1; printf completion", title: "missed start terminal" },
      undefined,
      undefined,
      context,
    );
    idle = false;

    await new Promise((resolve) => setTimeout(resolve, 450));
    assert.equal(messages.length, 0);

    idle = true;
    await waitFor(() => messages.length > 0);
    assert.equal(messages.length, 1);
  } finally {
    await emit(handlers, "session_shutdown", {}, context);
  }
});

test("does not deliver from agent_settled when another extension already started a run", async () => {
  const { handlers, messages, tools } = createHarness();
  let idle = true;
  const context = {
    cwd: process.cwd(),
    hasUI: false,
    isIdle: () => idle,
    hasPendingMessages: () => false,
    ui: { setStatus() {}, setWidget() {} },
  };

  try {
    await emit(handlers, "session_start", { reason: "startup" }, context);
    idle = false;
    await emit(handlers, "agent_start", {}, context);
    await tools.get("bg_start").execute(
      "call-race",
      { command: "sleep 0.1; printf completion", title: "settled race terminal" },
      undefined,
      undefined,
      context,
    );
    await new Promise((resolve) => setTimeout(resolve, 200));

    await emit(handlers, "agent_settled", {}, context);
    await new Promise((resolve) => setTimeout(resolve, 350));
    assert.equal(messages.length, 0);

    idle = true;
    await emit(handlers, "agent_settled", {}, context);
    await waitFor(() => messages.length > 0);
    assert.equal(messages.length, 1);
  } finally {
    await emit(handlers, "session_shutdown", {}, context);
  }
});

test("delivers a terminal that settles after an already-idle agent", async () => {
  const { handlers, messages, tools } = createHarness();
  const context = {
    cwd: process.cwd(),
    hasUI: false,
    isIdle: () => true,
    hasPendingMessages: () => false,
    ui: { setStatus() {}, setWidget() {} },
  };

  try {
    await emit(handlers, "session_start", { reason: "startup" }, context);
    await emit(handlers, "agent_settled", {}, context);
    await tools.get("bg_start").execute(
      "call-1",
      { command: "sleep 0.35; printf completion", title: "short terminal" },
      undefined,
      undefined,
      context,
    );

    await waitFor(() => messages.length > 0);
    assert.equal(messages.length, 1);
    assert.deepEqual(messages[0]?.options, { deliverAs: "followUp", triggerTurn: true });
  } finally {
    await emit(handlers, "session_shutdown", {}, context);
  }
});
