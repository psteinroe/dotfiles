import assert from "node:assert/strict";
import test from "node:test";
import { renderBackgroundWidgetLine } from "./src/ui/widget.ts";

const ANSI_SGR_RE = /\u001b\[[0-9;]*m/g;
const visibleWidth = (text: string) => text.replace(ANSI_SGR_RE, "").length;

test("background widget fits a narrow styled terminal", () => {
  const theme = {
    fg: (_color: string, text: string) => `\u001b[33m${text}\u001b[39m`,
  };
  const truncate = (text: string, width: number) =>
    text.replace(ANSI_SGR_RE, "").slice(0, width);
  const width = 43;

  const line = renderBackgroundWidgetLine(1, width, theme, truncate);

  assert.ok(
    visibleWidth(line) <= width,
    `widget width ${visibleWidth(line)} exceeds terminal width ${width}`,
  );
});
