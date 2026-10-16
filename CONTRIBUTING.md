# Contributing

## Layout

| Path | |
|---|---|
| `lua/nitpick/`, `plugin/`, `doc/` | The Neovim plugin – all of the logic |
| `pi/` | The Pi extension and the socket bridge it shares with Claude Code |
| `claude/` | The Claude Code mod and the Node process that runs the bridge for it |

Neovim and the agents only talk through the socket protocol in
`:help nitpick-bridge`. Each side is tested against that contract on its own.

## Tests

```sh
nix flake check
```

runs:

- `tests/nvim_test.lua` – the plugin, headless, against a fake agent socket
  (`nvim --clean --headless -l tests/nvim_test.lua`)
- `pi/bridge.test.ts`, `pi/index.test.ts`, `claude/bridge-helper.spec.ts` – the
  agents' side of the socket (`node --test …`, Node.js 22.18 or newer)

The mod's own tests use Claude Code's test kit and need the `claude` binary:

```sh
claude plugin test claude
```
