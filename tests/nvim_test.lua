-- Headless tests: nvim --clean --headless -l tests/nvim_test.lua
-- Tests the plugin in $NITPICK_PLUGIN (a built package), else the one in the
-- current directory. Uses throwaway state and socket directories.

local plugin = vim.env.NITPICK_PLUGIN or vim.fn.getcwd()
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
vim.env.XDG_STATE_HOME = tmp .. "/state"
vim.env.NITPICK_DIR = tmp .. "/sockets"
vim.env.XDG_RUNTIME_DIR = nil

vim.g.mapleader = " "
vim.opt.rtp:prepend(plugin)
-- An nvim that bundles nitpick has loaded its own copy already, even with --clean.
vim.g.loaded_nitpick = nil
vim.cmd.source(plugin .. "/plugin/nitpick.lua")
require("nitpick").setup({ startinsert = false, open_cmd = "split" })
-- The mappings the documentation suggests; the plugin itself maps nothing.
vim.keymap.set({ "n", "x" }, "gb", "<Plug>(nitpick-annotate)")
vim.keymap.set({ "n", "x", "o" }, "]n", "<Plug>(nitpick-next)")
vim.keymap.set({ "n", "x", "o" }, "[n", "<Plug>(nitpick-prev)")

local project = vim.uv.fs_realpath(tmp) .. "/project"
vim.fn.mkdir(project .. "/.git", "p")
vim.fn.mkdir(project .. "/src", "p")
local source = {}
for i = 1, 20 do
  source[i] = ("line %d"):format(i)
end
vim.fn.writefile(source, project .. "/src/app.py")
vim.cmd.cd(project)

local pc = require("nitpick")
local store = require("nitpick.store")

local failures, total = 0, 0
local function it(name, fn)
  total = total + 1
  vim.cmd("silent! %bwipeout!")
  vim.cmd.cd(project)
  store.clear()
  vim.cmd.edit("src/app.py")
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    io.stdout:write("ok   " .. name .. "\n")
  else
    failures = failures + 1
    io.stdout:write("FAIL " .. name .. "\n" .. err .. "\n")
  end
end

local function eq(a, b, msg)
  if not vim.deep_equal(a, b) then
    error(("%s\nexpected: %s\n     got: %s"):format(msg or "", vim.inspect(b), vim.inspect(a)), 2)
  end
end

local function ranges()
  return vim.tbl_map(function(c)
    return { c.lnum, c.end_lnum, c.text }
  end, store.list())
end

local function keys(k)
  vim.api.nvim_feedkeys(vim.keycode(k), "mx", false)
end

-- A fake Pi bridge speaking the same protocol as integrations/pi/bridge.ts.
local received = {}
local function fake_pi(opts)
  opts = opts or {}
  vim.fn.mkdir(vim.env.NITPICK_DIR, "p")
  local path = vim.env.NITPICK_DIR .. "/" .. (opts.pid or 4242) .. ".sock"
  local server = assert(vim.uv.new_pipe(false))
  assert(server:bind(path))
  server:listen(8, function()
    local client = assert(vim.uv.new_pipe(false))
    server:accept(client)
    local buf = ""
    client:read_start(function(_, data)
      if not data then return client:close() end
      buf = buf .. data
      if not buf:find("\n") then return end
      local req = vim.json.decode(buf)
      local res
      if req.type == "hello" then
        res = { ok = true, v = 1, type = "hello", pid = opts.pid or 4242,
          session = { agent = opts.agent, id = "session-" .. (opts.pid or 4242), short = "tag" .. (opts.pid or 4242),
            name = opts.name, cwd = opts.cwd or project, idle = opts.idle ~= false } }
      else
        table.insert(received, req)
        res = { ok = true, v = 1, type = "submit", status = "sent" }
      end
      client:write(vim.json.encode(res) .. "\n", function()
        client:shutdown(function()
          client:close()
        end)
      end)
    end)
  end)
  return function()
    server:close()
    os.remove(path)
  end
end

