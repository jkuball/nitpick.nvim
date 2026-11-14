import { test } from "node:test";
import assert from "node:assert/strict";
import { chmodSync, existsSync, mkdtempSync, writeFileSync } from "node:fs";
import { connect } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import extension from "./index.ts";

function request(path: string, payload: unknown): Promise<any> {
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

// Just enough of Pi's ExtensionAPI and context for the extension's glue.
function fakePi() {
  const handlers: Record<string, (event: unknown, ctx: unknown) => Promise<void>> = {};
  const commands: Record<string, { handler: (args: string, ctx: unknown) => Promise<void> }> = {};
  const notes: string[] = [];
  const sent: { text: string; options?: unknown }[] = [];
  const statuses: (string | undefined)[] = [];
  let idle = true;
  const pi = {
    on: (event: string, handler: (event: unknown, ctx: unknown) => Promise<void>) => (handlers[event] = handler),
    registerCommand: (name: string, command: { handler: (args: string, ctx: unknown) => Promise<void> }) => (commands[name] = command),
    getSettings: () => ({}),
    sendUserMessage: (text: string, options?: unknown) => sent.push(options ? { text, options } : { text }),
  };
  const ctx = {
    mode: "tui",
    cwd: "/work",
    isIdle: () => idle,
    sessionManager: { getSessionId: () => "019a0000-0000-7000-8000-00000a1b2c3d", getSessionName: () => "Fix it" },
    ui: {
      notify: (text: string) => notes.push(text),
      // Pi hands over the terminal like this; here there is none to hand over.
      custom: async <T>(factory: (tui: unknown, theme: unknown, kb: unknown, done: (result: T) => void) => unknown) => {
        let result!: T;
        factory({ stop() {}, start() {}, requestRender() {} }, undefined, undefined, (r) => (result = r));
        return result;
      },
      setStatus: (_key: string, text: string | undefined) => statuses.push(text),
      theme: { fg: (_color: string, text: string) => text },
    },
  };
  return { pi, ctx, handlers, commands, notes, sent, statuses, setIdle: (value: boolean) => (idle = value) };
}

test("the extension serves its session and delivers reviews the most immediate way", async () => {
  process.env.NITPICK_DIR = join(mkdtempSync(join(tmpdir(), "nitpick-ext-")), "sockets");
  const fake = fakePi();
  extension(fake.pi as never);
  await fake.handlers.session_start({ type: "session_start", reason: "startup" }, fake.ctx);
  const socket = join(process.env.NITPICK_DIR, `${process.pid}.sock`);
  try {
    assert.deepEqual(fake.statuses, ["ŋ nvim 1b2c3d"]);
    const hello = await request(socket, { v: 1, type: "hello" });
    assert.deepEqual(hello.session, { agent: "pi", id: "019a0000-0000-7000-8000-00000a1b2c3d", short: "1b2c3d", name: "Fix it", cwd: "/work", idle: true });

    // Idle: a new turn. Busy: it steers the running one.
    await request(socket, { v: 1, type: "submit", text: "first", comments: 1 });
    fake.setIdle(false);
    await request(socket, { v: 1, type: "submit", text: "second", comments: 2 });
    assert.deepEqual(fake.sent, [{ text: "first" }, { text: "second", options: { deliverAs: "steer" } }]);
  } finally {
    await fake.handlers.session_shutdown({ type: "session_shutdown", reason: "quit" }, fake.ctx);
  }
  assert.equal(existsSync(socket), false);
  assert.equal(fake.statuses.at(-1), undefined);
});

test("/nit sends what the Neovim it started left behind, and nothing after :cq", async () => {
  // Stands in for Neovim: writes "review of <args>" to the path from --cmd.
  const dir = mkdtempSync(join(tmpdir(), "nitpick-nit-"));
  const fakeNvim = join(dir, "nvim");
  writeFileSync(
    fakeNvim,
    `#!/bin/sh
out=$(printf '%s' "$2" | sed 's/^lua vim.g.nitpick_output = "\\(.*\\)"$/\\1/')
printf 'review of %s' "$3" > "$out"
exit "\${NIT_EXIT:-0}"
`,
  );
  chmodSync(fakeNvim, 0o755);
  process.env.NITPICK_NVIM = fakeNvim;
  const fake = fakePi();
  extension(fake.pi as never);
  try {
    await fake.commands.nit.handler("  src/app.ts ", fake.ctx);
    assert.deepEqual(fake.sent, [{ text: "review of src/app.ts" }]);

    process.env.NIT_EXIT = "1";
    await fake.commands.nit.handler("src/app.ts", fake.ctx);
    assert.equal(fake.sent.length, 1);
    assert.match(fake.notes.at(-1)!, /discarded/);
  } finally {
    delete process.env.NITPICK_NVIM;
    delete process.env.NIT_EXIT;
  }
});
