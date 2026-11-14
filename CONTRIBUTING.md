# Contributing

## Layout

| Path | |
|---|---|
| `lua/nitpick/`, `plugin/`, `doc/` | The Neovim plugin – all of the logic |
| `integrations/pi/` | The Pi extension and the socket bridge it shares with Claude Code |
| `integrations/claude/` | The Claude Code mod and the Node process that runs the bridge for it |

Neovim and the agents only talk through the socket protocol in
`:help nitpick-bridge`. Each side is tested against that contract on its own.

## Tests

`nix develop` gives you Neovim, Node.js and the formatter (`nix fmt`).
`nix run .` starts a Neovim with the plugin from your tree and the suggested
mappings (`modules/try/init.lua`).

```sh
nix flake check
```

runs:

- `tests/nvim_test.lua` – the plugin, headless, against a fake agent socket
  (`nvim --clean --headless -l tests/nvim_test.lua`)
- `integrations/pi/*.test.ts`, `integrations/claude/bridge-helper.spec.ts` – the
  agents' side of the socket (`node --test …`, Node.js 22.18 or newer)

The mod's own tests use Claude Code's test kit and need the `claude` binary:

```sh
claude plugin test integrations/claude
```

## Versions

[Presswerk](https://presswerk.dev/) releases nitpick from the Gitmoji commits
on `main`: it picks the next version, writes it to the version files declared
in `flake.nix` (`package.json` and
`integrations/claude/.claude-plugin/plugin.json`) and adds the release's
section to `CHANGELOG.md`, all in the release commit. Don't bump versions or
edit `CHANGELOG.md` by hand; your commit subjects become its entries.
`nix flake check` fails while the two version files differ.
