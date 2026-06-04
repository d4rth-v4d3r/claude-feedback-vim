local store = require("claude-feedback.store")
local util = require("claude-feedback.git.util")

local M = {}

function M.read_context(bufnr, line_index)
  line_index = math.max(0, line_index)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local start = math.max(line_index - 2, 0)
  local finish = math.min(line_index + 2, line_count - 1)
  local lines = {}
  for i = start, finish do
    local marker = i == line_index and ">" or " "
    local text = (vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1] or "")
    lines[#lines + 1] = string.format("%s L%d: %s", marker, i + 1, text)
  end
  return lines
end

function M.location_metadata(file_path)
  local worktree_root = util.worktree_root(file_path) or vim.fn.fnamemodify(file_path, ":h")
  return {
    relative_path = util.relative_path(worktree_root, file_path),
    repo_name = util.repo_name(worktree_root),
    repo_path = worktree_root,
    worktree_name = vim.fn.fnamemodify(worktree_root, ":t"),
    workspace_folder_path = worktree_root,
    branch_name = util.branch_name(worktree_root),
  }
end

function M.add_at_cursor(body)
  body = (body or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if body == "" then
    return false, "Comment cannot be empty"
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  if file_path == "" or vim.bo[bufnr].buftype ~= "" then
    return false, "Review comments can only be added on local files"
  end

  local line_index = vim.api.nvim_win_get_cursor(0)[1] - 1
  local context = M.read_context(bufnr, line_index)
  local metadata = M.location_metadata(file_path)
  local id = store.make_id()
  local created_at = vim.fn.strftime("%Y-%m-%dT%H:%M:%S")

  local comment = {
    id = id,
    file_path = file_path,
    relative_path = metadata.relative_path,
    line = line_index + 1,
    context = context,
    messages = {
      {
        id = id .. "-m0",
        author = "You",
        body = body,
        created_at = created_at,
      },
    },
    status = "pending",
    repo_name = metadata.repo_name,
    repo_path = metadata.repo_path,
    worktree_name = metadata.worktree_name,
    workspace_folder_path = metadata.workspace_folder_path,
    branch_name = metadata.branch_name,
    created_at = created_at,
  }

  store.update(function(state)
    table.insert(state.pending, 1, comment)
  end)

  return true, comment
end

return M
