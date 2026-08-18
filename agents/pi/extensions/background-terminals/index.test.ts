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

test("delivers a terminal that settles after an already-idle agent", async () => {
  const { handlers, messages, tools } = createHarness();
  const context = {
    cwd: process.cwd(),
    hasUI: false,
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
