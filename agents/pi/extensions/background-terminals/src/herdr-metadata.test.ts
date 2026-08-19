import assert from "node:assert/strict";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { rm } from "node:fs/promises";
import test from "node:test";
import { HerdrBackgroundMetadata } from "./herdr-metadata.ts";

test(
  "labels idle and done as background while terminals run, then clears the labels",
  { skip: process.platform === "win32" },
  async () => {
    const socketPath = join(tmpdir(), `background-herdr-${process.pid}-${Date.now()}.sock`);
    await rm(socketPath, { force: true });
    const requests: any[] = [];
    const server = createServer((socket) => {
      let input = "";
      socket.setEncoding("utf8");
      socket.on("data", (chunk) => {
        input += chunk;
        const newline = input.indexOf("\n");
        if (newline === -1) return;
        const request = JSON.parse(input.slice(0, newline));
        requests.push(request);
        socket.end(`${JSON.stringify({ id: request.id, result: { type: "ok" } })}\n`);
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
      const metadata = new HerdrBackgroundMetadata();
      await metadata.setActive(true);
      await metadata.setActive(true);
      await metadata.setActive(false);
      await metadata.shutdown();
      await metadata.setActive(true);

      assert.equal(requests.length, 2);
      assert.equal(requests[0]?.method, "pane.report_metadata");
      assert.deepEqual(requests[0]?.params.state_labels, {
        idle: "background",
        done: "background",
      });
      assert.equal(requests[0]?.params.applies_to_source, "herdr:pi");
      assert.equal(requests[0]?.params.ttl_ms, 86_400_000);
      assert.equal(requests[1]?.params.clear_state_labels, true);
      assert.ok(requests[1]?.params.seq > requests[0]?.params.seq);
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
  },
);

test(
  "retries an unacknowledged report with the same id and sequence",
  { skip: process.platform === "win32" },
  async () => {
    const socketPath = join(tmpdir(), `background-herdr-retry-${process.pid}-${Date.now()}.sock`);
    await rm(socketPath, { force: true });
    const requests: any[] = [];
    const server = createServer((socket) => {
      let input = "";
      socket.setEncoding("utf8");
      socket.on("data", (chunk) => {
        input += chunk;
        const newline = input.indexOf("\n");
        if (newline === -1) return;
        const request = JSON.parse(input.slice(0, newline));
        requests.push(request);
        if (requests.length === 1) socket.end();
        else socket.end(`${JSON.stringify({ id: request.id, result: { type: "ok" } })}\n`);
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
      await new HerdrBackgroundMetadata().setActive(true);
      assert.equal(requests.length, 2);
      assert.equal(requests[1]?.id, requests[0]?.id);
      assert.equal(requests[1]?.params.seq, requests[0]?.params.seq);
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
  },
);

test("is inert outside a Herdr pane", async () => {
  const original = process.env.HERDR_ENV;
  delete process.env.HERDR_ENV;
  try {
    const metadata = new HerdrBackgroundMetadata();
    await metadata.setActive(true);
    await metadata.shutdown();
  } finally {
    if (original === undefined) delete process.env.HERDR_ENV;
    else process.env.HERDR_ENV = original;
  }
});