local function wait(cond, what)
  if not vim.wait(3000, cond, 10) then error("timed out waiting for " .. what, 2) end
end

---------------------------------------------------------------------------

it(":Nit with text and ranges", function()
  vim.cmd("3Nit first")
  vim.cmd("12,14Nit second | with a bar")
  vim.api.nvim_win_set_cursor(0, { 7, 0 })
  vim.cmd("Nit on cursor")
  eq(ranges(), { { 3, 3, "first" }, { 7, 7, "on cursor" }, { 12, 14, "second | with a bar" } })
end)

it("comments follow edits", function()
  vim.cmd("5,6Nit moving")
  vim.api.nvim_buf_set_lines(0, 0, 0, false, { "new 1", "new 2" })
  -- A line opened directly below the range stays outside of it.
  vim.api.nvim_win_set_cursor(0, { 8, 0 })
  keys("onew below<Esc>")
  eq(ranges(), { { 7, 8, "moving" } })
end)

it("operator: gbb, counts, motions, text objects and visual mode", function()
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  keys("gbb")
  eq(vim.bo.buftype, "acwrite", "comment buffer opened")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "single line", "" })
  vim.cmd("wq")
  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  keys("3gbb")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "three" })
  vim.cmd("wq")
  vim.api.nvim_win_set_cursor(0, { 10, 0 })
  keys("gb2j")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "motion" })
  vim.cmd("wq")
  vim.api.nvim_win_set_cursor(0, { 15, 0 })
  keys("Vjgb")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "visual" })
  vim.cmd("wq")
  -- "a" text objects must reach the operator ("gbap" used to clash).
  vim.api.nvim_buf_set_lines(0, 17, 17, false, { "" })
  vim.api.nvim_win_set_cursor(0, { 20, 0 })
  keys("gbap")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "paragraph" })
  vim.cmd("wq")
  -- The line key is only armed while our operator waits; "p" keeps its meaning,
  -- also after cancelling the operator.
  eq(vim.fn.maparg("b", "o"), "")
  keys("gb<Esc>")
  eq(vim.fn.maparg("b", "o"), "")
  for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
    assert(not (m.lhs:sub(1, 2) == "gb" and #m.lhs > 2), "mapping makes gb a prefix: " .. m.lhs)
  end
  eq(ranges(), {
    { 2, 2, "single line" },
    { 4, 6, "three" },
    { 10, 12, "motion" },
    { 15, 16, "visual" },
    { 18, 21, "paragraph" },
  })
end)

it("comment buffer: :w keeps it open, edits existing, empty deletes", function()
  vim.cmd("8Nit original")
  local src = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_cursor(0, { 8, 0 })
  vim.cmd("Nit")
  eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "original" })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "changed", "second line" })
  vim.cmd("write")
  eq(vim.bo.modified, false)
  eq(ranges(), { { 8, 8, "changed\nsecond line" } })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
  vim.cmd("write")
  eq(ranges(), {})
  vim.cmd("quit")
  eq(vim.api.nvim_get_current_win(), src)
end)

