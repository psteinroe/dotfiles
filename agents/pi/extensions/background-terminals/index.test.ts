import assert from "node:assert/strict";
import { rm } from "node:fs/promises";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test, { after } from "node:test";

const originalHerdrEnvironment = {
  HERDR_ENV: process.env.HERDR_ENV,
  HERDR_PANE_ID: process.env.HERDR_PANE_ID,
  HERDR_SOCKET_PATH: process.env.HERDR_SOCKET_PATH,
};
delete process.env.HERDR_ENV;
delete process.env.HERDR_PANE_ID;
delete process.env.HERDR_SOCKET_PATH;
after(() => {
  for (const [name, value] of Object.entries(originalHerdrEnvironment)) {
    if (value === undefined) delete process.env[name];
    else process.env[name] = value;
  }
});

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

test("tells the agent not to poll or sleep while a terminal runs", async () => {
  const { handlers, tools } = createHarness();
  const context = {
    cwd: process.cwd(),
    hasUI: false,
    isIdle: () => true,
    hasPendingMessages: () => false,
    ui: { setStatus() {}, setWidget() {} },
  };
  const start = tools.get("bg_start");
  const status = tools.get("bg_status");

  try {
    assert.match(start.description, /never use foreground bash with sleep/i);
    assert.ok(start.promptGuidelines.some((guideline: string) => /end the turn/i.test(guideline)));
    assert.match(status.description, /not as a polling or waiting mechanism/i);

    const result = await start.execute(
      "call-guidance",
      { command: "sleep 2", title: "guidance terminal" },
      undefined,
      undefined,
      context,
    );
    assert.match(result.content[0].text, /Do not poll or run foreground sleep/i);
    assert.match(result.content[0].text, /continue useful work or end the turn/i);
  } finally {
    await emit(handlers, "session_shutdown", {}, context);
  }
});

test("renders running terminals without a ticking elapsed-time widget", async () => {
  const { handlers, tools } = createHarness();
  let widget: string[] | undefined;
  let widgetUpdates = 0;
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
        widgetUpdates++;
      },
    },
  };

  try {
    await emit(handlers, "session_start", { reason: "startup" }, context);
    await tools.get("bg_start").execute(
      "call-widget",
      { command: "sleep 2", title: "quiet widget" },
      undefined,
      undefined,
      context,
    );

    assert.equal(widget?.[0], "● bt-1 quiet widget");
    const updatesAfterStart = widgetUpdates;
    await new Promise((resolve) => setTimeout(resolve, 100));
    assert.equal(widgetUpdates, updatesAfterStart);
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

test("does not publish Herdr metadata from a headless session", async () => {
  if (process.platform === "win32") return;
  const socketPath = join(tmpdir(), `background-index-herdr-${process.pid}-${Date.now()}.sock`);
  await rm(socketPath, { force: true });
  let connections = 0;
  const server = createServer((socket) => {
    connections++;
    socket.end();
  });
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(socketPath, resolve);
  });
  process.env.HERDR_ENV = "1";
  process.env.HERDR_PANE_ID = "test:p1";
  process.env.HERDR_SOCKET_PATH = socketPath;

  const { handlers, tools } = createHarness();
  const context = {
    cwd: process.cwd(),
    mode: "print",
    hasUI: false,
    isIdle: () => true,
    hasPendingMessages: () => false,
    ui: { setStatus() {}, setWidget() {} },
  };

  try {
    await emit(handlers, "session_start", { reason: "startup" }, context);
    await tools.get("bg_start").execute(
      "call-headless",
      { command: "sleep 2", title: "headless terminal" },
      undefined,
      undefined,
      context,
    );
    await new Promise((resolve) => setTimeout(resolve, 50));
    assert.equal(connections, 0);
  } finally {
    await emit(handlers, "session_shutdown", {}, context);
    await new Promise<void>((resolve, reject) => {
      server.close((error) => (error ? reject(error) : resolve()));
    });
    await rm(socketPath, { force: true });
    delete process.env.HERDR_ENV;
    delete process.env.HERDR_PANE_ID;
    delete process.env.HERDR_SOCKET_PATH;
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
