-- nitpick: collect a code review in Neovim and hand it to a running coding
-- agent session.

local config = require("nitpick.config")
local editor = require("nitpick.editor")
local review = require("nitpick.review")
local sessions = require("nitpick.sessions")
local store = require("nitpick.store")

local M = {}

local function notify(msg, level)
  vim.notify("nitpick: " .. msg, level or vim.log.levels.INFO)
end

local function range_label(c)
  if not c.path then return "the review" end
  local path = store.display(c.path)
  if not c.lnum then return path end
  if c.col then
    return ("%s:%d:%d-%d:%d"):format(path, c.lnum, c.col + 1, c.end_lnum, c.end_col)
  end
  return c.lnum == c.end_lnum and ("%s:%d"):format(path, c.lnum) or ("%s:%d-%d"):format(path, c.lnum, c.end_lnum)
end

function M.setup(opts)
  config.setup(opts)
end

---------------------------------------------------------------------------
-- Annotating
---------------------------------------------------------------------------

local function edit_comment(buf, c, mods)
  local id = c.id
  editor.open({
    name = ("nitpick://comment/%s"):format(range_label(c)),
    title = ("%s comment on %s   :w save · :wq done · :q! discard"):format(config.get().icon, range_label(c)),
    lines = c.text and vim.split(c.text, "\n", { plain = true }) or { "" },
    mods = mods,
    insert = not id and config.get().startinsert,
    on_write = function(lines)
      local text = editor.text(lines)
      if text == "" then
        if id then
          store.remove({ id })
          id = nil
          notify("comment deleted")
        else
          notify("empty comment discarded", vim.log.levels.WARN)
        end
        return
      end
      if id and store.get(id) then
        store.update(id, text)
      elseif not c.lnum then
        id = store.add_note(text, c.path).id
      elseif vim.api.nvim_buf_is_valid(buf) then
        id = store.add(buf, c.lnum, c.end_lnum, text, c.col and { col = c.col, end_col = c.end_col }).id
      else
        notify("the annotated buffer is gone", vim.log.levels.ERROR)
        return false
      end
    end,
  })
end

--- 'omnifunc' of comment buffers (set in ftplugin/nitpick.lua): a label at the start of the first line.
--- Anywhere else it offers nothing (-3: leave completion quietly).
function M.omnifunc(findstart, base)
  if findstart == 1 then
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local typed = vim.api.nvim_get_current_line():sub(1, col)
    if row ~= 1 or not typed:match("^%s*%a*$") then return -3 end
    return #typed:match("^%s*")
  end
  local items = {}
  for _, l in ipairs(config.get().labels) do
    if vim.startswith(l.name, base:lower()) then
      table.insert(items, { word = l.name .. ": ", abbr = l.name, kind = l.sign })
    end
  end
  return items
end

--- Completes a label ("question:") as the first word of a comment's text.
function M.complete_label(lead, cmdline, pos)
  local args = cmdline:sub(1, pos):match("^.-Nit%a*!?%s+(.*)$")
  if not args or args:find("%s") then return {} end
  local names = {}
  for _, l in ipairs(config.get().labels) do
    if vim.startswith(l.name, lead:lower()) then table.insert(names, l.name .. ":") end
  end
  return names
end

local ids_in_range -- defined with the lists below

---@param opts { line1: integer, line2: integer, range: integer, args?: string, bang?: boolean, mods?: string, buf?: integer, span?: { col: integer, end_col: integer } }
function M.annotate(opts)
  local buf = opts.buf or vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype == "quickfix" then
    -- In a nitpick list, :Nit edits the comment of the entry under the cursor.
    local ids = ids_in_range({ line1 = opts.line1, line2 = opts.line1 })
    local c = ids and store.get(ids[1])
    if c then edit_comment(nil, c, opts.mods) end
    return
  end
  local path, why, outside = store.buf_path(buf)
  if not path then return notify(why, vim.log.levels.ERROR) end
  if outside then
    notify(("%s is outside the project %s; the review names it by its absolute path"):format(
      vim.fn.fnamemodify(path, ":~"),
      store.root()
    ), vim.log.levels.WARN)
  end
  local line1, line2 = math.min(opts.line1, opts.line2), math.max(opts.line1, opts.line2)
  local span = opts.span
  local text = vim.trim(opts.args or "")
  if text ~= "" then
    store.add(buf, line1, line2, text, span)
    return
  end

  if not opts.bang then
    -- Without a range, edit the comment under the cursor; with one, the comment on exactly that range.
    for _, c in ipairs(store.find(path, line1, line2)) do
      local same = c.lnum == line1 and c.end_lnum == line2 and c.col == (span and span.col)
        and c.end_col == (span and span.end_col)
      if opts.range == 0 or same then return edit_comment(buf, c, opts.mods) end
    end
  end
  edit_comment(buf, {
    path = path,
    lnum = line1,
    end_lnum = line2,
    col = span and span.col,
    end_col = span and span.end_col,
  }, opts.mods)
end

--- Without text, :NitNote and :NitFile edit the existing note – picking one
--- when there are several – or start one; [!] always starts a new one.
---@param path? string the file of a file note; nil for notes on the review
local function note(opts, path)
  local text = vim.trim(opts.args or "")
  if text ~= "" then
    store.add_note(text, path)
    return
  end
  local notes = opts.bang and {}
    or vim.tbl_filter(function(c)
      return c.path == path and not c.lnum
    end, store.list())
  if #notes <= 1 then return edit_comment(nil, notes[1] or { path = path }, opts.mods) end
  vim.ui.select(notes, {
    prompt = "Edit note",
    kind = "nitpick.note",
    format_item = function(c)
      return vim.split(c.text, "\n", { plain = true })[1]
    end,
  }, function(choice)
    if choice then edit_comment(nil, choice, opts.mods) end
  end)
end

--- :NitNote[!] [text] – a note on the review as a whole, not on any line.
---@param opts { args?: string, bang?: boolean, mods?: string }
function M.note(opts)
  note(opts, nil)
end

--- :NitFile[!] [text] – a note on the current file as a whole, not on any line.
---@param opts { args?: string, bang?: boolean, mods?: string }
function M.file_note(opts)
  local path, why, outside = store.buf_path(0)
  if not path then return notify(why, vim.log.levels.ERROR) end
  if outside then
    notify(("%s is outside the project %s; the review names it by its absolute path"):format(
      vim.fn.fnamemodify(path, ":~"),
      store.root()
    ), vim.log.levels.WARN)
  end
  note(opts, path)
end

--- 'operatorfunc' for <Plug>(nitpick-annotate).
local OPFUNC = "v:lua.require'nitpick'.operator"

--- While our operator waits for a motion, `line_key` means "current line"
--- (like `dd`). It only exists then, so `<leader>pp` stays a plain operator
--- for which-key and the key keeps its meaning after other operators.
local function arm_line_key()
  local key = config.get().line_key
  if not key or key == "" then return end
  vim.keymap.set("o", key, function()
    if vim.v.operator == "g@" and vim.o.operatorfunc == OPFUNC then return "_" end
    return key
  end, { expr = true, desc = "Nit: current line" })
  vim.api.nvim_create_autocmd("ModeChanged", {
    pattern = "no*:*",
    once = true,
    callback = function()
      pcall(vim.keymap.del, "o", key)
    end,
  })
end