it("<mods> pick the window and :q! discards", function()
  local before = #vim.api.nvim_list_tabpages()
  vim.cmd("tab Nit")
  eq(#vim.api.nvim_list_tabpages(), before + 1)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "never saved" })
  vim.cmd("quit!")
  eq(ranges(), {})
end)

it("signs and virtual text", function()
  vim.cmd("2,4Nit a block")
  local marks = vim.api.nvim_buf_get_extmarks(0, store.ns_deco, 0, -1, { details = true })
  local signs, virt = {}, nil
  for _, m in ipairs(marks) do
    if m[4].sign_text then signs[m[2] + 1] = vim.trim(m[4].sign_text) end
    if m[4].virt_text then virt = m[4].virt_text[1][1] end
  end
  eq(signs, { [2] = "ŋ", [3] = "│", [4] = "└" })
  eq(virt, "ŋ a block")
end)

it("]n and [n jump between comments, with count and wrap-around", function()
  vim.cmd("4Nit a")
  vim.cmd("9,11Nit b")
  vim.cmd("15Nit c")
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  keys("]n")
  eq(vim.fn.line("."), 4)
  keys("2]n")
  eq(vim.fn.line("."), 15)
  keys("]n")
  eq(vim.fn.line("."), 4, "wraps around")
  keys("[n")
  eq(vim.fn.line("."), 15)
  keys("``")
  eq(vim.fn.line("."), 4, "jumps set the ' mark")
end)

it("errors say why a buffer cannot be annotated; outside files only warn", function()
  local messages = {}
  local orig = vim.notify
  vim.notify = function(msg)
    table.insert(messages, msg)
  end
  vim.cmd("enew")
  vim.cmd("Nit x")
  vim.cmd("NitDelete")
  local outside = vim.uv.fs_realpath(tmp) .. "/outside.txt"
  vim.fn.writefile({ "far away" }, outside)
  vim.cmd("edit " .. outside)
  vim.cmd("Nit y")
  vim.notify = orig
  eq(messages, {
    "nitpick: this buffer is not a file",
    "nitpick: this buffer is not a file",
    "nitpick: " .. vim.fn.fnamemodify(outside, ":~") .. " is outside the project " .. project
      .. "; the review names it by its absolute path",
  })
  eq(store.list()[1].path, outside)
  local text = require("nitpick.review").format(store.list())
  assert(text:find("## `" .. vim.pesc(outside) .. "`, line 1\n\n```text\nfar away\n```\n\ny"), text)
end)

it("charwise motions remember columns", function()
  vim.api.nvim_buf_set_lines(0, 2, 3, false, { "local total = x + y" })
  vim.api.nvim_win_set_cursor(0, { 3, 7 })
  keys("gbiw")
  eq(vim.api.nvim_buf_get_name(0), "nitpick://comment/src/app.py:3:7-3:11")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "rename" })
  vim.cmd("wq")
  local c = store.list()[1]
  eq({ c.lnum, c.end_lnum, c.col, c.end_col }, { 3, 3, 6, 11 })
  -- Highlighted, follows edits inside the line, and is named in the review.
  local hl
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, store.ns_deco, 0, -1, { details = true })) do
    if m[4].hl_group == "NitpickRange" then hl = { m[2], m[3], m[4].end_row, m[4].end_col } end
  end
  eq(hl, { 2, 6, 2, 11 })
  vim.api.nvim_buf_set_text(0, 2, 0, 2, 0, { "  " })
  c = store.list()[1]
  eq({ c.col, c.end_col }, { 8, 13 })
  local t = require("nitpick.review").format(store.list())
  assert(t:find("## `src/app.py`, line 3, columns 9%-13 "), t)
  -- Visual charwise selection, across lines.
  vim.api.nvim_win_set_cursor(0, { 5, 2 })
  keys("vj$hgb")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "span" })
  vim.cmd("wq")
  c = store.list()[2]
  eq({ c.lnum, c.end_lnum, c.col, c.end_col }, { 5, 6, 2, 6 })
  assert(require("nitpick.review").format(store.list()):find("lines 5%-6, from 5:3 to 6:6"))
  -- The same span edits the existing comment; linewise stays linewise.
  vim.api.nvim_win_set_cursor(0, { 3, 9 })
  keys("gbiw")
  eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "rename" })
  vim.cmd("quit")
  keys("gbb")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "whole line" })
  vim.cmd("wq")
  for _, x in ipairs(store.list()) do
    if x.text == "whole line" then eq({ x.lnum, x.col }, { 3, nil }) end
  end
  eq(#store.list(), 3)
end)

