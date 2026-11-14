-- One-shot mode: an agent started this Neovim (Pi's /nit) and reads the
-- review from a file once it exits, like git reads a commit message. The
-- agent passes the file as `--cmd 'lua vim.g.nitpick_output = "…"'`, so it is
-- not inherited by anything this Neovim starts. There is no session here.

local review = require("nitpick.review")
local store = require("nitpick.store")

local M = {}

---@type string? the review as last saved in the review buffer
M.final = nil

function M.active()
  local path = vim.g.nitpick_output
  return type(path) == "string" and path ~= ""
end

--- The message written on exit: the edited review, else one built from the
--- pending comments, else nothing.
function M.text()
  if M.final then return M.final end
  local list = store.list()
  if #list == 0 then return "" end
  return review.format(list)
end

--- Write the file. Always, even empty: a missing file tells the agent that
--- nitpick never ran in this Neovim.
function M.write()
  if not M.active() then return end
  local lines = vim.split(M.text(), "\n", { plain = true })
  vim.fn.writefile(lines, vim.g.nitpick_output, "b")
end

--- The review buffer was closed with `text`: that is the message now, and
--- Neovim quits to hand it over.
function M.finish(text, notify)
  M.final = text
  local ok = pcall(vim.cmd.qall)
  if not ok then
    notify("the review is done; quit with :qa to hand it over (:cq discards it)", vim.log.levels.WARN)
  end
end

function M.setup(notify)
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("nitpick_oneshot", { clear = true }),
    callback = M.write,
  })
  store.on_change(function()
    if not M.final then return end
    M.final = nil
    notify("comments changed; the edited review is dropped and rebuilt on quit", vim.log.levels.WARN)
  end)
end

return M
