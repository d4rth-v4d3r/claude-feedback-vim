local notify_mod = require("claude-feedback.notify")
local changed_files = require("claude-feedback.git.changed_files")
local config = require("claude-feedback.config")
local parent = require("claude-feedback.git.parent")
local util = require("claude-feedback.git.util")
local Tree = require("snacks.explorer.tree")

local M = {}

---@type table<string, { rel: string, abs: string, base: string?, untracked: boolean }>
M._file_meta = {}
M._filter_active = false
M._saved = {}

local open_with_diff

local function default_explorer_confirm()
  return require("snacks.explorer.actions").actions.confirm
end

---@param picker snacks.Picker
local function install_picker_confirm(picker)
  if not M._saved.default_confirm then
    M._saved.default_confirm = default_explorer_confirm()
  end

  local ref = picker:ref()
  local PickerActions = require("snacks.picker.core.actions")
  local default = M._saved.default_confirm

  local function cf_confirm(p, item, action)
    if p.opts._cf_changed_filter and item and not item.dir and not p.input.filter.meta.searching then
      local file_path = item.file
      if file_path then
        vim.schedule(function()
          open_with_diff(file_path, M._file_meta[file_path])
        end)
      end
      return
    end
    return default(p, item, action)
  end

  local wrapped = PickerActions.wrap(cf_confirm, ref, "confirm")
  picker.opts.win.input.actions.confirm = wrapped
  picker.opts.win.list.actions.confirm = wrapped
  picker.opts.win.preview.actions.confirm = wrapped
end

---@param picker snacks.Picker
local function restore_picker_confirm(picker)
  if not M._saved.default_confirm then
    return
  end
  local ref = picker:ref()
  local PickerActions = require("snacks.picker.core.actions")
  local wrapped = PickerActions.wrap(M._saved.default_confirm, ref, "confirm")
  picker.opts.win.input.actions.confirm = wrapped
  picker.opts.win.list.actions.confirm = wrapped
  picker.opts.win.preview.actions.confirm = wrapped
end

local function notify(msg, level)
  notify_mod.show(msg, level)
end

local function norm(path)
  if svim and svim.fs and svim.fs.normalize then
    return svim.fs.normalize(path)
  end
  return vim.fn.fnamemodify(path, ":p"):gsub("/$", "")
end

--- snacks explorer filters on Tree node.path, not absolute filesystem paths
---@param abs_path string
---@return string?
local function tree_path(abs_path)
  local node = Tree:find(norm(abs_path))
  return node and node.path or nil
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
  local node = Tree:find(full)
  if not node then
    return
  end
  local wt_node = Tree:find(norm(worktree))
  local current = node
  while current do
    paths[current.path] = true
    if current == wt_node then
      break
    end
    current = current.parent
  end
end

---@param meta table<string, { rel: string, abs: string, base: string?, untracked: boolean }>
---@param worktree string
---@param f { path: string, status: string }
---@param section string
---@param merge_base_sha string?
local function add_file_meta(meta, worktree, f, section, merge_base_sha)
  local full = norm(worktree .. "/" .. f.path)
  local tp = tree_path(full)
  if not tp then
    return
  end
  local existing = meta[tp]
  if existing and existing.base then
    return
  end
  local untracked = f.status == "??"
  local base = nil
  if not untracked and section == "branch" and merge_base_sha then
    base = merge_base_sha
  end
  meta[tp] = {
    rel = f.path,
    abs = full,
    base = base,
    untracked = untracked,
  }
end

---@return string[], table<string, { rel: string, abs: string, base: string?, untracked: boolean }>, string?, table?
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

---@param file_path string explorer tree path (from item.file)
---@param info { rel: string, abs: string, base: string?, untracked: boolean }?
open_with_diff = function(file_path, info)
  local opts = config.get()
  local abs = info and info.abs or file_path
  if vim.fn.filereadable(abs) ~= 1 then
    notify("File not found: " .. (info and info.rel or file_path), vim.log.levels.WARN)
    return
  end

  vim.cmd("edit " .. vim.fn.fnameescape(abs))

  if opts.diff.on_open == false then
    return
  end

  if info and info.untracked then
    notify("New file — no parent version to diff against", vim.log.levels.INFO)
    return
  end

  local ok_gs, gs = pcall(require, "gitsigns")
  if not ok_gs then
    notify("gitsigns not available — install gitsigns.nvim for diff-on-open", vim.log.levels.WARN)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local vertical = opts.diff.vertical ~= false
  local base = info and info.base or nil

  when_gitsigns_attached(bufnr, function()
    gs.diffthis(base, { vertical = vertical }, function(err)
      if err then
        notify("Could not open diff: " .. err, vim.log.levels.WARN)
      end
    end)
  end)
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

  install_picker_confirm(picker)

  if norm(picker:cwd()) ~= norm(worktree) then
    picker:set_cwd(worktree)
  end

  Tree:refresh(worktree)

  picker.opts.include = include
  picker.opts.exclude = { "**" }
  picker.opts._cf_changed_filter = true
  picker.title = title

  for _, info in pairs(M._file_meta) do
    Tree:open(info.abs)
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
  restore_picker_confirm(picker)
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
