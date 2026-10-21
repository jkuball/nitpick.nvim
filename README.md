<h1 align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/wordmark-dark.svg">
    <img alt="nitpick.nvim" src="assets/wordmark-light.svg" width="460">
  </picture>
</h1>

<p align="center"><em>The agent codes. You nitpick it directly from Neovim.</em></p>

Read the code your agent wrote, mark what bothers you, and send it all back as
one review.

Comments are made the way you edit text in Vim: an operator, an Ex command
with a range, an ordinary buffer.

```vim
:Nit question: why not sum()?          " current line, with a label
:'<,'>Nit This block looks redundant   " visual selection
:12,18Nit                              " opens a comment buffer: :w / :wq / :q!
gbap                                   " the operator ("go bother"): a paragraph
:NitNote Let's rethink the naming.     " a note on the whole review
:Nits                                  " everything pending, in the quickfix list
:NitSend Please keep it short.         " send, with a leading message
```

## Features

- **Neovim-native.** Nits are extmarks that follow your edits, shown in the
  sign column and as virtual text. Lists are the quickfix and location lists,
  comments are ordinary buffers, commands take ranges and `:vertical`/`:tab`.
- **Charwise or linewise.** `gbiw` or a `v` selection remembers the exact
  columns and highlights them; `gbap` or `V` takes whole lines.
- **Conventional Comments.** Start a nit with a
  [label](https://conventionalcomments.org) – `question:`,
  `suggestion (non-blocking):` – and the agent knows what you want, without
  rules in the prompt. Labels show as signs and complete in `:Nit` and in the
  comment buffer (its `omnifunc`).
- **What you see is what is sent.** `:NitReview` opens the exact message in a
  buffer; edit it and `:wq` sends it, like a `git commit` message.
- **Any file.** Files outside the project can be annotated too; the review
  names them by absolute path.
- **One review per Neovim**, kept in memory while it runs. Quitting Neovim
  drops it without asking, so send before you `:qa`.

### Statusline

`require("nitpick").status()` returns e.g. `ŋ 3 → a3f9c1` – pending nits and
the attached session – or an empty string. For lualine:

```lua
sections = { lualine_x = { function() return require("nitpick").status() end, "encoding", "fileformat", "filetype" } }
```

## Commands

| Command | |
|---|---|
| `:[range]Nit[!] [text]` | Comment on `[range]` (default: current line). With text it is stored directly; without, an ordinary Markdown buffer opens – `:w` saves, `:wq` saves and closes, `:q!` discards, writing it empty deletes the comment. An existing comment on the line/range is edited; `!` forces a new one. In a nitpick list, it edits the entry under the cursor. The first word completes to a label (`question:`). |
| `:NitNote[!] [text]` | A note on the review as a whole, not on any line. Without text, edit the existing note (or start one); `!` starts a new one. |
| `:NitFile[!] [text]` | The same for a note on the current file as a whole, shown at the end of its first line. |
| `:[range]NitEdit[!]` | Edit a comment touching `[range]`, or the one under the cursor; with several, pick one (`!` always picks, among all on the line). |
| `:[range]NitDelete` | Delete comments touching `[range]` – or, in a nitpick quickfix/location list window, the entries in `[range]`. |
| `:Nits` | All pending comments in the quickfix list, kept up to date. |
| `:LNits` | This file's pending comments in the window's location list. |
| `:NitReview [text]` | The exact message the agent will receive, in a buffer – like a `git commit` message: `:w` saves, closing it (`:wq`) sends, `:q!` cancels. |
| `:NitSend [text]` | Send the review, `[text]` goes first. Idle, the agent starts a turn; busy, it takes the review as early as it can (see [Integrations](#integrations)). |
| `:NitClear[!]` | Delete all pending comments (`!` skips the confirmation). |
| `:NitTo[!]` | Attach to the sole agent session of this project; with several (or `!`), pick one. |

## Mappings

nitpick maps no keys; it provides `<Plug>` mappings (see
`:help nitpick-mappings`). A suggested set, with `gb` as the operator:

```lua
local map = vim.keymap.set
map({ "n", "x" }, "gb", "<Plug>(nitpick-annotate)")         -- gbb: this line
map({ "n", "x", "o" }, "]n", "<Plug>(nitpick-next)")
map({ "n", "x", "o" }, "[n", "<Plug>(nitpick-prev)")
map("n", "<leader>nn", "<Plug>(nitpick-annotate-line)")
map("x", "<leader>nn", "<Plug>(nitpick-annotate)")
map("n", "<leader>no", "<Plug>(nitpick-note)")
map("n", "<leader>nf", "<Plug>(nitpick-file)")
map({ "n", "x" }, "<leader>ne", "<Plug>(nitpick-edit)")
map({ "n", "x" }, "<leader>nd", "<Plug>(nitpick-delete)")
map("n", "<leader>nq", "<Plug>(nitpick-qflist)")
map("n", "<leader>nl", "<Plug>(nitpick-loclist)")
map("n", "<leader>nr", "<Plug>(nitpick-review)")
map("n", "<leader>ns", "<Plug>(nitpick-send)")
map("n", "<leader>nc", "<Plug>(nitpick-clear)")
map("n", "<leader>nt", "<Plug>(nitpick-to)")
```

## Installation

Neovim 0.11 or newer, e.g. with lazy.nvim:

```lua
{ "jkuball/nitpick.nvim" }
```

With Nix, add the flake and install `packages.<system>.plugin`, e.g. with
nixvim:

```nix
inputs.nitpick.url = "github:jkuball/nitpick.nvim";
inputs.nitpick.inputs.nixpkgs.follows = "nixpkgs";
```

```nix
extraPlugins = [ inputs.nitpick.packages.${pkgs.stdenv.hostPlatform.system}.plugin ];
```

Then install the part for your agent.

To try it first, without touching your config: `nix run
github:jkuball/nitpick.nvim` starts a plain Neovim with nitpick and the
mappings above.

## Integrations

All of nitpick's logic lives in Neovim: it writes the review and hands it over
a Unix socket. An agent only needs a small integration that receives it and
delivers it as a user message – it does almost nothing itself, and updating
nitpick never means restarting your agent. Adding another agent means
speaking the two-message protocol in `:help nitpick-bridge`.

Each integration shows the session's tag (`ŋ nvim a3f9c1`), so you can tell
sessions apart in `:NitTo`. With Nix, the flake has them as packages too:
`integration-pi` and `integration-claude-code`.

### Pi

An extension that listens in every interactive Pi session and delivers the
review as a user message. `/nvim [on|off]` shows or toggles it,
`NITPICK_AUTOSTART=0` turns off the automatic start.

```sh
pi install git:github.com/jkuball/nitpick.nvim
```

For a single run, `pi -e <checkout>/integrations/pi/index.ts`.

### Claude Code

A [mod](https://code.claude.com/docs/en/plugins/mods/overview), for Claude
Code 2.1.287 or newer. Mods cannot open sockets, so it starts a small Node
process (Node.js 22.18 or newer) for the session's life. The review arrives as
a prompt in your own words.

```
/plugin install nitpick --marketplace jkuball/nitpick.nvim
```

For a single session, `claude --plugin-dir <checkout>/integrations/claude`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT
