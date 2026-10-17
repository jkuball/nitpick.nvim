import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { existsSync, mkdtempSync } from "node:fs";
import { request as httpRequest } from "node:http";
import { connect } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";

function ask(path: string, payload: unknown): Promise<any> {
  return new Promise((resolve, reject) => {
    const socket = connect(path);
    let data = "";
    socket.setEncoding("utf8");
    socket.on("data", (chunk) => (data += chunk));
    socket.on("end", () => resolve(JSON.parse(data)));
    socket.on("error", reject);
    socket.write(JSON.stringify(payload) + "\n");
  });
}

function post(socketPath: string, body: unknown): Promise<number> {
  return new Promise((resolve, reject) => {
    const req = httpRequest({ socketPath, method: "POST", path: "/state" }, (res) => {
      res.resume();
      resolve(res.statusCode ?? 0);
    });
    req.on("error", reject);
    req.end(JSON.stringify(body));
  });
}

// The packaged plugin's entry point when $NITPICK_CLAUDE_PLUGIN names one,
// else the source next to this file.
const [command, args] = process.env.NITPICK_CLAUDE_PLUGIN
  ? [join(process.env.NITPICK_CLAUDE_PLUGIN, "bin/nitpick-bridge"), []]
  : [process.execPath, [join(import.meta.dirname, "bridge-helper.ts")]];

test("the helper bridges Neovim and the mod", async () => {
  const dir = join(mkdtempSync(join(tmpdir(), "nitpick-claude-")), "sockets");
  const child = spawn(command, args, {
    env: { ...process.env, NITPICK_DIR: dir },
    stdio: ["ignore", "pipe", "inherit"],
  });
  const lines = createInterface({ input: child.stdout! })[Symbol.asyncIterator]();
  const next = async () => JSON.parse((await lines.next()).value);
  try {
    const listening = await next();
    assert.equal(listening.type, "listening");
    assert.equal(listening.socket, join(dir, `${child.pid}.sock`));

    // Before the mod reports, the session is unknown but idle.
    let hello = await ask(listening.socket, { v: 1, type: "hello" });
    assert.equal(hello.session.agent, "claude");

    assert.equal(await post(listening.control, { id: "4c1d-9e8f-00a1b2c3d4e5", cwd: "/work", idle: false }), 204);
    hello = await ask(listening.socket, { v: 1, type: "hello" });
    assert.deepEqual(hello.session, {
      agent: "claude",
      id: "4c1d-9e8f-00a1b2c3d4e5",
      short: "c3d4e5",
      cwd: "/work",
      idle: false,
    });

    const res = await ask(listening.socket, { v: 1, type: "submit", text: "fix it", comments: 2 });
    assert.equal(res.ok, true);
    assert.deepEqual(await next(), { type: "submit", text: "fix it", comments: 2 });

    child.kill("SIGTERM");
    await new Promise((resolve) => child.once("exit", resolve));
    assert.equal(existsSync(listening.socket), false);
    assert.equal(existsSync(listening.control), false);
  } finally {
    child.kill("SIGKILL");
  }
});
