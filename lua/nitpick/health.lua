local M = {}

function M.check()
  local health = vim.health
  health.start("nitpick")

  if vim.fn.has("nvim-0.11") == 1 then
    health.ok("Neovim " .. tostring(vim.version()))
  else
    health.error("Neovim 0.11 or newer is required")
    return
  end

  local store = require("nitpick.store")
  local sessions = require("nitpick.sessions")
  local root = store.root()
  health.info("Project root: " .. root)
  health.info(("Pending comments: %d"):format(#store.list()))

  local dir = sessions.dir()
  local stat = vim.uv.fs_stat(dir)
  if not stat then
    health.warn("Socket directory " .. dir .. " does not exist", {
      "Start your agent with nitpick's integration loaded; it creates the directory.",
      "Both sides must agree on $NITPICK_DIR / $XDG_RUNTIME_DIR.",
    })
    return
  end
  health.ok("Socket directory " .. dir)

  local found
  sessions.list(function(list)
    found = list
  end)
  vim.wait(require("nitpick.config").get().timeout + 500, function()
    return found ~= nil
  end)
  if not found or #found == 0 then
    health.warn("No running agent session answered", {
      "An agent with nitpick's integration shows `ŋ nvim <tag>`; see :help nitpick-bridge.",
    })
    return
  end
  for _, s in ipairs(found) do
    local tags = {}
    if sessions.matches(s, root) then table.insert(tags, "this project") end
    if s.socket == sessions.active then table.insert(tags, "selected") end
    health.ok(sessions.label(s) .. (#tags > 0 and ("  (" .. table.concat(tags, ", ") .. ")") or ""))
  end
end

return M
