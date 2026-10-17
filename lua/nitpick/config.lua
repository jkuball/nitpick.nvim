local M = {}

M.defaults = {
  -- Mark of the statusline component and window titles (an n with a hook).
  icon = "ŋ",
  -- Typed after the annotate operator, the current line: with the operator
  -- on "gb", "gbb" annotates the line (like "gcc").
  line_key = "b",
  -- Command used to open the comment and review buffers when no :{mods} are given.
  open_cmd = "botright 10split",
  -- Start in Insert mode when writing a new comment.
  startinsert = true,
  signs = {
    enabled = true,
    single = "ŋ",
    first = "┌",
    middle = "│",
    last = "└",
  },
  virt_text = {
    enabled = true,
    prefix = "ŋ ",
    max_width = 60,
  },
  -- Opening text of every review. A project can replace it with
  -- <root>/.pi/review-prompt.md (an empty file omits it).
  instructions = "My review comments on the code, each with the lines it refers to.",
  -- Conventional Comments labels (conventionalcomments.org) a comment may
  -- start with: "question: why?", "suggestion (non-blocking): …". A label is
  -- shown as a sign beside the comment. Setting this replaces the whole list.
  labels = {
    { name = "praise", sign = "+", hl = "DiagnosticSignOk" },
    { name = "nitpick", sign = "~", hl = "NitpickSign" },
    { name = "suggestion", sign = ">", hl = "DiagnosticSignInfo" },
    { name = "issue", sign = "!", hl = "DiagnosticSignWarn" },
    { name = "todo", sign = "*", hl = "DiagnosticSignWarn" },
    { name = "question", sign = "?", hl = "DiagnosticSignHint" },
    { name = "thought", sign = "-", hl = "NitpickSign" },
    { name = "chore", sign = "c", hl = "NitpickSign" },
    { name = "note", sign = "i", hl = "DiagnosticSignInfo" },
  },
  -- Longest excerpt (in lines) quoted per comment.
  max_excerpt_lines = 200,
  -- Markers that define the project root, searched upwards from :pwd.
  root_markers = { ".git", ".jj", ".hg" },
  -- Socket directory override (the agents read $NITPICK_DIR).
  socket_dir = nil,
  -- Milliseconds to wait for an agent session to answer.
  timeout = 2000,
}

local user = {}

function M.setup(opts)
  user = vim.tbl_deep_extend("force", user, opts or {})
end

function M.get()
  local g = vim.g.nitpick or {}
  local cfg = vim.tbl_deep_extend("force", M.defaults, g, user)
  -- Lists are replaced, not merged index by index.
  cfg.labels = user.labels or g.labels or M.defaults.labels
  return cfg
end

--- The configured label a comment starts with ("question: …",
--- "issue (blocking): …"), if any.
---@return table?
function M.label(text)
  local first = (text or ""):match("^%s*([^\n]*)")
  local name = first:match("^([%a][%w-]*)%s*%b()%s*:") or first:match("^([%a][%w-]*)%s*:")
  if not name then return nil end
  name = name:lower()
  for _, l in ipairs(M.get().labels) do
    if l.name == name then return l end
  end
end

return M
