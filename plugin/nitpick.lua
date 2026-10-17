if vim.g.loaded_nitpick then return end
vim.g.loaded_nitpick = true

local function pc()
  return require("nitpick")
end

local command = vim.api.nvim_create_user_command

local function complete_label(...)
  return pc().complete_label(...)
end

command("NitTo", function(o)
  pc().pick(o)
end, { bang = true, desc = "Attach to an agent session (! always shows the picker)" })

command("Nit", function(o)
  pc().annotate(o)
end, { range = true, nargs = "*", complete = complete_label, bang = true, desc = "Comment on [range]; text or open a comment buffer" })

command("NitNote", function(o)
  pc().note(o)
end, { nargs = "*", complete = complete_label, bang = true, desc = "A note on the review as a whole; without text, edit it (! starts a new one)" })

command("NitFile", function(o)
  pc().file_note(o)
end, { nargs = "*", complete = complete_label, bang = true, desc = "A note on this file as a whole; without text, edit it (! starts a new one)" })

command("NitDelete", function(o)
  pc().delete(o)
end, { range = true, desc = "Delete comments in [range] (or quickfix entries)" })

command("Nits", function(o)
  pc().comments(o)
end, { desc = "Pending comments in the quickfix list" })

command("LNits", function(o)
  pc().loc_comments(o)
end, { desc = "This file's pending comments in the location list" })

command("NitReview", function(o)
  pc().review(o)
end, { nargs = "*", desc = "Edit the full review message; :w sends it" })

command("NitSend", function(o)
  pc().submit(o)
end, { nargs = "*", desc = "Send the review [with a leading message]" })

command("NitClear", function(o)
  pc().clear(o)
end, { bang = true, desc = "Delete all pending comments" })

-- Only <Plug> targets; see :help nitpick-mappings for a suggested setup.
local map = vim.keymap.set
map({ "n", "x" }, "<Plug>(nitpick-annotate)", function()
  return pc().operator()
end, { expr = true, desc = "Nit: annotate {motion}" })
map("n", "<Plug>(nitpick-annotate-line)", function()
  return pc().operator() .. "_"
end, { expr = true, desc = "Nit: annotate [count] lines" })
map("n", "<Plug>(nitpick-delete)", "<Cmd>NitDelete<CR>", { desc = "Nit: delete on this line" })
map("x", "<Plug>(nitpick-delete)", ":NitDelete<CR>", { silent = true, desc = "Nit: delete in selection" })
map({ "n", "x", "o" }, "<Plug>(nitpick-next)", function()
  pc().jump(1, vim.v.count1)
end, { desc = "Nit: next" })
map({ "n", "x", "o" }, "<Plug>(nitpick-prev)", function()
  pc().jump(-1, vim.v.count1)
end, { desc = "Nit: previous" })
map("n", "<Plug>(nitpick-note)", "<Cmd>NitNote<CR>", { desc = "Nit: note on the whole review" })
map("n", "<Plug>(nitpick-file)", "<Cmd>NitFile<CR>", { desc = "Nit: note on this file" })
map("n", "<Plug>(nitpick-qflist)", "<Cmd>Nits<CR>", { desc = "Nit: all nits (quickfix)" })
map("n", "<Plug>(nitpick-loclist)", "<Cmd>LNits<CR>", { desc = "Nit: this file's nits (location list)" })
map("n", "<Plug>(nitpick-review)", "<Cmd>NitReview<CR>", { desc = "Nit: edit the review" })
map("n", "<Plug>(nitpick-send)", "<Cmd>NitSend<CR>", { desc = "Nit: send the review" })
map("n", "<Plug>(nitpick-clear)", "<Cmd>NitClear<CR>", { desc = "Nit: clear the review" })
map("n", "<Plug>(nitpick-to)", "<Cmd>NitTo<CR>", { desc = "Nit: pick the agent session" })

vim.api.nvim_set_hl(0, "NitpickSign", { default = true, link = "DiagnosticSignInfo" })
vim.api.nvim_set_hl(0, "NitpickVirtText", { default = true, link = "Comment" })
vim.api.nvim_set_hl(0, "NitpickTitle", { default = true, link = "Title" })
vim.api.nvim_set_hl(0, "NitpickRange", { default = true, link = "DiagnosticUnderlineInfo" })
vim.api.nvim_set_hl(0, "NitpickLabel", { default = true, link = "Label" })

local group = vim.api.nvim_create_augroup("nitpick", {})
local function store()
  return require("nitpick.store")
end
vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufFilePost" }, {
  group = group,
  callback = function(ev)
    store().attach(ev.buf)
  end,
})
vim.api.nvim_create_autocmd("BufUnload", {
  group = group,
  callback = function(ev)
    store().detach(ev.buf)
  end,
})
vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
  group = group,
  callback = function(ev)
    if vim.api.nvim_buf_get_extmarks(ev.buf, store().ns_anchor, 0, -1, { limit = 1 })[1] then
      store().render(ev.buf)
    end
  end,
})
vim.api.nvim_create_autocmd("DirChanged", {
  group = group,
  callback = function()
    store().forget_root()
  end,
})
