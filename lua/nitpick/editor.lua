-- Ordinary 'acwrite' buffers for writing comments and the final review:
-- :w saves (or sends), :wq saves and closes, :q! discards.

local config = require("nitpick.config")

local M = {}

local function open_window(mods)
  if mods and mods ~= "" then
    vim.cmd(mods .. " split")
  else
    vim.cmd(config.get().open_cmd)
  end
  return vim.api.nvim_get_current_win()
end

local function escape_statusline(s)
  return (s:gsub("%%", "%%%%"))
end

---@param opts { name: string, title: string, lines: string[], filetype?: string, mods?: string, insert?: boolean, on_write: fun(lines: string[], buf: integer): boolean? }
---@return integer buf
function M.open(opts)
  local existing = vim.fn.bufnr("^" .. vim.fn.escape(opts.name, "\\/.*$^~[]") .. "$")
  if existing ~= -1 then
    local win = vim.fn.bufwinid(existing)
    if win ~= -1 then
      vim.api.nvim_set_current_win(win)
    else
      open_window(opts.mods)
      vim.api.nvim_win_set_buf(0, existing)
    end
    return existing
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, opts.name)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, opts.lines)
  vim.bo[buf].modified = false
  -- Markdown, tagged so that other plugins can tell these buffers apart
  -- (e.g. lualine's disabled_filetypes, which would replace the winbar).
  vim.bo[buf].filetype = opts.filetype or "markdown.nitpick"

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      -- on_write returns false to keep the buffer modified (e.g. failed send).
      if opts.on_write(lines, buf) ~= false and vim.api.nvim_buf_is_valid(buf) then vim.bo[buf].modified = false end
    end,
  })

  local origin = vim.api.nvim_get_current_win()
  local win = open_window(opts.mods)
  vim.api.nvim_win_set_buf(win, buf)
  vim.wo[win][0].winbar = "%#NitpickTitle# " .. escape_statusline(opts.title) .. " %*"
  -- Closing the window returns to where it was opened from (Vim would pick a
  -- neighbour), e.g. back to the list a comment was edited from.
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = vim.schedule_wrap(function()
      if vim.api.nvim_win_is_valid(origin) then vim.api.nvim_set_current_win(origin) end
    end),
  })
  if opts.insert then vim.cmd.startinsert() end
  return buf
end

--- Strip trailing blank lines and surrounding whitespace.
function M.text(lines)
  return vim.trim(table.concat(lines, "\n"))
end

return M
