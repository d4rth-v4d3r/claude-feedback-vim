local notify_mod = require("claude-feedback.notify")
local changed_files = require("claude-feedback.git.changed_files")
local config = require("claude-feedback.config")
local parent = require("claude-feedback.git.parent")
local util = require("claude-feedback.git.util")

local M = {}

---@type table<string, { rel: string, base: string?, untracked: boolean }>
M._file_meta = {}
M._filter_active = false
M._saved = {}
M._default_confirm = nil

local open_with_diff

local function notify(msg, level)
  notify_mod.show(msg, level)
end

local function norm(path)
  return vim.fn.fnamemodify(path, ":p")
end

local function project_root()
  local ok, lv = pcall(require, "lazyvim.util")
  if ok and lv.root then
    return lv.root()
  end
  return util.worktree_root(vim.api.nvim_get_current_buf()) or vim.fn.getcwd()
end

local function get_explorer_picker()
  local pickers = require("snacks").picker.get({ source = "explorer" })
  return pickers[#pickers]
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
      "Changed · %s vs %s (%d)",
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
open_with_diff = function(file_path, info)
  local opts = config.get()
  if vim.fn.filereadable(file_path) ~= 1 then
    notify("File not found: " .. (info and info.rel or file_path), vim.log.levels.WARN)
    return
  end

  vim.cmd("edit " .. vim.fn.fnameescape(file_path))

  if opts.diff.on_open == false then
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
    end
  end)
end

local function patch_explorer_confirm()
  if M._default_confirm then
    return
  end
  local explorer_actions = require("snacks.explorer.actions").actions
  M._default_confirm = explorer_actions.confirm
  explorer_actions.confirm = function(picker, item, action)
    if picker.opts._cf_changed_filter and item and not item.dir and not picker.input.filter.meta.searching then
      local file_path = item.file
      if file_path then
        vim.schedule(function()
          open_with_diff(file_path, M._file_meta[norm(file_path)])
        end)
      end
      return
    end
    return M._default_confirm(picker, item, action)
  end
end

---@param picker snacks.Picker
---@param include string[]
---@param worktree string
---@param title string
local function apply_filter(picker, include, worktree, title)
  if not M._filter_active then
    M._saved = {
      include = picker.opts.include,
      exclude = picker.opts.exclude,
      title = picker.title,
    }
  end

  patch_explorer_confirm()

  picker.opts.include = include
  picker.opts.exclude = { "**" }
  picker.opts._cf_changed_filter = true
  picker.title = title

  local Tree = require("snacks.explorer.tree")
  Tree:refresh(worktree)
  for path in pairs(M._file_meta) do
    Tree:open(path)
  end

  if norm(picker:cwd()) ~= norm(worktree) then
    picker:set_cwd(worktree)
  end

  picker:find({ refresh = true })
  picker:focus("list")
  M._filter_active = true
end

---@param picker snacks.Picker
local function clear_filter(picker)
  picker.opts.include = M._saved.include
  picker.opts.exclude = M._saved.exclude
  picker.opts._cf_changed_filter = nil
  if M._saved.title then
    picker.title = M._saved.title
  end
  picker:find({ refresh = true })
  M._filter_active = false
  M._saved = {}
  notify("Explorer: showing all files", vim.log.levels.INFO)
end

---@param worktree string
local function open_explorer(worktree)
  local Picker = require("snacks.picker.core.picker")
  return Picker.new({
    source = "explorer",
    cwd = worktree,
  })
end

function M.open()
  local cwd = project_root()
  local include, meta, worktree, resolved = collect_explorer_paths(cwd)
  local file_count = vim.tbl_count(meta)

  if file_count == 0 then
    notify("No changed files found", vim.log.levels.INFO)
    return
  end

  worktree = worktree or cwd
  M._file_meta = meta

  local picker = get_explorer_picker()
  local opts = config.get()

  if M._filter_active and picker then
    clear_filter(picker)
    return
  end

  if not picker then
    picker = open_explorer(worktree)
  end

  apply_filter(picker, include, worktree, explorer_title(resolved, file_count))

  local toggle_hint = opts.diff.toggle ~= false and " · run again to show all files" or ""
  notify(
    string.format("Explorer filtered to %d changed file(s)%s", file_count, toggle_hint),
    vim.log.levels.INFO
  )
end

return M
