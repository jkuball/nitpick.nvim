-- Discovery of and requests to running agent sessions, Pi or Claude Code
-- (see pi/bridge.ts).

local config = require("nitpick.config")

local M = {}

local PROTOCOL_VERSION = 1

---@class NitpickSession
---@field socket string
---@field pid integer
---@field agent string "pi" or "claude"
---@field id string
---@field short string
---@field name? string
---@field cwd string
---@field idle boolean

---@type string? socket of the selected session
M.active = nil
---@type NitpickSession? last known state of the selected session
M.current = nil

local function select(session)
  M.active = session and session.socket
  M.current = session
end

function M.dir()
  local custom = config.get().socket_dir or vim.env.NITPICK_DIR
  if custom and custom ~= "" then return custom end
  if vim.env.XDG_RUNTIME_DIR and vim.env.XDG_RUNTIME_DIR ~= "" then
    return vim.fs.joinpath(vim.env.XDG_RUNTIME_DIR, "nitpick")
  end
  return vim.fs.joinpath(vim.uv.os_tmpdir(), "nitpick-" .. vim.uv.getuid())
end

--- Send one request and call cb(err, response) on the main loop.
function M.request(socket, payload, cb)
  cb = vim.schedule_wrap(cb)
  payload.v = PROTOCOL_VERSION
  local pipe = assert(vim.uv.new_pipe(false))
  local timer = assert(vim.uv.new_timer())
  local finished = false
  local chunks = {}
  local function finish(err, res)
    if finished then return end
    finished = true
    timer:stop()
    timer:close()
    if not pipe:is_closing() then pipe:close() end
    cb(err, res)
  end
  timer:start(config.get().timeout, 0, function()
    finish("timed out")
  end)
  pipe:connect(socket, function(err)
    if err then return finish(err) end
    pipe:write(vim.json.encode(payload) .. "\n")
    pipe:read_start(function(rerr, data)
      if rerr then return finish(rerr) end
      if data then return table.insert(chunks, data) end
      local ok, res = pcall(vim.json.decode, table.concat(chunks))
      if not ok or type(res) ~= "table" then return finish("invalid response") end
      if not res.ok then return finish(res.error or "request failed") end
      finish(nil, res)
    end)
  end)
end

--- Ask a session socket who it is.
function M.hello(socket, cb)
  M.request(socket, { type = "hello" }, function(err, res)
    if err then return cb(err) end
    cb(nil, {
      socket = socket,
      pid = res.pid,
      agent = res.session.agent or "pi",
      id = res.session.id,
      short = res.session.short or res.session.id:gsub("-", ""):sub(-6),
      name = res.session.name ~= vim.NIL and res.session.name or nil,
      cwd = res.session.cwd,
      idle = res.session.idle,
    })
  end)
end

--- All live sessions; sockets of dead processes are removed.
---@param cb fun(sessions: NitpickSession[])
function M.list(cb)
  local dir = M.dir()
  local sockets = {}
  for name, kind in vim.fs.dir(dir) do
    if kind == "socket" and name:match("%.sock$") then table.insert(sockets, vim.fs.joinpath(dir, name)) end
  end
  local pending, found = #sockets, {}
  if pending == 0 then return vim.schedule(function() cb(found) end) end
  for _, socket in ipairs(sockets) do
    M.hello(socket, function(err, session)
      if session then
        table.insert(found, session)
      elseif type(err) == "string" and (err:match("ECONNREFUSED") or err:match("ENOENT")) then
        os.remove(socket)
      end
      pending = pending - 1
      if pending == 0 then
        table.sort(found, function(a, b)
          return a.pid < b.pid
        end)
        cb(found)
      end
    end)
  end
end

--- Whether a session works on the given project root.
function M.matches(session, root)
  local cwd = vim.uv.fs_realpath(session.cwd) or session.cwd
  return cwd == root or vim.fs.relpath(root, cwd) ~= nil or vim.fs.relpath(cwd, root) ~= nil
end

--- "pi a3f9c1  Session title  ~/project  [busy]"; the tag matches the one
--- the agent shows in its own status line.
function M.label(session)
  local parts = { session.agent .. " " .. session.short }
  if session.name then table.insert(parts, session.name) end
  table.insert(parts, vim.fn.fnamemodify(session.cwd, ":~"))
  if not session.idle then table.insert(parts, "[busy]") end
  return table.concat(parts, "  ")
end

--- Short name for messages and the statusline.
function M.name(session)
  return session.name or session.short
end

--- Let the user pick a session; matching sessions come first. Unless
--- opts.force, the sole session of this project is taken without asking.
---@param root string
---@param cb fun(session?: NitpickSession, picked?: boolean)
---@param opts? { force?: boolean }
function M.pick(root, cb, opts)
  M.list(function(sessions)
    if #sessions == 0 then
      vim.notify("nitpick: no running agent session found (is nitpick loaded in Pi or Claude Code?)", vim.log.levels.WARN)
      return cb(nil)
    end
    local matching = vim.tbl_filter(function(s)
      return M.matches(s, root)
    end, sessions)
    if #matching == 1 and not (opts and opts.force) then
      select(matching[1])
      return cb(matching[1], false)
    end
    table.sort(sessions, function(a, b)
      local ma, mb = M.matches(a, root), M.matches(b, root)
      if ma ~= mb then return ma end
      return a.pid < b.pid
    end)
    vim.ui.select(sessions, {
      prompt = "Send nits to",
      kind = "nitpick.session",
      format_item = function(s)
        return (s.socket == M.active and "● " or "  ") .. M.label(s)
      end,
    }, function(choice)
      if choice then select(choice) end
      cb(choice, true)
    end)
  end)
end

--- The active session, re-checked, else the sole session of this project,
--- else whatever the user picks.
---@param root string
---@param cb fun(session?: NitpickSession)
function M.resolve(root, cb)
  if not M.active then return M.pick(root, cb) end
  M.hello(M.active, function(err, session)
    if session then
      M.current = session
      return cb(session)
    end
    vim.notify("nitpick: the attached session is gone (" .. tostring(err) .. ")", vim.log.levels.WARN)
    select(nil)
    M.pick(root, cb)
  end)
end

return M
