import { expect, mock, test } from "bun:test";

mock.module("@earendil-works/pi-tui", () => ({
  Editor: class {},
  Key: {},
  matchesKey: () => false,
  Text: class {},
  truncateToWidth: (text: string, width: number) => text.slice(0, width),
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

function createHarness() {
  let tool: any;

  askUser({
    registerTool(definition: unknown) {
      tool = definition;
    },
  } as any);

  return { tool };
}

const params = {
  question: "Which environment should I deploy to?",
  options: [
    { label: "Preview" },
    { label: "Production" },
  ],
};

test("re-renders cached question lines after a narrow terminal resize", async () => {
  const { tool } = createHarness();
  const narrowWidth = 43;
  let narrowLines: string[] = [];

  await tool.execute("call-resize", params, undefined, undefined, {
    mode: "tui",
    ui: {
      custom(factory: (...args: any[]) => any) {
        return new Promise((resolve) => {
          const component = factory(
            { requestRender() {} },
            {
              fg: (_color: string, text: string) => text,
              bold: (text: string) => text,
            },
            {},
            resolve,
          );
          component.render(80);
          narrowLines = component.render(narrowWidth);
          resolve(null);
        });
      },
    },
  });

  expect(Math.max(...narrowLines.map((line) => line.length))).toBeLessThanOrEqual(
    narrowWidth,
  );
});