function M.operator(kind)
  if kind == nil then
    vim.o.operatorfunc = OPFUNC
    if vim.api.nvim_get_mode().mode == "n" then arm_line_key() end
    return "g@"
  end
  local s, e = vim.api.nvim_buf_get_mark(0, "["), vim.api.nvim_buf_get_mark(0, "]")
  local span
  if kind == "char" then
    -- '] is inclusive and may sit on a multibyte character.
    local last = vim.api.nvim_buf_get_lines(0, e[1] - 1, e[1], false)[1] or ""
    local end_col = #last == 0 and 0 or e[2] + 1 + vim.str_utf_end(last, e[2] + 1)
    span = { col = s[2], end_col = math.min(end_col, #last) }
  end
  M.annotate({ line1 = s[1], line2 = e[1], range = 2, span = span })
end

---------------------------------------------------------------------------
-- Deleting and listing
---------------------------------------------------------------------------

local qf_id = 0
local QF_TITLE = "nitpick review"

---@param path? string only the nits of this file (for a location list)
local function qf_items(path)
  local items = {}
  for _, c in ipairs(store.list()) do
    if not path or c.path == path then
      local lines = vim.split(c.text, "\n", { plain = true })
      table.insert(items, {
        filename = c.path,
        lnum = c.lnum,
        end_lnum = c.end_lnum,
        col = c.col and c.col + 1 or 0,
        end_col = c.end_col or 0,
        text = (not c.path and "(general) " or not c.lnum and "(file) " or "")
          .. lines[1]
          .. (#lines > 1 and (" (+%d lines)"):format(#lines - 1) or ""),
        user_data = c.id,
      })
    end
  end
  return items
end

local function our_qf()
  return qf_id ~= 0 and vim.fn.getqflist({ id = qf_id }).id == qf_id
end

--- Keeps the quickfix list and every window's location list current.
local function refresh_lists()
  if our_qf() then vim.fn.setqflist({}, "r", { id = qf_id, items = qf_items(), title = QF_TITLE }) end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local loc = vim.w[win].nitpick_loclist
    if loc and vim.fn.getloclist(win, { id = loc.id }).id == loc.id then
      vim.fn.setloclist(win, {}, "r", { id = loc.id, items = qf_items(loc.path) })
    end
  end
end
store.on_change(refresh_lists)

--- :Nits – every nit in the quickfix list.
function M.comments(opts)
  if our_qf() then
    refresh_lists()
    local nr = vim.fn.getqflist({ id = qf_id, nr = 0 }).nr
    local cur = vim.fn.getqflist({ nr = 0 }).nr
    if nr ~= cur then vim.cmd(("silent %s %d"):format(nr > cur and "cnewer" or "colder", math.abs(nr - cur))) end
  else
    vim.fn.setqflist({}, " ", { items = qf_items(), title = QF_TITLE })
    qf_id = vim.fn.getqflist({ id = 0 }).id
  end
  vim.cmd(((opts and opts.mods ~= "") and opts.mods or "botright") .. " copen")
end

--- :LNits – the current file's nits in this window's location list.
function M.loc_comments(opts)
  local path, why = store.buf_path(0)
  if not path then return notify(why, vim.log.levels.ERROR) end
  local title = "nitpick: " .. store.display(path)
  local loc = vim.w.nitpick_loclist
  if loc and loc.path == path and vim.fn.getloclist(0, { id = loc.id }).id == loc.id then
    vim.fn.setloclist(0, {}, "r", { id = loc.id, items = qf_items(path), title = title })
  else
    vim.fn.setloclist(0, {}, " ", { items = qf_items(path), title = title })
    vim.w.nitpick_loclist = { id = vim.fn.getloclist(0, { id = 0 }).id, path = path }
  end
  vim.cmd(((opts and opts.mods ~= "") and opts.mods or "") .. " lopen")
end

--- Comment ids in [line1, line2] of the current buffer, or of the nitpick
--- quickfix list when called from its window. nil (after a message) on error.
---@param opts { line1: integer, line2: integer }
---@return string[]?
function ids_in_range(opts)
  local ids = {}
  if vim.bo.buftype == "quickfix" then
    local is_loc = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].loclist == 1
    local list = is_loc and vim.fn.getloclist(0, { title = 0, items = 0 })
      or vim.fn.getqflist({ title = 0, items = 0 })
    if not vim.startswith(list.title, "nitpick") then
      notify("this is not a nitpick list", vim.log.levels.ERROR)
      return nil
    end
    local items = list.items
    for i = opts.line1, opts.line2 do
      if items[i] and items[i].user_data then table.insert(ids, items[i].user_data) end
    end
  else
    local path, why = store.buf_path(0)
    if not path then
      notify(why, vim.log.levels.ERROR)
      return nil
    end
    for _, c in ipairs(store.find(path, opts.line1, opts.line2)) do
      table.insert(ids, c.id)
    end
  end
  if #ids == 0 then
    notify("no comment here", vim.log.levels.WARN)
    return nil
  end
  return ids
end

---@param opts { line1: integer, line2: integer }
function M.delete(opts)
  local ids = ids_in_range(opts)
  if not ids then return end
  store.remove(ids)
  notify(("deleted %d comment%s"):format(#ids, #ids == 1 and "" or "s"))
end

function M.clear(opts)
  local n = #store.list()
  if n == 0 then return notify("no pending comments") end
  if not (opts and opts.bang) then
    local answer = vim.fn.confirm(("Delete all %d pending comments?"):format(n), "&Yes\n&No", 2)
    if answer ~= 1 then return end
  end
  store.clear()
  notify("review cleared")
end

--- ]r / [r: jump to the next / previous comment in this buffer, wrapping
--- around like ]d. [count] jumps that many comments.
---@param dir 1|-1
function M.jump(dir, count)
  local path = store.buf_path(0)
  local starts, cols = {}, {}
  for _, c in ipairs(path and store.list() or {}) do
    if c.path == path and c.lnum and not cols[c.lnum] then
      table.insert(starts, c.lnum)
      cols[c.lnum] = c.col or 0
    end
  end
  if #starts == 0 then return notify("no comments in this buffer", vim.log.levels.WARN) end
  table.sort(starts)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  for _ = 1, math.max(count or 1, 1) do
    local target
    for i = dir == 1 and 1 or #starts, dir == 1 and #starts or 1, dir do
      if (dir == 1 and starts[i] > line) or (dir == -1 and starts[i] < line) then
        target = starts[i]
        break
      end
    end
    line = target or (dir == 1 and starts[1] or starts[#starts])
  end
  if vim.api.nvim_get_mode().mode == "n" then vim.cmd("normal! m'") end
  vim.api.nvim_win_set_cursor(0, { line, cols[line] })
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

---@param text string
---@param ids string[] comments contained in the text
--- What a busy agent does with a review it receives.
local BUSY = {
  pi = "it steers the running turn",
  claude = "it follows once the running turn ends",
}

---@param opts { on_done?: fun(ok: boolean) }
function M.send(text, ids, opts)
  sessions.resolve(store.root(), function(session)
    if not session then
      if opts.on_done then opts.on_done(false) end
      return
    end
    sessions.request(session.socket, {
      type = "submit",
      text = text,
      comments = #ids,
    }, function(err)
      if err then
        notify("sending failed, your comments are kept: " .. tostring(err), vim.log.levels.ERROR)
        if opts.on_done then opts.on_done(false) end
        return
      end
      store.remove(ids)
      local how = session.idle and "" or ("; " .. (BUSY[session.agent] or "the agent is busy"))
      notify(("review sent to %s%s"):format(sessions.name(session), how))
      if opts.on_done then opts.on_done(true) end
    end)
  end)
end

local function pending_or_warn()
  local list = store.list()
  if #list == 0 then notify("no pending comments", vim.log.levels.WARN) end
  return list
end

local function ids_of(list)
  return vim.tbl_map(function(c)
    return c.id
  end, list)
end

function M.submit(opts)
  opts = opts or {}
  local list = pending_or_warn()
  if #list == 0 then return end
  M.send(review.format(list, { preamble = opts.args }), ids_of(list), {})
end

local REVIEW_BUF = "nitpick://review"

--- The review buffer works like `git commit`'s: :w saves the edited text, and
--- closing the buffer sends what was saved last. Closing it unsaved (:q!) or
--- saving it empty sends nothing.
local function open_review(ids, lines, mods)
  local written
  local buf = editor.open({
    name = REVIEW_BUF,
    title = ("%s review: %d comment%s   :wq send · :q! cancel"):format(config.get().icon, #ids, #ids == 1 and "" or "s"),
    lines = lines,
    mods = mods,
    on_write = function(buf_lines)
      written = editor.text(buf_lines)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    -- Nothing may open a window while the buffer is wiped, not even a
    -- notification (nvim-notify's are floats), so the work waits a tick.
    callback = vim.schedule_wrap(function()
      if written == nil then return notify("review not sent") end
      if written == "" then return notify("empty review not sent", vim.log.levels.WARN) end
      local text = written
      M.send(text, ids, {
        on_done = function(ok)
          -- Nothing is lost: the text comes back for another try.
          if not ok then open_review(ids, vim.split(text, "\n", { plain = true }), mods) end
        end,
      })
    end),
  })
end

--- :NitReview – the complete message in a buffer; see open_review.
function M.review(opts)
  opts = opts or {}
  if vim.fn.bufnr("^" .. vim.fn.escape(REVIEW_BUF, "\\/.*$^~[]") .. "$") ~= -1 then
    -- Already open: go there rather than start a second one.
    return editor.open({ name = REVIEW_BUF, mods = opts.mods })
  end
  local list = pending_or_warn()
  if #list == 0 then return end
  local text = review.format(list, { preamble = opts.args })
  local lines = vim.split(text, "\n", { plain = true })
  if lines[#lines] == "" then table.remove(lines) end
  open_review(ids_of(list), lines, opts.mods)
end

---------------------------------------------------------------------------
-- Sessions and status
---------------------------------------------------------------------------

--- :NitTo[!] – attach to the sole session of this project, else (or with !) pick one.
function M.pick(opts)
  sessions.pick(store.root(), function(session)
    if session then notify("attached to " .. sessions.label(session)) end
  end, { force = opts and opts.bang })
end

--- Statusline component: "ŋ 3 → a3f9c1" (pending comments, attached session).
--- Empty while there is neither.
function M.status()
  local ok, n = pcall(function()
    return #store.list()
  end)
  n = ok and n or 0
  local session = sessions.current
  if n == 0 and not session then return "" end
  local parts = { config.get().icon }
  if n > 0 then table.insert(parts, tostring(n)) end
  if session then table.insert(parts, "→ " .. sessions.name(session)) end
  return table.concat(parts, " ")
end

return M
