// nitpick: receive code reviews written in Neovim.
//
// Every interactive Pi session listens on a Unix socket; the Neovim plugin
// discovers it, formats the review, and asks this extension to deliver it as
// a user message. Set NITPICK_AUTOSTART=0 to start the bridge only via /nvim.
// /nit starts a Neovim in this terminal instead, and sends what it leaves.

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Bridge, shortId } from "./bridge.ts";
import { editorCommand, piShell, runNit } from "./nit.ts";

export default function (pi: ExtensionAPI) {
  let ctx: ExtensionContext | undefined;
  let bridge: Bridge | undefined;

  // Idle, a review starts a turn; during one, it steers that turn.
  const deliver = (context: ExtensionContext, text: string, comments?: number) => {
    if (context.isIdle()) pi.sendUserMessage(text);
    else pi.sendUserMessage(text, { deliverAs: "steer" });
    const what = comments === undefined ? "Review" : `Review with ${comments} comment(s)`;
    context.ui.notify(`${what} received from Neovim`, "info");
  };

  const ensureBridge = async () => {
    bridge ??= new Bridge({
      session: () => ({
        agent: "pi",
        id: ctx!.sessionManager.getSessionId(),
        short: shortId(ctx!.sessionManager.getSessionId()),
        name: ctx!.sessionManager.getSessionName(),
        cwd: ctx!.cwd,
        idle: ctx!.isIdle(),
      }),
      deliver: (text, meta) => deliver(ctx!, text, meta.comments),
    });
    await bridge.start();
    showStatus();
  };

  // The same tag Neovim's :NitTo picker shows, so you can tell sessions apart.
  const showStatus = () => {
    if (!ctx || ctx.mode !== "tui") return;
    const tag = bridge?.listening ? `ŋ nvim ${shortId(ctx.sessionManager.getSessionId())}` : undefined;
    ctx.ui.setStatus("nitpick", tag && ctx.ui.theme.fg("dim", tag));
  };

  const stopBridge = async () => {
    await bridge?.stop();
    bridge = undefined;
    showStatus();
  };

  pi.on("session_start", async (_event, context) => {
    ctx = context;
    // Print and JSON runs are one-shot; nobody could review into them.
    if (context.mode !== "tui" && context.mode !== "rpc") return;
    if (process.env.NITPICK_AUTOSTART === "0") return;
    try {
      await ensureBridge();
    } catch (error) {
      context.ui.notify(`nitpick: could not start bridge: ${String(error)}`, "error");
    }
  });

  pi.on("session_shutdown", async () => {
    await stopBridge();
    ctx = undefined;
  });

  pi.registerCommand("nvim", {
    description: "Show or toggle the Neovim review bridge (on|off)",
    handler: async (args, context) => {
      ctx = context;
      const arg = args.trim();
      if (arg === "off") await stopBridge();
      else if (arg === "on" || arg === "") await ensureBridge();
      else {
        context.ui.notify("Usage: /nvim [on|off]", "warning");
        return;
      }
      context.ui.notify(
        bridge?.listening ? `nitpick bridge listening on ${bridge.path}` : "nitpick bridge is off",
        "info",
      );
    },
  });

  pi.registerCommand("nit", {
    description: "Review in Neovim here; quitting sends the review, :cq discards it",
    handler: async (args, context) => {
      ctx = context;
      if (context.mode !== "tui") {
        context.ui.notify("/nit needs Pi's terminal UI", "warning");
        return;
      }
      const settings = pi.getSettings();
      let shell;
      try {
        shell = await piShell(settings.shellPath);
      } catch (error) {
        context.ui.notify(`nitpick: ${String(error)}`, "error");
        return;
      }
      const result = await runNit(context.ui, shell, editorCommand(process.env, settings), args.trim());
      if (result.kind === "send") deliver(context, result.text);
      else if (result.kind === "empty") context.ui.notify("No comments, nothing sent", "info");
      else if (result.kind === "discard") context.ui.notify(`Review discarded (Neovim exited with ${result.code ?? "a signal"})`, "info");
      else context.ui.notify("Neovim left no review: is nitpick.nvim installed in it? (NITPICK_NVIM picks the Neovim)", "error");
    },
  });
}
