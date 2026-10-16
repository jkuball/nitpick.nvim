// Unix-socket bridge between one Pi process and any number of Neovim clients.
//
// Wire format: newline-delimited JSON, one request and one response per
// connection. Authentication is the socket directory's 0700 permission.

import { mkdirSync, chmodSync, rmSync, lstatSync } from "node:fs";
import { createServer, type Server, type Socket } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";

export const PROTOCOL_VERSION = 1;
const MAX_REQUEST_BYTES = 4 * 1024 * 1024;

export interface SessionInfo {
  /** Which agent runs the session: "pi" or "claude". */
  agent: string;
  id: string;
  /** Short, human-friendly tag; also shown in Pi's footer. */
  short: string;
  name?: string;
  cwd: string;
  idle: boolean;
}

/** Everything the bridge needs from the agent; injected so tests can fake it. */
export interface BridgeHost {
  session(): SessionInfo;
  /** Hand the review to the agent the most immediate way it has. */
  deliver(text: string, meta: { comments?: number }): void;
}

export type Request =
  | { v: number; type: "hello" }
  | { v: number; type: "submit"; text: string; comments?: number };

export type Response =
  | { ok: true; v: number; type: "hello"; pid: number; session: SessionInfo }
  | { ok: true; v: number; type: "submit" }
  | { ok: false; v: number; error: string };

/**
 * Pi session ids are UUIDv7, whose leading digits are a timestamp; sessions
 * started close together share them. The random tail tells them apart.
 */
export function shortId(sessionId: string): string {
  return sessionId.replace(/-/g, "").slice(-6);
}

/** Directory shared with the Neovim side (lua/nitpick/sessions.lua). */
export function socketDir(env: NodeJS.ProcessEnv = process.env): string {
  if (env.NITPICK_DIR) return env.NITPICK_DIR;
  if (env.XDG_RUNTIME_DIR) return join(env.XDG_RUNTIME_DIR, "nitpick");
  return join(tmpdir(), `nitpick-${process.getuid?.() ?? "user"}`);
}

export function parseRequest(line: string): Request | string {
  let value: unknown;
  try {
    value = JSON.parse(line);
  } catch {
    return "invalid JSON";
  }
  if (typeof value !== "object" || value === null) return "request must be an object";
  const req = value as Record<string, unknown>;
  if (req.v !== PROTOCOL_VERSION) return `unsupported protocol version ${String(req.v)}`;
  if (req.type === "hello") return { v: PROTOCOL_VERSION, type: "hello" };
  if (req.type === "submit") {
    if (typeof req.text !== "string" || req.text.trim() === "") return "submit needs a non-empty text";
    if (req.comments !== undefined && !Number.isInteger(req.comments)) return "comments must be an integer";
    return {
      v: PROTOCOL_VERSION,
      type: "submit",
      text: req.text,
      comments: req.comments as number | undefined,
    };
  }
  return `unknown request type ${String(req.type)}`;
}

export class Bridge {
  readonly path: string;
  private server: Server | undefined;
  private readonly host: BridgeHost;

  constructor(host: BridgeHost, dir = socketDir()) {
    this.host = host;
    this.path = join(dir, `${process.pid}.sock`);
  }

  get listening(): boolean {
    return this.server?.listening ?? false;
  }

  async start(): Promise<void> {
    if (this.server) return;
    const dir = join(this.path, "..");
    mkdirSync(dir, { recursive: true, mode: 0o700 });
    if ((lstatSync(dir).mode & 0o077) !== 0) chmodSync(dir, 0o700);
    // A socket left by a crashed process with our PID cannot be in use.
    rmSync(this.path, { force: true });

    const server = createServer((socket) => this.accept(socket));
    this.server = server;
    await new Promise<void>((resolve, reject) => {
      server.once("error", reject);
      server.listen(this.path, () => {
        server.off("error", reject);
        resolve();
      });
    });
    chmodSync(this.path, 0o600);
  }

  async stop(): Promise<void> {
    const server = this.server;
    this.server = undefined;
    if (!server) return;
    await new Promise<void>((resolve) => server.close(() => resolve()));
    rmSync(this.path, { force: true });
  }

  handle(req: Request): Response {
    if (req.type === "hello") {
      return { ok: true, v: PROTOCOL_VERSION, type: "hello", pid: process.pid, session: this.host.session() };
    }
    this.host.deliver(req.text, { comments: req.comments });
    return { ok: true, v: PROTOCOL_VERSION, type: "submit" };
  }

  private accept(socket: Socket): void {
    let buffered = "";
    let done = false;
    const reply = (res: Response) => {
      if (done) return;
      done = true;
      socket.end(JSON.stringify(res) + "\n");
    };
    socket.setEncoding("utf8");
    socket.setTimeout(10_000, () => socket.destroy());
    socket.on("error", () => socket.destroy());
    socket.on("data", (chunk: string) => {
      buffered += chunk;
      if (buffered.length > MAX_REQUEST_BYTES) {
        reply({ ok: false, v: PROTOCOL_VERSION, error: "request too large" });
        return;
      }
      const newline = buffered.indexOf("\n");
      if (newline === -1) return;
      const parsed = parseRequest(buffered.slice(0, newline));
      if (typeof parsed === "string") {
        reply({ ok: false, v: PROTOCOL_VERSION, error: parsed });
        return;
      }
      try {
        reply(this.handle(parsed));
      } catch (error) {
        reply({ ok: false, v: PROTOCOL_VERSION, error: error instanceof Error ? error.message : String(error) });
      }
    });
  }
}
