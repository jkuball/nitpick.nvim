-- nitpick's comment buffers ("markdown.nitpick"): the label at the start of
-- the first line completes through 'omnifunc' and is highlighted.

local buf = vim.api.nvim_get_current_buf()
local config = require("nitpick.config")
local ns = vim.api.nvim_create_namespace("nitpick-label")

vim.bo[buf].omnifunc = "v:lua.require'nitpick'.omnifunc"

local function highlight()
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
  local label, s, e = config.label_at(line)
  -- In the label's own color, as its sign.
  if label then vim.api.nvim_buf_set_extmark(buf, ns, 0, s, { end_col = e, hl_group = label.hl }) end
end
highlight()

-- Each run (and the undo) bumps the generation, so an older attachment detaches.
vim.b[buf].nitpick_ftplugin = (vim.b[buf].nitpick_ftplugin or 0) + 1
local generation = vim.b[buf].nitpick_ftplugin
vim.api.nvim_buf_attach(buf, false, {
  on_lines = function(_, _, _, first)
    if vim.b[buf].nitpick_ftplugin ~= generation then return true end
    if first == 0 then highlight() end
  end,
})

local undo = ("setlocal omnifunc< | unlet! b:nitpick_ftplugin | lua vim.api.nvim_buf_clear_namespace(0, %d, 0, -1)"):format(ns)
vim.b[buf].undo_ftplugin = vim.b[buf].undo_ftplugin and (vim.b[buf].undo_ftplugin .. " | " .. undo) or undo