it(":NitDelete with ranges and in the quickfix window", function()
  vim.cmd("2Nit a")
  vim.cmd("5Nit b")
  vim.cmd("9Nit c")
  vim.cmd("1,4NitDelete")
  eq(ranges(), { { 5, 5, "b" }, { 9, 9, "c" } })
  vim.cmd("Nits")
  eq(vim.bo.buftype, "quickfix")
  eq(#vim.fn.getqflist(), 2)
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.cmd("NitDelete")
  eq(ranges(), { { 5, 5, "b" } })
  eq(#vim.fn.getqflist(), 1, "quickfix list refreshed")
  vim.cmd("cclose")
end)

it(":NitNote adds notes on the whole review", function()
  vim.cmd("3Nit on a line")
  vim.cmd("NitNote We should rethink the naming overall.")
  vim.cmd("NitNote!")
  eq(vim.bo.buftype, "acwrite", "note buffer opened")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "Second thought,", "on two lines." })
  vim.cmd("wq")
  local list = store.list()
  eq(#list, 3)
  eq({ list[1].path, list[2].path, list[3].lnum }, { nil, nil, 3 }, "notes come first")

  local text = require("nitpick.review").format(list)
  assert(text:find("\n## General\n\nWe should rethink the naming overall%.\n\n## General\n\nSecond thought,\non two lines%.\n\n## `src/app%.py`, line 3\n"), text)

  vim.cmd("Nits")
  eq(vim.fn.getqflist()[1].text, "(general) We should rethink the naming overall.")
  vim.cmd("cclose")
  -- Notes are not on any line, so ]n skips them.
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  keys("]n")
  eq(vim.fn.line("."), 3)
end)

it(":NitFile notes a whole file", function()
  vim.cmd("5Nit on a line")
  vim.cmd("NitFile This module does too much.")
  local list = store.list()
  eq({ list[1].path ~= nil, list[1].lnum, list[2].lnum }, { true, nil, 5 }, "file notes before the file's lines")

  -- Shown at the end of the first line.
  local virt
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, store.ns_deco, 0, 0, { details = true })) do
    if m[4].virt_text then virt = m[4].virt_text[1][1] end
  end
  eq(virt, "ŋ file: This module does too much.")

  local text = require("nitpick.review").format(list)
  assert(text:find("\n## `src/app%.py`\n\nThis module does too much%.\n\n## `src/app%.py`, line 5\n"), text)

  vim.cmd("Nits")
  eq(vim.fn.getqflist()[1].text, "(file) This module does too much.")
  vim.cmd("cclose")
  vim.cmd("LNits")
  eq(#vim.fn.getloclist(0), 2)
  vim.cmd("lclose")

  -- [!] opens a buffer for a new one.
  vim.cmd("NitFile!")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "And it has no tests." })
  vim.cmd("wq")
  eq(#store.list(), 3)
end)

it(":NitFile and :NitNote without text edit the existing note", function()
  -- None yet: a new one.
  vim.cmd("NitFile")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "first" })
  vim.cmd("wq")
  wait(function()
    return vim.bo.buftype == ""
  end, "back in the file")
  -- One: edit it.
  vim.cmd("NitFile")
  eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "first" })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "first, edited" })
  vim.cmd("wq")
  wait(function()
    return vim.bo.buftype == ""
  end, "back in the file")
  vim.cmd("NitFile second")
  -- Several: pick one.
  local offered
  local orig = vim.ui.select
  vim.ui.select = function(items, o, cb)
    offered = vim.tbl_map(o.format_item, items)
    cb(items[2])
  end
  vim.cmd("NitFile")
  vim.ui.select = orig
  eq(offered, { "first, edited", "second" })
  eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "second" })
  vim.cmd("quit!")
  -- Notes on the review work the same way, apart from file notes.
  vim.cmd("NitNote general")
  vim.cmd("NitNote")
  eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "general" })
  vim.cmd("quit!")
  eq(#store.list(), 3)
end)

it(":Nit in a nitpick list edits the entry under the cursor", function()
  vim.cmd("NitNote global")
  vim.cmd("NitFile file")
  vim.cmd("4Nit line")
  vim.cmd("Nits")
  for row, new in ipairs({ "global, edited", "file, edited", "line, edited" }) do
    vim.api.nvim_win_set_cursor(0, { row, 0 })
    vim.cmd("Nit")
    eq(vim.bo.buftype, "acwrite", "comment buffer opened")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { new })
    vim.cmd("wq")
    -- Closing the comment buffer returns to the list.
    wait(function()
      return vim.bo.buftype == "quickfix"
    end, "back in the list")
  end
  vim.cmd("cclose")
  eq(vim.tbl_map(function(c)
    return c.text
  end, store.list()), { "global, edited", "file, edited", "line, edited" })
