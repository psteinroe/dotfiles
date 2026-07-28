import { expect, mock, test } from "bun:test";
import { rm } from "node:fs/promises";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";

mock.module("@earendil-works/pi-tui", () => ({
  Editor: class {},
  Key: {},
  matchesKey: () => false,
  Text: class {},
  truncateToWidth: (text: string) => text,
}));
mock.module("typebox", () => ({
  Type: {
    Array: (items: unknown, options: unknown) => ({ items, options }),
    Object: (properties: unknown) => ({ properties }),
    Optional: (schema: unknown) => schema,
    String: (options: unknown) => ({ options }),
  },
}));

const { default: askUser } = await import("./index.ts");

type EmittedEvent = {
  name: string;
  data: unknown;
};

function createHarness() {
  let tool: any;
  const events: EmittedEvent[] = [];

  askUser({
    registerTool(definition: unknown) {
      tool = definition;
    },
    events: {
      emit(name: string, data: unknown) {
        events.push({ name, data });
      },
    },
  } as any);

  return { events, tool };
}

async function waitFor(predicate: () => boolean) {
  const deadline = Date.now() + 1_000;
  while (!predicate()) {
    if (Date.now() >= deadline) {
      throw new Error("Timed out waiting for ask_user lifecycle event");
    }
    await Bun.sleep(1);
  }
}

const params = {
  question: "Which environment should I deploy to?",
  options: [
    { label: "Preview" },
    { label: "Production" },
  ],
};

test("reports blocked to Herdr only while waiting for user input", async () => {
  const { events, tool } = createHarness();
  let resolveQuestion: ((value: unknown) => void) | undefined;

  const execution = tool.execute("call-1", params, undefined, undefined, {
    mode: "tui",
    ui: {
      custom() {
        return new Promise((resolve) => {
          resolveQuestion = resolve;
        });
      },
    },
  });

  await waitFor(() => resolveQuestion !== undefined);
  expect(events).toEqual([
    {
      name: "herdr:blocked",
      data: { active: true, label: params.question },
    },
  ]);

  resolveQuestion?.({ answer: "Preview", wasCustom: false, index: 1 });
  await execution;

  expect(events).toEqual([
    {
      name: "herdr:blocked",
      data: { active: true, label: params.question },
    },
    {
      name: "herdr:blocked",
      data: { active: false },
    },
  ]);
});

test("does not report blocked when no interactive UI is available", async () => {
  const { events, tool } = createHarness();

  await tool.execute("call-2", params, undefined, undefined, {
    mode: "print",
    ui: {},
  });

  expect(events).toEqual([]);
});

test("changes the live Herdr pane from working to blocked while awaiting input", async () => {
  const socketPath = join(tmpdir(), `ask-user-herdr-${process.pid}.sock`);
  await rm(socketPath, { force: true });

  const states: string[] = [];
  const server = createServer((socket) => {
    let input = "";
    socket.setEncoding("utf8");
    socket.on("data", (chunk) => {
      input += chunk;
      const newline = input.indexOf("\n");
      if (newline === -1) return;
      const request = JSON.parse(input.slice(0, newline));
      if (request.method === "pane.report_agent") {
        states.push(request.params.state);
      }
      socket.end("{}\n");
    });
  });
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(socketPath, resolve);
  });

  const originalEnvironment = {
    HERDR_ENV: process.env.HERDR_ENV,
    HERDR_PANE_ID: process.env.HERDR_PANE_ID,
    HERDR_SOCKET_PATH: process.env.HERDR_SOCKET_PATH,
  };
  process.env.HERDR_ENV = "1";
  process.env.HERDR_PANE_ID = "test:p1";
  process.env.HERDR_SOCKET_PATH = socketPath;

  try {
    let tool: any;
    const handlers = new Map<string, Array<(event: any, ctx: any) => unknown>>();
    const eventHandlers = new Map<string, Array<(data: any) => unknown>>();
    const pi = {
      registerTool(definition: unknown) {
        tool = definition;
      },
      on(name: string, handler: (event: any, ctx: any) => unknown) {
        const registered = handlers.get(name) ?? [];
        registered.push(handler);
        handlers.set(name, registered);
      },
      events: {
        on(name: string, handler: (data: any) => unknown) {
          const registered = eventHandlers.get(name) ?? [];
          registered.push(handler);
          eventHandlers.set(name, registered);
          return () => {};
        },
        emit(name: string, data: unknown) {
          for (const handler of eventHandlers.get(name) ?? []) handler(data);
        },
      },
    };

    const { default: installHerdrState } = await import(
      `../herdr-agent-state.ts?ask-user-test=${Date.now()}`
    );
    installHerdrState(pi as any);
    askUser(pi as any);

    const context = {
      hasUI: true,
      sessionManager: {
        getSessionFile: () => undefined,
        getSessionId: () => undefined,
      },
    };
    for (const handler of handlers.get("session_start") ?? []) {
      await handler({ reason: "startup" }, context);
    }
    for (const handler of handlers.get("agent_start") ?? []) {
      await handler({}, context);
    }
    await waitFor(() => states.at(-1) === "working");

    let resolveQuestion: ((value: unknown) => void) | undefined;
    const execution = tool.execute("call-3", params, undefined, undefined, {
      mode: "tui",
      ui: {
        custom() {
          return new Promise((resolve) => {
            resolveQuestion = resolve;
          });
        },
      },
    });

    await waitFor(() => states.at(-1) === "blocked");
    resolveQuestion?.({ answer: "Preview", wasCustom: false, index: 1 });
    await execution;
    await waitFor(() => states.at(-1) === "working");

    expect(states).toEqual(["idle", "working", "blocked", "working"]);
  } finally {
    await new Promise<void>((resolve, reject) => {
      server.close((error) => (error ? reject(error) : resolve()));
    });
    await rm(socketPath, { force: true });
    for (const [name, value] of Object.entries(originalEnvironment)) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
  }
});
