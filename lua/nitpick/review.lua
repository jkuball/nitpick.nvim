-- Turns pending comments into the Markdown message the agent receives.

local config = require("nitpick.config")
local store = require("nitpick.store")

local M = {}

local function instructions(root)
  local custom = vim.fs.joinpath(root, ".pi", "review-prompt.md")
  if vim.uv.fs_stat(custom) then return vim.trim(table.concat(vim.fn.readfile(custom), "\n")) end
  return config.get().instructions
end

--- Current lines of a comment's range and a note on where they came from.
local function excerpt(root, c)
  local buf = store.path_buf(c.path)
  if buf then
    local lines = vim.api.nvim_buf_get_lines(buf, c.lnum - 1, c.end_lnum, false)
    return lines, vim.bo[buf].modified and "unsaved changes in the editor" or nil, vim.bo[buf].filetype
  end
  local abs = c.path
  local ft = vim.filetype.match({ filename = abs }) or ""
  if vim.uv.fs_stat(abs) then
    local ok, lines = pcall(vim.fn.readfile, abs, "", c.end_lnum)
    if ok then return vim.list_slice(lines, c.lnum, c.end_lnum), nil, ft end
  end
  return c.source, "file no longer readable; excerpt from when the comment was written", ft
end

local function fence(lines)
  local longest = 2
  for _, l in ipairs(lines) do
    for run in l:gmatch("`+") do
      longest = math.max(longest, #run)
    end
  end
  return ("`"):rep(longest + 1)
end

--- "line 9", "lines 3-5", or for charwise comments "line 9, columns 5-9" and
--- "lines 3-5, from 3:5 to 5:12" (1-based character columns, inclusive).
local function location(c, lines)
  if not c.col then
    return c.lnum == c.end_lnum and ("line %d"):format(c.lnum) or ("lines %d-%d"):format(c.lnum, c.end_lnum)
  end
  local first, last = lines[1] or "", lines[#lines] or ""
  local scol = vim.fn.charidx(first, math.min(c.col, math.max(#first - 1, 0))) + 1
  local ecol = vim.fn.charidx(last, math.min(math.max(c.end_col - 1, 0), math.max(#last - 1, 0))) + 1
  if c.lnum == c.end_lnum then return ("line %d, columns %d-%d"):format(c.lnum, scol, ecol) end
  return ("lines %d-%d, from %d:%d to %d:%d"):format(c.lnum, c.end_lnum, c.lnum, scol, c.end_lnum, ecol)
end

---@param comments NitpickComment[] sorted by path and line
---@param opts? { preamble?: string }
---@return string
function M.format(comments, opts)
  opts = opts or {}
  local root = store.root()
  local max_lines = config.get().max_excerpt_lines
  local out = {}
  local function add(s)
    table.insert(out, s)
  end

  if opts.preamble and vim.trim(opts.preamble) ~= "" then
    add(vim.trim(opts.preamble))
    add("")
  end
  local intro = instructions(root)
  if intro ~= "" then
    add(intro)
    add("")
  end
  add(("Project root: `%s`"):format(root))

  for _, c in ipairs(comments) do
    add("")
    if not c.lnum then
      -- A note on the whole review, or on a whole file: no excerpt.
      add("## " .. (c.path and ("`" .. store.display(c.path) .. "`") or "General"))
    else
      local lines, note, ft = excerpt(root, c)
      add(("## `%s`, %s%s"):format(store.display(c.path), location(c, lines), note and (" (" .. note .. ")") or ""))
      add("")
      if #lines > max_lines then
        lines = vim.list_extend(vim.list_slice(lines, 1, max_lines), { "… (" .. (#lines - max_lines) .. " more lines)" })
      end
      local f = fence(lines)
      add(f .. (ft or ""))
      vim.list_extend(out, lines)
      add(f)
    end
    add("")
    add(vim.trim(c.text))
  end
  return table.concat(out, "\n") .. "\n"
end

return M
