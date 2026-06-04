local config = require("claude-feedback.config")
local notify = require("claude-feedback.notify")
local store = require("claude-feedback.store")

local M = {}

local function get_comment_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  if file_path == "" then
    return nil
  end
  local line = vim.api.nvim_win_get_cursor(0)[1]
  for _, c in ipairs(store.get_active_pending()) do
    if c.file_path == file_path and c.line == line then
      return c
    end
  end
  return nil
end

local function build_lines(comment)
  local opts = config.get().float
  local lines = {}
  lines[#lines + 1] = string.format("Review · %s:%d", comment.relative_path, comment.line)
  lines[#lines + 1] = string.rep("─", 40)

  if opts.show_context and comment.context then
    for _, ctx in ipairs(comment.context) do
      lines[#lines + 1] = "  " .. ctx
    end
    lines[#lines + 1] = string.rep("─", 40)
  end

  for i, m in ipairs(comment.messages or {}) do
    if i == 1 then
      lines[#lines + 1] = string.format("%s: %s", m.author or "You", m.body)
    else
      lines[#lines + 1] = string.format("↳ %s: %s", m.author or "You", m.body)
    end
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "[r] reply  [e] edit  [d] delete  [q] close"
  return lines
end

local function refresh_float(win, comment_id)
  local comment = store.find_by_id(comment_id)
  if not comment or not win.buf or not vim.api.nvim_buf_is_valid(win.buf) then
    return
  end
  local lines = build_lines(comment)
  vim.api.nvim_buf_set_lines(win.buf, 0, -1, false, lines)
end

local function open_float(comment)
  local Snacks = require("snacks")
  local comment_id = comment.id

  Snacks.win({
    text = build_lines(comment),
    wo = { wrap = true },
    width = math.min(config.get().float.max_width, vim.o.columns - 4),
    height = math.min(16, #build_lines(comment) + 1),
    border = config.get().float.border,
    title = " Code Review ",
    title_pos = "center",
    footer_keys = { "r", "e", "d", "q" },
    keys = {
      q = "close",
      ["<esc>"] = "close",
      r = function(self)
        Snacks.input({ prompt = "Reply to review comment" }, function(text)
          text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
          if text == "" then
            return
          end
          store.update(function(state)
            for _, c in ipairs(state.pending) do
              if c.id == comment_id then
                c.messages = c.messages or {}
                c.messages[#c.messages + 1] = {
                  id = comment_id .. "-m" .. #c.messages,
                  author = "You",
                  body = text,
                  created_at = vim.fn.strftime("%Y-%m-%dT%H:%M:%S"),
                }
              end
            end
          end)
          refresh_float(self, comment_id)
        end)
      end,
      e = function(self)
        local current = store.find_by_id(comment_id)
        local first = current and current.messages and current.messages[1]
        if not first then
          return
        end
        Snacks.input({ prompt = "Edit review comment", default = first.body }, function(text)
          text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
          if text == "" then
            return
          end
          store.update(function(state)
            for _, c in ipairs(state.pending) do
              if c.id == comment_id and c.messages[1] then
                c.messages[1].body = text
                c.messages[1].edited_at = vim.fn.strftime("%Y-%m-%dT%H:%M:%S")
              end
            end
          end)
          refresh_float(self, comment_id)
        end)
      end,
      d = function(self)
        store.update(function(state)
          state.pending = vim.tbl_filter(function(c)
            return c.id ~= comment_id
          end, state.pending)
        end)
        notify.show("Review comment deleted", vim.log.levels.INFO)
        self:close()
      end,
    },
  })
end

function M.open(comment_id)
  local comment = comment_id and store.find_by_id(comment_id) or get_comment_at_cursor()
  if not comment then
    notify.show("No review comment on this line", vim.log.levels.WARN)
    return
  end
  open_float(comment)
end

function M.jump(direction)
  local bufnr = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  if file_path == "" then
    return
  end

  local comments = {}
  for _, c in ipairs(store.get_active_pending()) do
    if c.file_path == file_path then
      comments[#comments + 1] = c
    end
  end
  table.sort(comments, function(a, b)
    return a.line < b.line
  end)

  if #comments == 0 then
    notify.show("No review comments in this file", vim.log.levels.INFO)
    return
  end

  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local target = nil

  if direction > 0 then
    for _, c in ipairs(comments) do
      if c.line > cursor_line then
        target = c
        break
      end
    end
    target = target or comments[1]
  else
    for i = #comments, 1, -1 do
      if comments[i].line < cursor_line then
        target = comments[i]
        break
      end
    end
    target = target or comments[#comments]
  end

  if target then
    vim.api.nvim_win_set_cursor(0, { target.line, 0 })
    vim.cmd("normal! zz")
    open_float(target)
  end
end

return M