end)

it(":LNits lists this file's nits in the location list", function()
  vim.cmd("2Nit here")
  vim.cmd("7Nit there")
  vim.cmd("NitNote not in the location list")
  local other = project .. "/src/other.py"
  vim.fn.writefile({ "x" }, other)
  vim.cmd("split " .. other)
  vim.cmd("1Nit elsewhere")
  vim.cmd("close")
  local win = vim.api.nvim_get_current_win()
  vim.cmd("LNits")
  eq(vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].loclist, 1)
  eq(vim.tbl_map(function(i)
    return i.text
  end, vim.fn.getloclist(win)), { "here", "there" })
  -- Kept current, and :NitDelete works on its entries.
  vim.cmd("2NitDelete")
  eq(#vim.fn.getloclist(win), 1)
  vim.cmd("lclose")
  vim.cmd("4Nit added later")
  eq(vim.tbl_map(function(i)
    return i.text
  end, vim.fn.getloclist(win)), { "here", "added later" })
  os.remove(other)
end)

it(":NitClear!, reloaded buffers, and one in-memory review per instance", function()
  vim.cmd("3,4Nit keep me")
  vim.cmd("bwipeout!")
  vim.cmd.edit("src/app.py")
  eq(ranges(), { { 3, 4, "keep me" } })
  -- Nothing is written to disk.
  eq(vim.fn.glob(vim.fn.stdpath("state") .. "/nitpick/*"), "")
  -- :cd keeps the review; only how paths are shown follows the new root.
  local other = vim.uv.fs_realpath(tmp) .. "/other"
  vim.fn.mkdir(other .. "/.git", "p")
  vim.cmd.cd(other)
  eq(ranges(), { { 3, 4, "keep me" } })
  assert(require("nitpick.review").format(store.list()):find("## `" .. vim.pesc(project) .. "/src/app.py`, lines 3%-4"))
  vim.cmd.cd(project)
  assert(require("nitpick.review").format(store.list()):find("## `src/app.py`, lines 3%-4"))
  vim.cmd("NitClear!")
  eq(ranges(), {})
end)

it("review format", function()
  vim.cmd("3Nit why?")
  vim.cmd("5,6Nit rename")
  local text = require("nitpick.review").format(store.list(), { preamble = "Be brief." })
  eq(text, table.concat({
    "Be brief.",
    "",
    "My review comments on the code, each with the lines it refers to.",
    "",
    "Project root: `" .. project .. "`",
    "",
    "## `src/app.py`, line 3",
    "",
    "```python",
    "line 3",
    "```",
    "",
    "why?",
    "",
    "## `src/app.py`, lines 5-6",
    "",
    "```python",
    "line 5",
    "line 6",
    "```",
    "",
    "rename",
    "",
  }, "\n"))
end)

it("Conventional Comments labels show as signs and complete in :Nit", function()
  vim.cmd("3Nit question: why?")
  vim.cmd("5,6Nit suggestion (non-blocking): rename")
  vim.cmd("8Nit Warning: not a label")
  vim.cmd("10Nit NITPICK: case does not matter")
  local function marker(row)
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, store.ns_deco, { row - 1, 0 }, { row - 1, -1 }, { details = true })) do
      if m[4].sign_text then return vim.trim(m[4].sign_text) end
    end
  end
  eq({ marker(3), marker(5), marker(6), marker(8), marker(10) }, { "ŋ?", "ŋ>", "└", "ŋ", "ŋ~" })
  -- A label colors every line of its range, not just the first.
  local function color(row)
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, store.ns_deco, { row - 1, 0 }, { row - 1, -1 }, { details = true })) do
      if m[4].sign_text then return m[4].sign_hl_group end
    end
  end
  eq({ color(5), color(6), color(8) }, { "DiagnosticSignInfo", "DiagnosticSignInfo", "NitpickSign" })

  -- The label stays part of the text, in the list and in the review alike.
  vim.cmd("Nits")
  eq(vim.fn.getqflist()[1].text, "question: why?")
  vim.cmd("cclose")
  local text = require("nitpick.review").format(store.list())
  assert(text:find("\n## `src/app%.py`, line 3\n\n```python\nline 3\n```\n\nquestion: why%?\n"), text)
  assert(not text:find("\n### "), "no sections")

  eq(vim.fn.getcompletion("Nit qu", "cmdline"), { "question:" })
  eq(vim.fn.getcompletion("3,4Nit sugg", "cmdline"), { "suggestion:" })
  eq(vim.fn.getcompletion("NitNote n", "cmdline"), { "nitpick:", "note:" })
  eq(vim.fn.getcompletion("Nit question: wh", "cmdline"), {}, "only the first word")
