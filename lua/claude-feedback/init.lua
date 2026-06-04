local config = require("claude-feedback.config")
local store = require("claude-feedback.store")
local signs = require("claude-feedback.comments.signs")
local reanchor = require("claude-feedback.comments.reanchor")
local add = require("claude-feedback.comments.add")
local thread = require("claude-feedback.comments.thread")
local ui = require("claude-feedback.ui.snacks")
local quick_menu = require("claude-feedback.ui.quick_menu")

local M = {}

local function setup_autocmds()
  local group = vim.api.nvim_create_augroup("ClaudeFeedback", { clear = true })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(args)
      reanchor.reanchor_buffer(args.buf)
    end,
  })

  store.on_change(function()
    signs.refresh_all()
  end)

  vim.api.nvim_create_autocmd({ "BufEnter", "BufReadPost" }, {
    group = group,
    callback = function(args)
      local file_path = vim.api.nvim_buf_get_name(args.buf)
      if file_path ~= "" then
        signs.refresh_file(file_path)
      end
    end,
  })
end

local function setup_commands()
  vim.api.nvim_create_user_command("ClaudeFeedbackAdd", function()
    M.add_comment()
  end, { desc = "Add review comment at cursor" })

  vim.api.nvim_create_user_command("ClaudeFeedbackThread", function()
    M.thread()
  end, { desc = "Open review thread at cursor" })

  vim.api.nvim_create_user_command("ClaudeFeedbackNext", function()
    M.next_comment()
  end, { desc = "Jump to next review comment" })

  vim.api.nvim_create_user_command("ClaudeFeedbackPrev", function()
    M.prev_comment()
  end, { desc = "Jump to previous review comment" })

  vim.api.nvim_create_user_command("ClaudeFeedbackMenu", function()
    M.menu()
  end, { desc = "Code review quick menu" })

  vim.api.nvim_create_user_command("ClaudeFeedbackPending", function()
    M.pending()
  end, { desc = "Open pending review picker" })

  vim.api.nvim_create_user_command("ClaudeFeedbackCopy", function()
    M.copy()
  end, { desc = "Copy review batch to clipboard" })

  vim.api.nvim_create_user_command("ClaudeFeedbackSetParent", function()
    M.set_parent()
  end, { desc = "Set diff parent branch" })

  vim.api.nvim_create_user_command("ClaudeFeedbackDiff", function()
    M.diff()
  end, { desc = "Open diff vs parent branch" })

  vim.api.nvim_create_user_command("ClaudeFeedbackResolved", function()
    M.resolved()
  end, { desc = "Open resolved batches" })

  vim.api.nvim_create_user_command("ClaudeFeedbackClear", function()
    M.clear()
  end, { desc = "Clear pending review comments" })
end

function M.setup(opts)
  config.setup(opts)
  store.init()
  signs.setup_highlights()
  setup_autocmds()
  setup_commands()
  signs.refresh_all()
end

function M.add_comment()
  local Snacks = require("snacks")
  local bufnr = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local raw = (vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""):gsub("^%s+", "")
  local hint = raw ~= "" and string.format("Line %d: %s", line, raw:sub(1, 80)) or string.format("Line %d", line)

  Snacks.input({ prompt = "Review comment · " .. hint }, function(text)
    if not text then
      return
    end
    local ok, err = add.add_at_cursor(text)
    if not ok then
      vim.notify(err, vim.log.levels.WARN)
    else
      vim.notify("Review comment added to pending", vim.log.levels.INFO)
    end
  end)
end

function M.thread()
  thread.open()
end

function M.next_comment()
  thread.jump(1)
end

function M.prev_comment()
  thread.jump(-1)
end

function M.menu()
  quick_menu.open()
end

function M.pending()
  ui.pending()
end

function M.copy()
  ui.copy()
end

function M.clear()
  ui.clear()
end

function M.set_parent()
  ui.set_parent()
end

function M.diff()
  ui.open_diff()
end

function M.resolved()
  ui.resolved()
end

return M
