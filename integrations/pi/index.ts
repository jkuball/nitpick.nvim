// nitpick: receive code reviews written in Neovim.
//
// Every interactive Pi session listens on a Unix socket; the Neovim plugin
// discovers it, formats the review, and asks this extension to deliver it as
// a user message. Set NITPICK_AUTOSTART=0 to start the bridge only via /nvim.

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Bridge, shortId } from "./bridge.ts";

export default function (pi: ExtensionAPI) {
  let ctx: ExtensionContext | undefined;
  let bridge: Bridge | undefined;

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
      // Idle, the review starts a turn; during one, it steers that turn.
      deliver: (text, meta) => {
        const idle = ctx!.isIdle();
        if (idle) pi.sendUserMessage(text);
        else pi.sendUserMessage(text, { deliverAs: "steer" });
        const what = meta.comments === undefined ? "Review" : `Review with ${meta.comments} comment(s)`;
        ctx!.ui.notify(`${what} received from Neovim`, "info");
      },
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
}
