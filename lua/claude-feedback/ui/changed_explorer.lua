local notify_mod = require("claude-feedback.notify")
local changed_files = require("claude-feedback.git.changed_files")
local config = require("claude-feedback.config")
local parent = require("claude-feedback.git.parent")
local util = require("claude-feedback.git.util")

local M = {}

---@type table<string, { rel: string, abs: string, base: string?, untracked: boolean }>
M._file_meta = {}

local function notify(msg, level)
  notify_mod.show(msg, level)
end

local function norm(path)
  if svim and svim.fs and svim.fs.normalize then
    return svim.fs.normalize(path)
  end
  return vim.fn.fnamemodify(path, ":p"):gsub("/$", "")
end

local function project_root()
  local ok, lv = pcall(require, "lazyvim.util")
  if ok and lv.root then
    return lv.root()
  end
  return util.worktree_root(vim.api.nvim_get_current_buf()) or vim.fn.getcwd()
end

--- Undo legacy explorer filter if a previous version left it active.
function M.restore_explorer()
  local pickers = require("snacks").picker.get({ source = "explorer" })
  local picker = pickers[#pickers]
  if not picker or not picker.opts._cf_changed_filter then
    return
  end

  local saved = picker._cf_saved
  if saved then
    picker.opts.include = saved.include
    picker.opts.exclude = saved.exclude
    picker.opts._cf_changed_filter = nil
    if saved.title then
      picker.title = saved.title
    end
    picker._cf_saved = nil
    picker:find({ refresh = true })
    notify("Restored file explorer", vim.log.levels.INFO)
  end
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

---@param info { rel: string, abs: string, base: string?, untracked: boolean }
local function open_with_diff(info)
  local opts = config.get()
  local abs = info.abs

  if vim.fn.filereadable(abs) ~= 1 then
    notify("File not found: " .. info.rel, vim.log.levels.WARN)
    return
  end

  vim.cmd("edit " .. vim.fn.fnameescape(abs))

  if opts.diff.on_open == false then
    return
  end

  if info.untracked then
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

  when_gitsigns_attached(bufnr, function()
    gs.diffthis(info.base, { vertical = vertical }, function(err)
      if err then
        notify("Could not open diff: " .. err, vim.log.levels.WARN)
      end
    end)
  end)
end

---@return table[], table<string, { rel: string, abs: string, base: string?, untracked: boolean }>, string?, table?
local function collect_changed_items(cwd)
  local worktree = util.worktree_root(cwd)
  if not worktree then
    return {}, {}, nil, nil
  end

  local resolved = parent.resolve(cwd)
  local changed = changed_files.collect(cwd)
  local items = {}
  local meta = {}
  local seen = {}
  local merge_base = resolved and resolved.merge_base_sha

  local function track(f, section)
    if seen[f.path] then
      return
    end
    seen[f.path] = true

    local abs = norm(worktree .. "/" .. f.path)
    local untracked = f.status == "??"
    local base = nil
    if not untracked and section == "branch" and merge_base then
      base = merge_base
    end

    local status = changed_files.format_status(f.status)
    local info = {
      rel = f.path,
      abs = abs,
      base = base,
      untracked = untracked,
    }
    meta[abs] = info

    items[#items + 1] = {
      text = string.format("[%s] %s", status, f.path),
      file = abs,
      item = info,
    }
  end

  for _, f in ipairs(changed.branch) do
    track(f, "branch")
  end
  for _, f in ipairs(changed.unstaged) do
    track(f, "unstaged")
  end

  table.sort(items, function(a, b)
    return a.text < b.text
  end)

  return items, meta, worktree, resolved
end

local function picker_title(resolved, file_count)
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

function M.open()
  M.restore_explorer()

  local cwd = project_root()
  local items, meta, _worktree, resolved = collect_changed_items(cwd)
  local file_count = #items

  if file_count == 0 then
    notify("No changed files found", vim.log.levels.INFO)
    return
  end

  M._file_meta = meta
  local Snacks = require("snacks")

  Snacks.picker.pick({
    title = picker_title(resolved, file_count),
    format = "file",
    preview = "file",
    items = items,
    layout = {
      preset = "sidebar",
      layout = { position = "right" },
      preview = true,
    },
    jump = { close = false },
    confirm = function(picker, item)
      if not item or not item.item then
        return
      end
      vim.schedule(function()
        open_with_diff(item.item)
      end)
    end,
    actions = {
      cf_open = {
        desc = "Open with diff",
        action = function(picker, item)
          item = item or picker:current()
          if item and item.item then
            vim.schedule(function()
              open_with_diff(item.item)
            end)
          end
        end,
      },
    },
    win = {
      list = {
        keys = {
          ["<CR>"] = "cf_open",
          ["l"] = "cf_open",
        },
      },
    },
  })
end

return M
