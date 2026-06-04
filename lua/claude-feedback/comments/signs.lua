local config = require("claude-feedback.config")
local store = require("claude-feedback.store")

local M = {}

local ns = vim.api.nvim_create_namespace("claude-feedback")
local marks = {}

local function truncate(text, max_len)
  if #text <= max_len then
    return text
  end
  return text:sub(1, max_len - 1) .. "…"
end

local function preview_text(comment)
  local opts = config.get().signs
  local body = store.comment_body_for_send(comment)
  local first_line = body:match("^[^\n]+") or body
  if opts.show_preview then
    return opts.text .. " " .. truncate(first_line, opts.preview_max_len)
  end
  return nil
end

function M.namespace()
  return ns
end

local function clear_comment_mark(comment_id)
  local mark = marks[comment_id]
  if mark then
    pcall(vim.api.nvim_buf_del_extmark, mark.bufnr, ns, mark.id)
    marks[comment_id] = nil
  end
end

function M.clear_buffer(bufnr)
  for comment_id, mark in pairs(marks) do
    if mark.bufnr == bufnr then
      pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, mark.id)
      marks[comment_id] = nil
    end
  end
end

function M.place_comment(comment)
  local opts = config.get()
  if not opts.signs.enabled then
    return
  end

  clear_comment_mark(comment.id)

  local bufnr = vim.fn.bufadd(comment.file_path)
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end

  local line = math.max(0, comment.line - 1)
  local preview = preview_text(comment)
  local virt_text = preview and { { preview, opts.signs.preview_hl_group } } or nil

  local id = vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, {
    sign_text = opts.signs.text,
    sign_hl_group = opts.signs.hl_group,
    virt_text = virt_text,
    virt_text_pos = "eol",
    priority = 100,
  })

  marks[comment.id] = { bufnr = bufnr, id = id }
end

function M.refresh_all()
  for comment_id in pairs(marks) do
    clear_comment_mark(comment_id)
  end

  for _, comment in ipairs(store.get_active_pending()) do
    M.place_comment(comment)
  end
end

function M.refresh_file(file_path)
  local bufnr = vim.fn.bufadd(file_path)
  M.clear_buffer(bufnr)
  for _, comment in ipairs(store.get_active_pending()) do
    if comment.file_path == file_path then
      M.place_comment(comment)
    end
  end
end

function M.setup_highlights()
  local opts = config.get().signs
  vim.api.nvim_set_hl(0, opts.hl_group, { link = "DiagnosticInfo", default = true })
  vim.api.nvim_set_hl(0, opts.preview_hl_group, { link = "Comment", default = true })
end

return M
