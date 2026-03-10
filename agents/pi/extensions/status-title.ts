import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { spawn } from "node:child_process";

const NVIM_SERVER = process.env.NVIM;

const STATUS_EXPR = {
  working: `luaeval('require("config.status-title").set("working")')`,
  done: `luaeval('require("config.status-title").set("done")')`,
} as const;

type Status = keyof typeof STATUS_EXPR;

function setStatus(status: Status) {
  if (!NVIM_SERVER) {
    return;
  }

  const child = spawn("nvim", ["--server", NVIM_SERVER, "--remote-expr", STATUS_EXPR[status]], {
    stdio: "ignore",
  });

  child.on("error", () => {
    // Ignore missing nvim binary/socket failures.
  });
}

export default function statusTitleExtension(pi: ExtensionAPI) {
  pi.on("agent_start", async () => {
    setStatus("working");
  });

  pi.on("agent_end", async () => {
    setStatus("done");
  });
}
