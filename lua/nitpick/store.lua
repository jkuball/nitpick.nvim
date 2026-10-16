-- Pending review comments: one review per Neovim instance, in memory only.
--
-- Paths are absolute; the project root (from :pwd) only decides how they are
-- shown and which agent session matches. While a file is loaded, each comment is
-- anchored by an extmark so it follows edits; the line numbers in the records
-- are refreshed from those anchors.

local config = require("nitpick.config")

local M = {}

local ns_anchor = vim.api.nvim_create_namespace("nitpick")
local ns_deco = vim.api.nvim_create_namespace("nitpick-decorations")
M.ns_anchor, M.ns_deco = ns_anchor, ns_deco

---@class NitpickComment
---@field id string
---@field path? string absolute, resolved path; nil for a note on the whole review
---@field lnum? integer first line (1-based); nil for a note on the whole file or review
---@field end_lnum? integer last line (1-based, inclusive)
---@field col? integer charwise comments: start byte column (0-based)
---@field end_col? integer charwise comments: end byte column (0-based, exclusive)
---@field text string
---@field kind? string name of a configured kind; nil is unclassified
---@field source string[] lines at the time the comment was written
---@field created integer

---@type string?
local root
---@type NitpickComment[]
local comments = {}
---@type table<integer, table<string, integer>> bufnr -> comment id -> extmark id
local anchors = {}
local listeners = {}

local function detect_root()
  local cwd = vim.fn.getcwd()
  local found = vim.fs.root(cwd, config.get().root_markers) or cwd
  return vim.uv.fs_realpath(found) or found
end

--- Project root of :pwd, cached until the next :cd.
function M.root()
  root = root or detect_root()
  return root
end

function M.forget_root()
  root = nil
end

function M.on_change(fn)
  table.insert(listeners, fn)
end

local function changed()
  for _, fn in ipairs(listeners) do
    pcall(fn)
  end
end

