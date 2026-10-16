// Socket bridge for a Claude Code session.
//
// Mods have no Node APIs, so the nitpick mod spawns this process for the
// session's life. It is the Pi extension's bridge with Claude Code on the
// other side: reviews leave as JSON lines on stdout, which the mod turns into
// prompts; the mod reports the session's state to a small HTTP control socket
// next to the bridge socket.

import { chmodSync, rmSync } from "node:fs";
import { createServer } from "node:http";
import { Bridge, shortId } from "../pi/bridge.ts";

const state = { id: "unknown", cwd: process.cwd(), idle: true };

function emit(message: Record<string, unknown>): void {
  try {
    process.stdout.write(JSON.stringify(message) + "\n");
  } catch {
    void shutdown();
  }
}

const bridge = new Bridge({
  session: () => ({ agent: "claude", id: state.id, short: shortId(state.id), cwd: state.cwd, idle: state.idle }),
  // Claude Code cannot steer a turn: the mod's prompt waits until it is idle.
  deliver: (text, meta) => emit({ type: "submit", text, comments: meta.comments }),
});

const controlPath = bridge.path.replace(/\.sock$/, ".ctl");

const control = createServer((req, res) => {
  let body = "";
  req.setEncoding("utf8");
  req.on("data", (chunk: string) => (body += chunk));
  req.on("end", () => {
    if (req.method !== "POST" || req.url !== "/state") {
      res.writeHead(404).end();
      return;
    }
    try {
      const update = JSON.parse(body) as Partial<typeof state>;
      if (typeof update.id === "string") state.id = update.id;
      if (typeof update.cwd === "string") state.cwd = update.cwd;
      if (typeof update.idle === "boolean") state.idle = update.idle;
      res.writeHead(204).end();
    } catch {
      res.writeHead(400).end();
    }
  });
});

let stopping = false;
async function shutdown(): Promise<void> {
  if (stopping) return;
  stopping = true;
  control.close();
  rmSync(controlPath, { force: true });
  await bridge.stop();
  process.exit(0);
}

for (const signal of ["SIGTERM", "SIGINT", "SIGHUP"] as const) process.on(signal, () => void shutdown());
process.stdout.on("error", () => void shutdown());
// Should Claude Code die without killing us, we are re-parented.
const parent = process.ppid;
setInterval(() => {
  if (process.ppid !== parent) void shutdown();
}, 2000).unref();

await bridge.start();
rmSync(controlPath, { force: true });
await new Promise<void>((resolve) => control.listen(controlPath, resolve));
chmodSync(controlPath, 0o600);
emit({ type: "listening", socket: bridge.path, control: controlPath });
