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
    single = "▶",
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
  -- Comment kinds, in the order their sections appear in the review. A comment
  -- starts unclassified; :NitKind classifies it. Setting this replaces the whole list.
  --   name     used by :NitKind and shown in the quickfix list / virtual text
  --   sign     sign column marker for the first line
  --   hl       highlight group of the sign
  --   heading  section heading in the review message
  kinds = {
    { name = "change", sign = "!", hl = "DiagnosticSignWarn", heading = "Please change" },
    { name = "question", sign = "?", hl = "DiagnosticSignHint", heading = "Questions" },
    { name = "note", sign = "i", hl = "DiagnosticSignInfo", heading = "Notes" },
  },
  -- Section heading for unclassified comments (only used when classified ones exist).
  unclassified_heading = "Comments",
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
  cfg.kinds = user.kinds or g.kinds or M.defaults.kinds
  return cfg
end

---@return table? the configured type called `name`
function M.kind(name)
  if not name then return nil end
  for _, t in ipairs(M.get().kinds) do
    if t.name == name then return t end
  end
end

return M
