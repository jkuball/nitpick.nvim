// /nit: review in a Neovim started right here, without a second terminal.
//
// Pi's TUI steps aside like it does for Ctrl+G, Neovim gets the terminal,
// and when it exits, nitpick has written the review to a file – the way git
// reads a commit message. `:cq` discards it.

import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

/** The Neovim to start: like Pi's Ctrl+G editor, but ending in nvim. */
export function editorCommand(env: NodeJS.ProcessEnv, settings: { externalEditor?: unknown }): string {
  for (const candidate of [env.NITPICK_NVIM, settings.externalEditor, env.VISUAL, env.EDITOR]) {
    if (typeof candidate === "string" && candidate.trim() !== "") return candidate;
  }
  return "nvim";
}

function shellQuote(s: string): string {
  return `'${s.replaceAll("'", `'\\''`)}'`;
}

/** A shell command line: the editor and the arguments as typed, so `~` and globs work. */
export function commandLine(editor: string, output: string, args: string): string {
  const lua = `lua vim.g.nitpick_output = ${JSON.stringify(output)}`;
  return `${editor} --cmd ${shellQuote(lua)} ${args}`.trimEnd();
}

export type Outcome =
  | { kind: "send"; text: string }
  | { kind: "empty" }
  | { kind: "discard"; code: number | null }
  | { kind: "missing" };

/** What Neovim's exit code and the review file (undefined if missing) amount to. */
export function outcome(code: number | null, text: string | undefined): Outcome {
  if (code !== 0) return { kind: "discard", code };
  if (text === undefined) return { kind: "missing" };
  if (text.trim() === "") return { kind: "empty" };
  return { kind: "send", text };
}

export type Shell = { shell: string; args: string[] };

/** The shell Pi runs its bash tool in (its `shellPath` setting, else bash, else sh). */
export async function piShell(shellPath: string | undefined): Promise<Shell> {
  let getShellConfig: ((path?: string) => Shell) | undefined;
  try {
    ({ getShellConfig } = await import("@earendil-works/pi-coding-agent"));
  } catch {
    // Not inside Pi (the tests) or a Pi without it: Pi's own last resort.
  }
  if (!getShellConfig) return { shell: "sh", args: ["-c"] };
  const { shell, args } = getShellConfig(shellPath);
  return { shell, args };
}

type Terminal = { stop(): void; start(): void; requestRender(force?: boolean): void };
type Ui = {
  custom<T>(factory: (tui: Terminal, theme: unknown, keybindings: unknown, done: (result: T) => void) => unknown): Promise<T>;
};

/** Run Neovim in the foreground and return what it left behind. Blocks Pi meanwhile, like Ctrl+G. */
export async function runNit(ui: Ui, shell: Shell, editor: string, args: string): Promise<Outcome> {
  const dir = mkdtempSync(join(tmpdir(), "nitpick-"));
  const output = join(dir, "review.md");
  try {
    const code = await ui.custom<number | null>((tui, _theme, _keybindings, done) => {
      tui.stop();
      process.stdout.write("\x1b[2J\x1b[H");
      const result = spawnSync(shell.shell, [...shell.args, commandLine(editor, output, args)], { stdio: "inherit" });
      tui.start();
      tui.requestRender(true);
      done(result.status);
      return { render: () => [], invalidate: () => {} };
    });
    let text: string | undefined;
    try {
      text = readFileSync(output, "utf8");
    } catch {
      text = undefined;
    }
    return outcome(code, text);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}