end)

it("a custom label list replaces the defaults", function()
  require("nitpick").setup({ labels = { { name = "later", sign = "L", hl = "NitpickSign" } } })
  vim.cmd("2Nit later: look at this")
  vim.cmd("4Nit question: no longer a label")
  eq(vim.fn.getcompletion("Nit ", "cmdline"), { "later:" })
  local signs = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, store.ns_deco, 0, -1, { details = true })) do
    if m[4].sign_text then signs[m[2] + 1] = vim.trim(m[4].sign_text) end
  end
  eq(signs, { [2] = "ŋL", [4] = "ŋ" })
  require("nitpick.config").setup({ labels = require("nitpick.config").defaults.labels })
end)

it("the comment buffer completes labels with its omnifunc", function()
  vim.cmd("Nit!")
  eq(vim.bo.omnifunc, "v:lua.require'nitpick'.omnifunc")
  -- Typed like a person would: the first match is inserted with its colon.
  keys("iqu<C-x><C-o><Esc>")
  eq(vim.fn.getline(1), "question: ")
  -- Only the start of the first line: elsewhere it offers nothing.
  local omni = require("nitpick").omnifunc
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "why sug", "sug" })
  vim.api.nvim_win_set_cursor(0, { 1, 7 })
  eq(omni(1, ""), -3)
  vim.api.nvim_win_set_cursor(0, { 2, 3 })
  eq(omni(1, ""), -3)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "  sug" })
  vim.api.nvim_win_set_cursor(0, { 1, 5 })
  eq(omni(1, ""), 2)
  eq(vim.tbl_map(function(i)
    return i.word
  end, omni(0, "sug")), { "suggestion: " })
  vim.cmd("quit!")
end)

it("comment buffers are markdown.nitpick", function()
  vim.cmd("3Nit")
  eq(vim.bo.filetype, "markdown.nitpick")
  eq(vim.treesitter.language.get_lang("markdown.nitpick"), "markdown")
end)

it("the comment buffer highlights the label", function()
  vim.cmd("Nit!")
  local ns = vim.api.nvim_create_namespace("nitpick-label")
  local function marks()
    return vim.tbl_map(function(m)
      return { m[2], m[3], m[4].end_col, m[4].hl_group }
    end, vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true }))
  end
  -- Only on the first line, and only the label with its decoration.
  keys("i  issue (blocking): x<CR>issue: not here<Esc>")
  eq(marks(), { { 0, 2, 18, "DiagnosticSignWarn" } }, "in the label's color")
  keys("gg0dw")
  eq(marks(), { { 0, 0, 16, "DiagnosticSignWarn" } }, "follows edits")
  keys("Ino <Esc>")
  eq(marks(), {}, "no label, no highlight")
  -- The buffer carries it, so a second window shows it too.
  keys("ccquestion: y<Esc>")
  vim.cmd("split")
  eq(marks(), { { 0, 0, 8, "DiagnosticSignHint" } })
  vim.cmd("quit!")
  vim.cmd("quit!")
end)

