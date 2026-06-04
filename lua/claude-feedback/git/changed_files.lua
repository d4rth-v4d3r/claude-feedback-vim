local config = require("claude-feedback.config")
local parent = require("claude-feedback.git.parent")
local util = require("claude-feedback.git.util")

local M = {}

local function parse_name_status_lines(lines, section)
  local out = {}
  if not lines then
    return out
  end
  for _, line in ipairs(lines) do
    if line ~= "" then
      local status, path = line:match("^(%S+)%s+(.+)$")
      if status and path then
        out[#out + 1] = { path = path, status = status, section = section }
      end
    end
  end
  return out
end

function M.unstaged(cwd)
  cwd = cwd or vim.fn.getcwd()
  local worktree = util.worktree_root(cwd)
  if not worktree then
    return {}
  end
  local changed = parse_name_status_lines(util.run(worktree, { "diff", "--name-status" }), "unstaged")
  local untracked = util.run(worktree, { "ls-files", "--others", "--exclude-standard" }) or {}
  for _, path in ipairs(untracked) do
    if path ~= "" then
      changed[#changed + 1] = { path = path, status = "??", section = "unstaged" }
    end
  end
  return changed
end

function M.vs_parent(cwd)
  cwd = cwd or vim.fn.getcwd()
  local resolved = parent.resolve(cwd)
  if not resolved then
    return {}, nil
  end
  local mb = resolved.merge_base_sha
  if not mb then
    return {}, resolved
  end
  local lines = util.run(resolved.worktree_root, { "diff", "--name-status", mb .. "..HEAD" })
  return parse_name_status_lines(lines, "branch"), resolved
end

function M.collect(cwd)
  cwd = cwd or vim.fn.getcwd()
  local mode = config.get().changed_files.mode
  local result = { unstaged = {}, branch = {}, parent = nil }

  if mode == "unstaged" or mode == "both" then
    result.unstaged = M.unstaged(cwd)
  end
  if mode == "branch" or mode == "both" then
    local branch_files, resolved = M.vs_parent(cwd)
    result.branch = branch_files
    result.parent = resolved
  end

  return result
end

function M.format_status(status)
  if status == "??" then
    return "??"
  end
  return status:sub(1, 1)
end

return M
