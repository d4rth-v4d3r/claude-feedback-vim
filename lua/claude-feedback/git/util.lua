local M = {}

function M.run(cwd, args)
  local cmd = vim.list_extend({ "git" }, args)
  local result = vim.system(cmd, { cwd = cwd, text = true }):wait()
  if result.code ~= 0 then
    return nil
  end
  local stdout = result.stdout or ""
  if stdout == "" then
    return {}
  end
  if stdout:sub(-1) == "\n" then
    stdout = stdout:sub(1, -2)
  end
  return vim.split(stdout, "\n")
end

function M.run_text(cwd, args)
  local lines = M.run(cwd, args)
  if not lines then
    return nil
  end
  return table.concat(lines, "\n")
end

function M.worktree_root(path_or_buf)
  local path = path_or_buf
  if type(path_or_buf) == "number" then
    path = vim.api.nvim_buf_get_name(path_or_buf)
  end
  if not path or path == "" then
    return nil
  end
  if vim.fn.isdirectory(path) == 0 then
    path = vim.fn.fnamemodify(path, ":h")
  end
  local out = M.run_text(path, { "rev-parse", "--show-toplevel" })
  return out and vim.fn.fnamemodify(out, ":p") or nil
end

function M.branch_name(cwd)
  local out = M.run_text(cwd, { "rev-parse", "--abbrev-ref", "HEAD" })
  if not out or out == "" then
    return "unknown"
  end
  return out
end

function M.normalize_branch(name)
  if not name or name == "" or name == "HEAD" then
    return name
  end
  return name
    :gsub("^refs/heads/", "")
    :gsub("^refs/remotes/origin/", "")
    :gsub("^origin/", "")
end

function M.git_config(cwd, key)
  local out = M.run_text(cwd, { "config", "--get", key })
  if not out or out == "" then
    return nil
  end
  return out
end

function M.set_git_config(cwd, key, value)
  local result = vim.system({ "git", "config", key, value }, { cwd = cwd }):wait()
  return result.code == 0
end

function M.rev_parse(cwd, ref)
  local out = M.run_text(cwd, { "rev-parse", ref .. "^{commit}" })
  return out and out ~= "" and out or nil
end

function M.merge_base(cwd, ref)
  local out = M.run_text(cwd, { "merge-base", "HEAD", ref })
  return out and out ~= "" and out or nil
end

function M.origin_head(cwd)
  local out = M.run_text(cwd, { "symbolic-ref", "--short", "refs/remotes/origin/HEAD" })
  if out and out ~= "" then
    return out
  end
  return M.run_text(cwd, { "rev-parse", "--abbrev-ref", "origin/HEAD" })
end

function M.repo_name(cwd)
  local root = M.worktree_root(cwd)
  if not root then
    return "unknown"
  end
  return vim.fn.fnamemodify(root, ":t")
end

function M.relative_path(cwd, file_path)
  local root = M.worktree_root(cwd) or cwd
  file_path = vim.fn.fnamemodify(file_path, ":p")
  root = vim.fn.fnamemodify(root, ":p")
  if file_path:sub(1, #root) == root then
    local rel = file_path:sub(#root + 2)
    return rel ~= "" and rel or vim.fn.fnamemodify(file_path, ":t")
  end
  return vim.fn.fnamemodify(file_path, ":~:.")
end

function M.list_worktrees(cwd)
  local lines = M.run(cwd, { "worktree", "list", "--porcelain" })
  if not lines then
    return {}
  end
  local worktrees = {}
  local current = nil
  for _, line in ipairs(lines) do
    if line:match("^worktree ") then
      current = { root = line:sub(10), branch = nil }
      worktrees[#worktrees + 1] = current
    elseif current and line:match("^branch ") then
      current.branch = line:sub(8):gsub("^refs/heads/", "")
    end
  end
  return worktrees
end

function M.list_branches(cwd)
  local lines = M.run(cwd, { "branch", "-a", "--format=%(refname:short)" })
  if not lines then
    return {}
  end
  local seen = {}
  local out = {}
  for _, b in ipairs(lines) do
    local name = b:gsub("^%s+", ""):gsub("%s+$", "")
    if name ~= "" and not seen[name] then
      seen[name] = true
      out[#out + 1] = name
    end
  end
  return out
end

return M
