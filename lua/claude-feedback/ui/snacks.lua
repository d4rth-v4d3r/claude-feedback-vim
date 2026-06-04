local changed_files = require("claude-feedback.git.changed_files")
local clipboard = require("claude-feedback.clipboard")
local format = require("claude-feedback.format")
local parent = require("claude-feedback.git.parent")
local store = require("claude-feedback.store")
local thread = require("claude-feedback.comments.thread")
local util = require("claude-feedback.git.util")

local M = {}

local function notify(msg, level)
  require("snacks").notifier(msg, level or vim.log.levels.INFO)
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

local function build_header_items(cwd)
  local items = {}
  local resolved = parent.resolve(cwd)
  local changed = changed_files.collect(cwd)

  if resolved then
    items[#items + 1] = {
      text = string.format(
        "[ %s · parent: %s (%s) ]",
        resolved.branch_name,
        resolved.parent_ref,
        parent.format_source(resolved.source)
      ),
      disabled = true,
    }
  end

  if #changed.unstaged > 0 then
    items[#items + 1] = {
      text = string.format("Changed (unstaged): %d file(s)", #changed.unstaged),
      disabled = true,
    }
    for _, f in ipairs(changed.unstaged) do
      items[#items + 1] = {
        text = string.format("  %s %s", changed_files.format_status(f.status), f.path),
        disabled = true,
      }
    end
  end

  if #changed.branch > 0 then
    local label = resolved and resolved.parent_ref or "parent"
    items[#items + 1] = {
      text = string.format("Changed (vs %s): %d file(s)", label, #changed.branch),
      disabled = true,
    }
    for _, f in ipairs(changed.branch) do
      items[#items + 1] = {
        text = string.format("  %s %s", changed_files.format_status(f.status), f.path),
        disabled = true,
      }
    end
  end

  return items
end

function M.pending(worktree_root)
  local Snacks = require("snacks")
  local cwd = worktree_root or util.worktree_root(vim.api.nvim_get_current_buf()) or vim.fn.getcwd()
  local items = build_header_items(cwd)
  local comments = filter_by_worktree(store.get_active_pending(), worktree_root)

  if #comments > 0 then
    items[#items + 1] = { text = string.format("Pending comments (%d)", #comments), disabled = true }
    for i, c in ipairs(comments) do
      local preview = store.comment_body_for_send(c):match("^[^\n]+") or ""
      items[#items + 1] = {
        text = string.format("%d. %s:%d — %s", i, c.relative_path, c.line, preview),
        file = c.file_path,
        line = tostring(c.line),
        item = { comment_id = c.id },
      }
    end
  else
    items[#items + 1] = { text = "No pending comments", disabled = true }
  end

  Snacks.picker.pick({
    title = "Code Review · Pending",
    items = items,
    preview = "none",
    confirm = function(picker, item)
      local comment_id = item and item.item and item.item.comment_id
      if comment_id then
        picker:close()
        vim.schedule(function()
          thread.open(comment_id)
        end)
      end
    end,
    actions = {
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
      item = { batch = batch },
      preview = {
        text = batch.copied_text or "",
        ft = "markdown",
      },
    }
  end

  if #items == 0 then
    notify("No resolved batches", vim.log.levels.INFO)
    return
  end

  Snacks.picker.pick({
    title = "Code Review · Resolved",
    items = items,
    actions = {
      cf_rollback = {
        desc = "Rollback batch",
        action = function(picker, item)
          local batch = item and item.item and item.item.batch
          if not batch then
            return
          end
          store.update(function(state)
            for idx, b in ipairs(state.reviews) do
              if b.id == batch.id then
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

function M.open_diff(file_path)
  file_path = file_path or vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
  if file_path == "" then
    return
  end

  local resolved = parent.resolve(file_path)
  if not resolved or not resolved.merge_base_sha then
    notify("Could not resolve parent branch", vim.log.levels.WARN)
    return
  end

  local rel = util.relative_path(resolved.worktree_root, file_path)
  vim.cmd("split")
  vim.cmd("enew")
  vim.bo.buftype = "nofile"
  vim.bo.bufhidden = "wipe"
  vim.bo.filetype = "diff"
  vim.fn.jobstart({
    "git",
    "diff",
    resolved.merge_base_sha .. "..HEAD",
    "--",
    rel,
  }, {
    cwd = resolved.worktree_root,
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        local line_count = vim.api.nvim_buf_line_count(0)
        vim.api.nvim_buf_set_lines(0, line_count, line_count, false, data)
      end
    end,
  })
end

return M