it("project prompt replaces the instructions", function()
  vim.fn.mkdir(project .. "/.nitpick", "p")
  vim.fn.writefile({ "Custom intro." }, project .. "/.nitpick/review-prompt.md")
  vim.cmd("3Nit x")
  local text = require("nitpick.review").format(store.list())
  os.remove(project .. "/.nitpick/review-prompt.md")
  assert(text:find("^Custom intro%.\n\nProject root:"), text)
end)

it(":NitSend sends to the sole matching session", function()
  local stop_other = fake_pi({ pid = 1, cwd = "/elsewhere" })
  local stop = fake_pi({ pid = 2, name = "demo", agent = "claude", idle = false })
  received = {}
  local messages = {}
  local orig = vim.notify
  vim.notify = function(msg)
    table.insert(messages, msg)
  end
  vim.cmd("3Nit please fix")
  vim.cmd("NitSend Context first")
  wait(function()
    return #received == 1 and #store.list() == 0
  end, "submission")
  vim.notify = orig
  eq(received[1], { v = 1, type = "submit", text = received[1].text, comments = 1 })
  -- The agent was busy; the message says what it does with the review.
  eq(messages[#messages], "nitpick: review sent to demo; it follows once the running turn ends")
  assert(received[1].text:find("^Context first"), received[1].text)
  assert(received[1].text:find("please fix"), received[1].text)
  eq(require("nitpick.sessions").active, vim.env.NITPICK_DIR .. "/2.sock")
  stop()
  stop_other()
end)

it("failed delivery keeps the comments", function()
  require("nitpick.sessions").active = nil
  -- A stale socket file of a dead process.
  vim.fn.mkdir(vim.env.NITPICK_DIR, "p")
  local dead = assert(vim.uv.new_pipe(false))
  dead:bind(vim.env.NITPICK_DIR .. "/99.sock")
  dead:close()
  vim.cmd("3Nit stays")
  vim.cmd("NitSend")
  wait(function()
    return vim.uv.fs_stat(vim.env.NITPICK_DIR .. "/99.sock") == nil
  end, "stale socket removal")
  vim.wait(50)
  eq(ranges(), { { 3, 3, "stays" } })
end)

it(":NitReview works like git commit: :w saves, closing sends", function()
  local stop = fake_pi({ pid = 3 })
  require("nitpick.sessions").active = nil
  received = {}
  vim.cmd("3Nit reviewed")

  -- :q! without a write sends nothing; the nits stay. Notifications that open
  -- a float, like nvim-notify's, must not fail while the buffer closes.
  local orig = vim.notify
  local floats = 0
  vim.notify = function(msg)
    local b = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(b, 0, -1, false, { msg })
    vim.api.nvim_win_close(vim.api.nvim_open_win(b, false, { relative = "editor", row = 0, col = 0, width = 40, height = 1 }), true)
    floats = floats + 1
  end
  vim.cmd("NitReview")
  vim.cmd("quit!")
  vim.wait(100, function()
    return floats > 0
  end)
  vim.notify = orig
  eq(floats, 1, "review not sent was shown")
  eq(#received, 0)

  -- :w only saves; a second :NitReview goes back to the same buffer.
  vim.cmd("NitReview")
  eq(vim.api.nvim_buf_get_name(0), "nitpick://review")
  vim.api.nvim_buf_set_lines(0, 0, 0, false, { "Edited by hand." })
  vim.cmd("write")
  vim.wait(100)
  eq(#received, 0, ":w does not send")
  local buf = vim.api.nvim_get_current_buf()
  vim.cmd("wincmd p")
  vim.cmd("NitReview")
  eq(vim.api.nvim_get_current_buf(), buf)

  -- Closing it sends what was written.
  vim.cmd("quit")
  wait(function()
    return #received == 1
  end, "review sent")
  assert(received[1].text:find("^Edited by hand%."), received[1].text)
  wait(function()
    return #store.list() == 0
  end, "nits cleared")
  stop()
end)

it(":NitReview gives the text back when sending fails", function()
  require("nitpick.sessions").active = nil
  vim.cmd("3Nit no agent runs")
  vim.cmd("NitReview")
  vim.api.nvim_buf_set_lines(0, 0, 0, false, { "Keep me." })
  vim.cmd("wq")
  wait(function()
    return vim.api.nvim_buf_get_name(0) == "nitpick://review"
  end, "review reopened")
  eq(vim.api.nvim_buf_get_lines(0, 0, 1, false), { "Keep me." })
  eq(#store.list(), 1, "nits kept")
  vim.cmd("quit!")
end)

it(":NitTo attaches to the sole matching session, :NitTo! always asks", function()
  local sessions = require("nitpick.sessions")
  sessions.active, sessions.current = nil, nil
  local stop_other = fake_pi({ pid = 5, cwd = "/elsewhere", agent = "claude" })
  local stop = fake_pi({ pid = 6, name = "Fix the parser" })
  vim.cmd("NitTo")
  wait(function()
    return sessions.active ~= nil
  end, "auto attach")
  eq(sessions.current.short, "tag6")

  local offered
  local orig = vim.ui.select
  vim.ui.select = function(items, o, cb)
    offered = vim.tbl_map(o.format_item, items)
    cb(items[2])
  end
  vim.cmd("NitTo!")
  wait(function()
    return offered ~= nil
  end, "picker")
  vim.ui.select = orig
  -- Sessions of this project come first; the attached one is marked.
  eq(offered[1], "● pi tag6  Fix the parser  " .. vim.fn.fnamemodify(project, ":~"))
  eq(offered[2], "  claude tag5  /elsewhere")
  eq(sessions.current.short, "tag5")
  stop()
  stop_other()
end)

it(":NitEdit edits the comment under the cursor, picking among several", function()
  vim.cmd("3Nit whole line")
  store.add(0, 3, 3, "a word", { col = 2, end_col = 4 })
  store.add(0, 5, 5, "part only", { col = 0, end_col = 4 })
  local function edited()
    local text = vim.api.nvim_buf_get_lines(0, 0, -1, false)[1]
    vim.cmd("quit!")
    return text
  end
  local picked
  local orig = vim.ui.select
  vim.ui.select = function(items, opts, cb)
    picked = vim.tbl_map(opts.format_item, items)
    cb(items[#items])
  end

  -- On the word: that comment; elsewhere on the line: the line's own.
  vim.api.nvim_win_set_cursor(0, { 3, 3 })
  vim.cmd("NitEdit")
  eq(edited(), "a word")
  vim.api.nvim_win_set_cursor(0, { 3, 5 })
  vim.cmd("NitEdit")
  eq(edited(), "whole line")
  eq(picked, nil, "one candidate, no picker")
  -- A comment on part of a line is found from anywhere on it when alone.
  vim.api.nvim_win_set_cursor(0, { 5, 6 })
  vim.cmd("NitEdit")
  eq(edited(), "part only")

  -- [!] and ranges with several comments pick.
  vim.api.nvim_win_set_cursor(0, { 3, 3 })
  vim.cmd("NitEdit!")
  eq(picked, { "src/app.py:3  whole line", "src/app.py:3:3-3:4  a word" })
  vim.cmd("quit!")
  vim.cmd("3,5NitEdit")
  eq(picked, { "src/app.py:3  whole line", "src/app.py:3:3-3:4  a word", "src/app.py:5:1-5:4  part only" })
  eq(edited(), "part only")
  vim.ui.select = orig
end)

it("status component", function()
  local sessions = require("nitpick.sessions")
  sessions.active, sessions.current = nil, nil
  eq(pc.status(), "")
  vim.cmd("1Nit x")
  eq(pc.status(), "ŋ 1")
  sessions.current = { short = "abc123", socket = "x" }
  eq(pc.status(), "ŋ 1 → abc123")
  sessions.current.name = "Fix the parser"
  vim.cmd("NitClear!")
  eq(pc.status(), "ŋ → Fix the parser")
end)

print(("\n%d/%d passed"):format(total - failures, total))
vim.fn.delete(tmp, "rf")
os.exit(failures == 0 and 0 or 1)