--- Absolute path of a buffer's file.
---@return string? path
---@return string? why the buffer cannot carry comments
---@return boolean? outside the file lies outside the project root
function M.buf_path(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if vim.bo[buf].buftype ~= "" or name == "" then return nil, "this buffer is not a file" end
  local real = vim.uv.fs_realpath(name) or vim.fs.normalize(vim.fn.fnamemodify(name, ":p"))
  return real, nil, vim.fs.relpath(M.root(), real) == nil
end

--- How a path is shown: relative to the project root when inside it.
function M.display(path)
  return vim.fs.relpath(M.root(), path) or path
end

--- Loaded buffer for a path, if any.
function M.path_buf(path)
  for buf, _ in pairs(anchors) do
    if vim.api.nvim_buf_is_valid(buf) and M.buf_path(buf) == path then return buf end
  end
  local buf = vim.fn.bufnr(path)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then return buf end
end

---------------------------------------------------------------------------
-- Anchors and decorations
---------------------------------------------------------------------------

local function place(buf, c)
  local count = vim.api.nvim_buf_line_count(buf)
  local srow = math.min(c.lnum, count) - 1
  local erow = math.min(math.max(c.end_lnum, c.lnum), count) - 1
  local first = vim.api.nvim_buf_get_lines(buf, srow, srow + 1, false)[1] or ""
  local last = vim.api.nvim_buf_get_lines(buf, erow, erow + 1, false)[1] or ""
  local scol, ecol = 0, #last
  if c.col then
    scol, ecol = math.min(c.col, #first), math.min(c.end_col or #last, #last)
  end
  anchors[buf] = anchors[buf] or {}
  anchors[buf][c.id] = vim.api.nvim_buf_set_extmark(buf, ns_anchor, srow, scol, {
    end_row = erow,
    end_col = ecol,
    -- Lines inserted directly above or below the range stay outside of it.
    right_gravity = true,
    end_right_gravity = false,
  })
end

--- Refresh comment line numbers from the extmarks of one buffer.
local function pull(buf)
  local marks = anchors[buf]
  if not marks then return end
  if not vim.api.nvim_buf_is_valid(buf) then
    anchors[buf] = nil
    return
  end
  local by_id = {}
  for _, c in ipairs(comments) do
    by_id[c.id] = c
  end
  for id, mark in pairs(marks) do
    local c = by_id[id]
    local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns_anchor, mark, { details = true })
    if c and pos[1] then
      c.lnum = pos[1] + 1
      c.end_lnum = math.max(pos[3].end_row or pos[1], pos[1]) + 1
      if c.col then
        c.col, c.end_col = pos[2], pos[3].end_col
      end
    end
  end
end

function M.sync()
  for buf, _ in pairs(anchors) do
    pull(buf)
  end
end

local function truncate(s, width)
  if vim.fn.strdisplaywidth(s) <= width then return s end
  return vim.fn.strcharpart(s, 0, width - 1) .. "…"
end

function M.render(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  pull(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns_deco, 0, -1)
  local cfg = config.get()
  local path = M.buf_path(buf)
  if not path then return end
  local count = vim.api.nvim_buf_line_count(buf)
  for _, c in ipairs(comments) do
    if c.path == path and not c.lnum and cfg.virt_text.enabled then
      local kind = config.kind(c.kind)
      local first = vim.split(c.text, "\n", { plain = true })[1]
      -- At the end of the first line: a virtual line above it would only show
      -- after scrolling up past it (CTRL-Y).
      vim.api.nvim_buf_set_extmark(buf, ns_deco, 0, 0, {
        virt_text = {
          { cfg.virt_text.prefix .. "file: " .. (kind and (kind.name .. ": ") or "") .. first, "NitpickVirtText" },
        },
        virt_text_pos = "eol",
      })
    elseif c.path == path then
      local s, e = math.min(c.lnum, count), math.min(c.end_lnum, count)
      local kind = config.kind(c.kind)
      if cfg.signs.enabled then
        -- Two cells: the type marker on the first line, then the range bracket,
        -- so the bracket stays in one column whether a comment is typed or not.
        for l = s, e do
          local bracket = s == e and cfg.signs.single
            or l == s and cfg.signs.first
            or l == e and cfg.signs.last
            or cfg.signs.middle
          local marker = (kind and l == s) and kind.sign or " "
          local hl = (kind and l == s) and kind.hl or "NitpickSign"
          vim.api.nvim_buf_set_extmark(buf, ns_deco, l - 1, 0, { sign_text = marker .. bracket, sign_hl_group = hl })
        end
      end
      if c.col then
        vim.api.nvim_buf_set_extmark(buf, ns_deco, s - 1, c.col, {
          end_row = e - 1,
          end_col = c.end_col,
          hl_group = "NitpickRange",
          strict = false,
        })
      end
      if cfg.virt_text.enabled then
        local first = vim.split(c.text, "\n", { plain = true })[1]
        local label = kind and (kind.name .. ": ") or ""
        vim.api.nvim_buf_set_extmark(buf, ns_deco, s - 1, 0, {
          virt_text = {
            { cfg.virt_text.prefix .. label .. truncate(first, cfg.virt_text.max_width), "NitpickVirtText" },
          },
          virt_text_pos = "eol",
        })
      end
    end
  end
end

function M.attach(buf)
  local path = M.buf_path(buf)
  if not path or not vim.api.nvim_buf_is_loaded(buf) then return end
  -- A reload (:e!) replaces the text; re-anchor from the stored positions.
  if anchors[buf] then vim.api.nvim_buf_clear_namespace(buf, ns_anchor, 0, -1) end
  anchors[buf] = {}
  for _, c in ipairs(comments) do
    if c.path == path and c.lnum then place(buf, c) end
  end
  M.render(buf)
end

function M.detach(buf)
  pull(buf)
  anchors[buf] = nil
end

local function render_all()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then M.render(buf) end
  end
end

---------------------------------------------------------------------------
-- Comment operations
---------------------------------------------------------------------------

local function sort()
  table.sort(comments, function(a, b)
    -- Notes on the whole review first, in the order they were written.
    if (a.path == nil) ~= (b.path == nil) then return a.path == nil end
    if a.path == nil then return a.created < b.created end
    if a.path ~= b.path then return a.path < b.path end
    -- A file's own notes before its lines.
    if (a.lnum == nil) ~= (b.lnum == nil) then return a.lnum == nil end
    if a.lnum == nil then return a.created < b.created end
    if a.lnum ~= b.lnum then return a.lnum < b.lnum end
    if (a.col or -1) ~= (b.col or -1) then return (a.col or -1) < (b.col or -1) end
    return a.created < b.created
  end)
end

--- All pending comments, sorted by path and line, with fresh positions.
function M.list()
  M.sync()
  sort()
  return comments
end

function M.get(id)
  for _, c in ipairs(M.list()) do
    if c.id == id then return c end
  end
end

--- Comments of a path that intersect [line1, line2].
function M.find(path, line1, line2)
  return vim.tbl_filter(function(c)
    return c.path == path and c.lnum ~= nil and c.lnum <= line2 and c.end_lnum >= line1
  end, M.list())
end

local counter = 0
local function new_id()
  counter = counter + 1
  return ("%x-%x-%x"):format(os.time(), vim.uv.hrtime() % 0xffffff, counter)
end

---@param span? { col: integer, end_col: integer } charwise byte columns
---@return NitpickComment
function M.add(buf, line1, line2, text, span)
  local path = M.buf_path(buf)
  assert(path, "not a file")
  local c = {
    id = new_id(),
    path = path,
    lnum = line1,
    end_lnum = line2,
    col = span and span.col,
    end_col = span and span.end_col,
    text = text,
    source = vim.api.nvim_buf_get_lines(buf, line1 - 1, line2, false),
    created = os.time(),
  }
  table.insert(comments, c)
  sort()
  if not anchors[buf] then anchors[buf] = {} end
  place(buf, c)
  M.render(buf)
  changed()
  return c
end

--- A note on no line: on the whole review, or with a path on that file.
---@param path? string
---@return NitpickComment
function M.add_note(text, path)
  local c = { id = new_id(), path = path, text = text, created = os.time() }
  table.insert(comments, c)
  sort()
  if path then render_all() end
  changed()
  return c
end

function M.update(id, text)
  local c = M.get(id)
  if not c then return nil end
  c.text = text
  render_all()
  changed()
  return c
end

---@param ids string[]
---@param kind? string kind name, nil for unclassified
function M.set_kind(ids, kind)
  local set = {}
  for _, id in ipairs(ids) do
    set[id] = true
  end
  for _, c in ipairs(M.list()) do
    if set[c.id] then c.kind = kind end
  end
  render_all()
  changed()
end

function M.remove(ids)
  local drop = {}
  for _, id in ipairs(ids) do
    drop[id] = true
  end
  M.sync()
  comments = vim.tbl_filter(function(c)
    return not drop[c.id]
  end, comments)
  for buf, marks in pairs(anchors) do
    for id, mark in pairs(marks) do
      if drop[id] then
        if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_del_extmark(buf, ns_anchor, mark) end
        marks[id] = nil
      end
    end
  end
  render_all()
  changed()
end

function M.clear()
  M.remove(vim.tbl_map(function(c)
    return c.id
  end, M.list()))
end

return M
