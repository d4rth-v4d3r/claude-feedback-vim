local notify_mod = require("claude-feedback.notify")
local changed_files = require("claude-feedback.git.changed_files")
local clipboard = require("claude-feedback.clipboard")
local format = require("claude-feedback.format")
local parent = require("claude-feedback.git.parent")
local store = require("claude-feedback.store")
local thread = require("claude-feedback.comments.thread")
local util = require("claude-feedback.git.util")

local M = {}

local function notify(msg, level)
  notify_mod.show(msg, level)
end

local function filter_by_worktree(comments, worktree_root)
  if not worktree_root then
    return comments
  end
  return vim.tbl_filter(function(c)
    return c.workspace_folder_path == worktree_root
  end, comments)
end

function M.copy(worktree_root)
  local comments = filter_by_worktree(store.get_active_pending(), worktree_root)
  if #comments == 0 then
    notify("No pending review comments to copy", vim.log.levels.WARN)
    return
  end

  local cwd = worktree_root or comments[1].workspace_folder_path
  local text = format.build_review_copy_text(comments, cwd)
  clipboard.copy(text)

  local ids = {}
  for _, c in ipairs(comments) do
    ids[c.id] = true
  end

  store.update(function(state)
    state.reviews = state.reviews or {}
    table.insert(state.reviews, 1, {
      id = store.make_id(),
      created_at = vim.fn.strftime("%Y-%m-%dT%H:%M:%S"),
      comments = comments,
      copied_text = text,
    })
    state.pending = vim.tbl_filter(function(c)
      if worktree_root and c.workspace_folder_path ~= worktree_root then
        return true
      end
      return not ids[c.id]
    end, state.pending)
  end)

  notify(string.format("Copied %d comment(s) + changed files to clipboard", #comments))
end

function M.clear(worktree_root)
  store.update(function(state)
    if worktree_root then
      state.pending = vim.tbl_filter(function(c)
        return c.workspace_folder_path ~= worktree_root
      end, state.pending)
    else
      state.pending = {}
    end
  end)
  notify("Pending review comments cleared")
end

local function pending_title(cwd)
  local resolved = parent.resolve(cwd)
  local changed = changed_files.collect(cwd)
  local parts = { "Code Review · Pending" }
  if resolved then
    parts[#parts + 1] = string.format("%s vs %s", resolved.branch_name, resolved.parent_ref)
  end
  local total = #changed.unstaged + #changed.branch
  if total > 0 then
    parts[#parts + 1] = string.format("%d changed file(s)", total)
  end
  return table.concat(parts, " · ")
end

function M.pending(worktree_root)
  local Snacks = require("snacks")
  local cwd = worktree_root or util.worktree_root(vim.api.nvim_get_current_buf()) or vim.fn.getcwd()
  local changed = changed_files.collect(cwd)
  local items = {}
  local comments = filter_by_worktree(store.get_active_pending(), worktree_root)

  local total_changed = #changed.unstaged + #changed.branch
  if total_changed > 0 then
    items[#items + 1] = {
      text = string.format("Browse %d changed file(s) with diff preview", total_changed),
      item = { action = "files" },
    }
  end

  if #comments > 0 then
    for i, c in ipairs(comments) do
      local preview = store.comment_body_for_send(c):match("^[^\n]+") or ""
      items[#items + 1] = {
        text = string.format("%d. %s:%d — %s", i, c.relative_path, c.line, preview),
        item = { comment_id = c.id },
      }
    end
  else
    items[#items + 1] = {
      text = "No pending comments (already copied? check Resolved batches)",
      item = { hint = true },
    }
  end

  items[#items + 1] = {
    text = "Keys: Enter=open · f=changed files · a=add · y=copy · p=parent · c=clear",
    item = { hint = true },
  }

  Snacks.picker.pick({
    title = pending_title(cwd),
    format = "text",
    items = items,
    preview = "none",
    confirm = function(picker, item)
      if not item or not item.item then
        return
      end
      if item.item.action == "files" then
        picker:close()
        vim.schedule(function()
          M.open_diff()
        end)
        return
      end
      local comment_id = item.item.comment_id
      if comment_id then
        picker:close()
        vim.schedule(function()
          thread.open(comment_id)
        end)
        return
      end
      if item.item.hint then
        notify("Use f=files, a=add, y=copy, p=parent, c=clear", vim.log.levels.INFO)
      end
    end,
    actions = {
      cf_files = {
        desc = "Browse changed files",
        action = function(picker)
          picker:close()
          vim.schedule(M.open_diff)
        end,
      },
      cf_copy = {
        desc = "Copy to clipboard",
        action = function(picker)
          picker:close()
          vim.schedule(function()
            M.copy(worktree_root)
          end)
        end,
      },
      cf_clear = {
        desc = "Clear pending",
        action = function(picker)
          picker:close()
          vim.schedule(function()
            M.clear(worktree_root)
          end)
        end,
      },
      cf_parent = {
        desc = "Set parent branch",
        action = function(picker)
          picker:close()
          vim.schedule(M.set_parent)
        end,
      },
      cf_add = {
        desc = "Add comment",
        action = function(picker)
          picker:close()
          vim.schedule(function()
            require("claude-feedback").add_comment()
          end)
        end,
      },
    },
    win = {
      list = {
        keys = {
          ["f"] = "cf_files",
          ["y"] = "cf_copy",
          ["c"] = "cf_clear",
          ["p"] = "cf_parent",
          ["a"] = "cf_add",
        },
      },
    },
  })
end

function M.resolved()
  local Snacks = require("snacks")
  local batches = store.get_state().reviews or {}
  local items = {}

  for i, batch in ipairs(batches) do
    items[#items + 1] = {
      text = string.format(
        "%d. %s — %d comment(s)",
        i,
        batch.created_at or "unknown",
        #(batch.comments or {})
      ),
      item = { batch_id = batch.id },
      preview = {
        text = batch.copied_text or "",
        ft = "markdown",
        loc = false,
      },
    }
  end

  if #items == 0 then
    notify("No resolved batches", vim.log.levels.INFO)
    return
  end

  Snacks.picker.pick({
    title = "Code Review · Resolved",
    format = "text",
    preview = "preview",
    items = items,
    confirm = function(_, item)
      if not item or not item.item or not item.item.batch_id then
        return
      end
      local batch = store.find_batch_by_id(item.item.batch_id)
      if batch and batch.copied_text and batch.copied_text ~= "" then
        clipboard.copy(batch.copied_text)
        notify("Copied batch text to clipboard")
      end
    end,
    actions = {
      cf_rollback = {
        desc = "Rollback batch",
        action = function(picker, item)
          local batch_id = item and item.item and item.item.batch_id
          local batch = batch_id and store.find_batch_by_id(batch_id)
          if not batch then
            return
          end
          store.update(function(state)
            for idx, b in ipairs(state.reviews) do
              if b.id == batch_id then
                table.remove(state.reviews, idx)
                state.pending = vim.list_extend(batch.comments or {}, state.pending)
                break
              end
            end
          end)
          notify("Batch rolled back to pending")
          picker:close()
        end,
      },
    },
    win = {
      list = {
        keys = {
          ["r"] = "cf_rollback",
        },
      },
    },
  })
end

function M.set_parent()
  local Snacks = require("snacks")
  local cwd = util.worktree_root(vim.api.nvim_get_current_buf()) or vim.fn.getcwd()
  local worktree_root = util.worktree_root(cwd)
  if not worktree_root then
    notify("Not in a git repository", vim.log.levels.WARN)
    return
  end

  local current = parent.resolve(worktree_root)
  local suggestions = parent.suggest_parents(worktree_root)
  local choices = {}

  for _, s in ipairs(suggestions) do
    local src = table.concat(
      vim.tbl_map(function(x)
        return parent.format_source(x)
      end, s.sources),
      " · "
    )
    choices[#choices + 1] = string.format("%s  (%s)", s.ref, src)
  end
  choices[#choices + 1] = "__custom__"
  if store.get_worktree_parent(worktree_root) then
    choices[#choices + 1] = "__clear__"
  end
  choices[#choices + 1] = "__git_config__"

  Snacks.picker.select(choices, {
    prompt = current and string.format("Parent for %s (now: %s)", current.branch_name, current.parent_ref)
      or "Select parent branch",
  }, function(choice)
    if not choice then
      return
    end
    if choice == "__clear__" then
      store.clear_worktree_parent(worktree_root)
      notify("Worktree override cleared")
    elseif choice == "__custom__" then
      Snacks.input({ prompt = "Custom parent ref", default = current and current.parent_ref or "main" }, function(text)
        if text and text ~= "" then
          store.set_worktree_parent(worktree_root, text)
          notify("Worktree parent saved: " .. text)
        end
      end)
    elseif choice == "__git_config__" then
      Snacks.input({ prompt = "Git config parent ref", default = current and current.parent_ref or "main" }, function(text)
        if text and text ~= "" then
          if parent.set_parent_for_branch(worktree_root, text) then
            notify("Saved branch config: " .. text)
          else
            notify("Could not save git config", vim.log.levels.WARN)
          end
        end
      end)
    else
      local ref = choice:match("^(%S+)")
      if ref then
        store.set_worktree_parent(worktree_root, ref)
        notify("Worktree parent saved: " .. ref)
      end
    end
  end)
end

local function diff_text_for_file(worktree, rel_path, section, merge_base_sha)
  if section == "unstaged" then
    local unstaged = util.run_text(worktree, { "diff", "--", rel_path })
    if unstaged and unstaged ~= "" then
      return unstaged
    end
    return util.run_text(worktree, { "diff", "--no-index", "--", "/dev/null", rel_path }) or ""
  end
  if merge_base_sha then
    return util.run_text(worktree, { "diff", merge_base_sha .. "..HEAD", "--", rel_path }) or ""
  end
  return ""
end

local function build_diff_picker_items(cwd)
  local items = {}
  local resolved = parent.resolve(cwd)
  local worktree = util.worktree_root(cwd)
  if not worktree then
    return items, nil
  end

  local changed = changed_files.collect(cwd)
  local seen = {}

  local function add_file(f, section, label)
    if seen[f.path] then
      return
    end
    seen[f.path] = true
    local full = worktree .. "/" .. f.path
    local preview_text = diff_text_for_file(worktree, f.path, section, resolved and resolved.merge_base_sha)
    items[#items + 1] = {
      text = string.format("[%s] %s %s", label, changed_files.format_status(f.status), f.path),
      file = full,
      item = { rel = f.path, section = section },
      preview = {
        text = preview_text ~= "" and preview_text or "(no diff)",
        ft = "diff",
        loc = false,
      },
    }
  end

  local branch_label = resolved and resolved.parent_ref or "parent"
  for _, f in ipairs(changed.branch) do
    add_file(f, "branch", branch_label)
  end
  for _, f in ipairs(changed.unstaged) do
    add_file(f, "unstaged", "unstaged")
  end

  return items, resolved
end

local function open_file_diff_split(worktree, rel_path, section, merge_base_sha)
  local diff_text = diff_text_for_file(worktree, rel_path, section, merge_base_sha)
  if diff_text == "" then
    notify("No diff for " .. rel_path, vim.log.levels.INFO)
    return
  end

  vim.cmd("split")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(diff_text, "\n", { plain = true }))
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "diff"
  vim.bo[buf].modifiable = false
end

function M.open_diff(file_path)
  local Snacks = require("snacks")
  local cwd = util.worktree_root(vim.api.nvim_get_current_buf()) or vim.fn.getcwd()
  local items, resolved = build_diff_picker_items(cwd)

  if #items == 0 then
    notify("No changed files found", vim.log.levels.INFO)
    return
  end

  local worktree = resolved and resolved.worktree_root or util.worktree_root(cwd)
  local merge_base = resolved and resolved.merge_base_sha

  Snacks.picker.pick({
    title = "Changed files · diff",
    format = "text",
    preview = "preview",
    items = items,
    confirm = function(picker, item)
      if not item or not item.file then
        return
      end
      picker:close()
      vim.schedule(function()
        vim.cmd("edit " .. vim.fn.fnameescape(item.file))
      end)
    end,
    actions = {
      cf_open_diff = {
        desc = "Open diff in split",
        action = function(picker, item)
          if not item or not item.item or not worktree then
            return
          end
          picker:close()
          vim.schedule(function()
            open_file_diff_split(worktree, item.item.rel, item.item.section, merge_base)
          end)
        end,
      },
    },
    win = {
      list = {
        keys = {
          ["d"] = "cf_open_diff",
        },
      },
    },
  })
end

return M
