import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { commandLine, editorCommand, outcome, piShell } from "./nit.ts";

test("the Neovim comes from NITPICK_NVIM, Pi's externalEditor, VISUAL, EDITOR, else nvim", () => {
  const all = { NITPICK_NVIM: "nn", VISUAL: "vi", EDITOR: "ed" };
  assert.equal(editorCommand(all, { externalEditor: "ext" }), "nn");
  assert.equal(editorCommand({ ...all, NITPICK_NVIM: " " }, { externalEditor: "ext" }), "ext");
  assert.equal(editorCommand({ VISUAL: "vi", EDITOR: "ed" }, {}), "vi");
  assert.equal(editorCommand({ EDITOR: "ed" }, { externalEditor: "" }), "ed");
  assert.equal(editorCommand({}, {}), "nvim");
});

test("the command line hands Neovim the output path and passes the arguments to the shell", () => {
  const line = commandLine("printf '%s\\n'", "/tmp/it's here/review.md", "a 'b c'");
  const out = execFileSync("/bin/sh", ["-c", line], { encoding: "utf8" });
  assert.deepEqual(out.split("\n").slice(0, -1), ["--cmd", `lua vim.g.nitpick_output = "/tmp/it's here/review.md"`, "a", "b c"]);
  assert.equal(commandLine("nvim", "/o", ""), `nvim --cmd 'lua vim.g.nitpick_output = "/o"'`);
});

test("the exit code and the review file decide what happens", () => {
  assert.deepEqual(outcome(0, "## review\n"), { kind: "send", text: "## review\n" });
  assert.deepEqual(outcome(0, "\n"), { kind: "empty" });
  assert.deepEqual(outcome(0, undefined), { kind: "missing" });
  // :cq discards, whatever was written.
  assert.deepEqual(outcome(1, "## review\n"), { kind: "discard", code: 1 });
  assert.deepEqual(outcome(null, undefined), { kind: "discard", code: null });
});

test("outside Pi, the shell is sh, Pi's own last resort", async () => {
  assert.deepEqual(await piShell(undefined), { shell: "sh", args: ["-c"] });
});
