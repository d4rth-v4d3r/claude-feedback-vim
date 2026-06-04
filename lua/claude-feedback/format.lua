local config = require("claude-feedback.config")
local store = require("claude-feedback.store")
local changed_files = require("claude-feedback.git.changed_files")

local M = {}

local function format_body_for_line(body)
  return body:gsub("\r?\n", "\n     ")
end

function M.format_changed_files(changed, parent)
  local lines = {}
  local opts = config.get()

  if not opts.copy.include_changed_files then
    return lines
  end

  if #changed.unstaged > 0 then
    lines[#lines + 1] = "Changed files (unstaged):"
    for _, f in ipairs(changed.unstaged) do
      lines[#lines + 1] = string.format("  - %s", f.path)
    end
    lines[#lines + 1] = ""
  end

  if #changed.branch > 0 then
    local label = parent and parent.parent_ref or "parent"
    lines[#lines + 1] = string.format("Changed files (vs %s):", label)
    for _, f in ipairs(changed.branch) do
      lines[#lines + 1] = string.format("  - %s", f.path)
    end
    lines[#lines + 1] = ""
  end

  return lines
end

function M.build_review_copy_text(comments, cwd)
  cwd = cwd or vim.fn.getcwd()
  local opts = config.get()
  local changed = changed_files.collect(cwd)
  local lines = M.format_changed_files(changed, changed.parent)

  lines[#lines + 1] =
    "Please address the following code review comments. Run git diff (or git diff HEAD) to see the full context of any changes, especially for deleted lines."
  lines[#lines + 1] = ""

  for i, item in ipairs(comments) do
    local path = opts.copy.include_absolute_paths and item.file_path or item.relative_path
    local body = format_body_for_line(store.comment_body_for_send(item))
    lines[#lines + 1] = string.format("  %d. @%s L%d: %s", i, path, item.line, body)
  end

  return table.concat(lines, "\n")
end

return M
