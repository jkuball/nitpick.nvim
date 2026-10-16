import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, statSync } from "node:fs";
import { connect } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Bridge, parseRequest, shortId } from "./bridge.ts";

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

function fakeBridge() {
  const delivered: { text: string; comments?: number }[] = [];
  const dir = join(mkdtempSync(join(tmpdir(), "nitpick-test-")), "sockets");
  const bridge = new Bridge(
    {
      session: () => ({ agent: "pi", id: "s1", short: "s1", name: "demo", cwd: "/project", idle: true }),
      deliver: (text, meta) => delivered.push({ text, comments: meta.comments }),
    },
    dir,
  );
  return { bridge, delivered, dir };
}

test("shortId uses the random tail of a UUIDv7", () => {
  assert.equal(shortId("01a138ce-1111-7abc-8def-0123456789ab"), "6789ab");
  assert.notEqual(shortId("01a138ce-0000-7000-8000-000000aaaaaa"), shortId("01a138ce-0000-7000-8000-000000bbbbbb"));
});

test("parseRequest validates input", () => {
  assert.equal(parseRequest("nope"), "invalid JSON");
  assert.match(parseRequest('{"v":9,"type":"hello"}') as string, /version/);
  assert.match(parseRequest('{"v":1,"type":"submit","text":"  "}') as string, /non-empty/);
  assert.match(parseRequest('{"v":1,"type":"submit","text":"a","comments":1.5}') as string, /integer/);
  assert.deepEqual(parseRequest('{"v":1,"type":"hello"}'), { v: 1, type: "hello" });
});

test("hello and submit over the socket", async () => {
  const { bridge, delivered, dir } = fakeBridge();
  await bridge.start();
  try {
    assert.equal(statSync(dir).mode & 0o777, 0o700);
    assert.equal(statSync(bridge.path).mode & 0o777, 0o600);

    const hello = await request(bridge.path, { v: 1, type: "hello" });
    assert.equal(hello.ok, true);
    assert.equal(hello.session.name, "demo");
    assert.equal(hello.pid, process.pid);

    const submit = { v: 1, type: "submit", text: "review", comments: 2 };
    assert.deepEqual(await request(bridge.path, submit), { ok: true, v: 1, type: "submit" });
    assert.deepEqual(delivered, [{ text: "review", comments: 2 }]);

    const bad = await request(bridge.path, { v: 1, type: "launch" });
    assert.equal(bad.ok, false);
  } finally {
    await bridge.stop();
  }
});
