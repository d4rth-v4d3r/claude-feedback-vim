local notify_mod = require("claude-feedback.notify")
local changed_files = require("claude-feedback.git.changed_files")
local config = require("claude-feedback.config")
local parent = require("claude-feedback.git.parent")
local util = require("claude-feedback.git.util")

local M = {}

---@type table<string, { rel: string, base: string?, untracked: boolean }>
M._file_meta = {}

local function notify(msg, level)
  notify_mod.show(msg, level)
end

local function norm(path)
  return vim.fn.fnamemodify(path, ":p")
end

---@param paths table<string, boolean>
---@param worktree string
---@param rel_path string
local function add_path_and_ancestors(paths, worktree, rel_path)
  local full = norm(worktree .. "/" .. rel_path)
  paths[full] = true
  local dir = vim.fs.dirname(full)
  worktree = norm(worktree)
  while dir and #dir >= #worktree do
    paths[dir] = true
    if dir == worktree then
      break
    end
    dir = vim.fs.dirname(dir)
  end
end

---@param meta table<string, { rel: string, base: string?, untracked: boolean }>
---@param worktree string
---@param f { path: string, status: string }
---@param section string
---@param merge_base_sha string?
local function add_file_meta(meta, worktree, f, section, merge_base_sha)
  local full = norm(worktree .. "/" .. f.path)
  local existing = meta[full]
  if existing and existing.base then
    return
  end
  local untracked = f.status == "??"
  local base = nil
  if not untracked and section == "branch" and merge_base_sha then
    base = merge_base_sha
  end
  meta[full] = {
    rel = f.path,
    base = base,
    untracked = untracked,
  }
end

---@return string[], table<string, { rel: string, base: string?, untracked: boolean }>, string?, table?
local function collect_explorer_paths(cwd)
  local worktree = util.worktree_root(cwd)
  if not worktree then
    return {}, {}, nil, nil
  end

  local resolved = parent.resolve(cwd)
  local changed = changed_files.collect(cwd)
  local include_set = {}
  local meta = {}
  local seen = {}
  local merge_base = resolved and resolved.merge_base_sha

  local function track(f, section)
    if seen[f.path] then
      return
    end
    seen[f.path] = true
    add_path_and_ancestors(include_set, worktree, f.path)
    add_file_meta(meta, worktree, f, section, merge_base)
  end

  for _, f in ipairs(changed.branch) do
    track(f, "branch")
  end
  for _, f in ipairs(changed.unstaged) do
    track(f, "unstaged")
  end

  local include = vim.tbl_keys(include_set)
  table.sort(include)
  return include, meta, worktree, resolved
end

local function explorer_title(resolved, file_count)
  if resolved then
    return string.format(
      "Changed files · %s vs %s (%d)",
      resolved.branch_name,
      resolved.parent_ref,
      file_count
    )
  end
  return string.format("Changed files (%d)", file_count)
end

---@param bufnr number
---@param fn fun()
local function when_gitsigns_attached(bufnr, fn)
  local ok_cache, cache_mod = pcall(require, "gitsigns.cache")
  if not ok_cache then
    notify("gitsigns not available — opened file without diff", vim.log.levels.WARN)
    return
  end

  if cache_mod.cache[bufnr] then
    fn()
    return
  end

  local ok_gs, gitsigns = pcall(require, "gitsigns")
  if ok_gs and gitsigns.attach then
    gitsigns.attach({ bufnr = bufnr }, function(err)
      if err then
        notify("gitsigns attach failed: " .. err, vim.log.levels.WARN)
        return
      end
      if cache_mod.cache[bufnr] then
        fn()
      else
        notify("gitsigns did not attach — opened file without diff", vim.log.levels.WARN)
      end
    end)
  else
    notify("gitsigns not available — opened file without diff", vim.log.levels.WARN)
  end
end

---@param file_path string
---@param info { rel: string, base: string?, untracked: boolean }?
local function open_with_diff(file_path, info)
  local opts = config.get()
  if vim.fn.filereadable(file_path) ~= 1 then
    notify("File not found: " .. (info and info.rel or file_path), vim.log.levels.WARN)
    return
  end

  vim.cmd("edit " .. vim.fn.fnameescape(file_path))

  if opts.diff.on_open == false then
    notify("Use <leader>cr to add a review comment", vim.log.levels.INFO)
    return
  end

  if info and info.untracked then
    notify("New file — no parent version to diff against", vim.log.levels.INFO)
    return
  end

  local ok_diff, diffthis = pcall(require, "gitsigns.actions.diffthis")
  if not ok_diff then
    notify("gitsigns not available — install gitsigns.nvim for diff-on-open", vim.log.levels.WARN)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local vertical = opts.diff.vertical ~= false
  local base = info and info.base or nil

  when_gitsigns_attached(bufnr, function()
    local ok, err = pcall(diffthis.diffthis, base, { vertical = vertical })
    if not ok then
      notify("Could not open diff: " .. tostring(err), vim.log.levels.WARN)
      return
    end
    notify("Vertical diff vs parent · <leader>cr to comment", vim.log.levels.INFO)
  end)
end

---@param picker snacks.Picker
---@param item snacks.picker.Item
---@param action snacks.picker.Action?
local function confirm_changed_file(picker, item, action)
  local explorer_actions = require("snacks.explorer.actions").actions

  if not item then
    return
  end
  if picker.input.filter.meta.searching or item.dir then
    explorer_actions.confirm(picker, item, action)
    return
  end

  local file_path = item.file
  if not file_path then
    return
  end

  local close = not picker.opts.jump or picker.opts.jump.close ~= false
  if close then
    picker:close()
  end

  vim.schedule(function()
    open_with_diff(file_path, M._file_meta[norm(file_path)])
  end)
end

function M.open()
  local Snacks = require("snacks")
  local cwd = util.worktree_root(vim.api.nvim_get_current_buf()) or vim.fn.getcwd()
  local include, meta, worktree, resolved = collect_explorer_paths(cwd)

  local file_count = vim.tbl_count(meta)
  if file_count == 0 then
    notify("No changed files found", vim.log.levels.INFO)
    return
  end

  M._file_meta = meta

  Snacks.explorer.open({
    title = explorer_title(resolved, file_count),
    cwd = worktree,
    include = include,
    exclude = { "**" },
    tree = true,
    follow_file = false,
    layout = { preset = "sidebar", preview = false },
    jump = { close = true },
    confirm = confirm_changed_file,
  })
end

return M
