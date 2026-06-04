local M = {}

M.defaults = {
  signs = {
    enabled = true,
    text = "󰍡",
    show_preview = true,
    preview_max_len = 60,
    hl_group = "ClaudeFeedbackSign",
    preview_hl_group = "ClaudeFeedbackPreview",
  },
  float = {
    border = "rounded",
    max_width = 72,
    show_context = true,
  },
  changed_files = {
    mode = "both", -- "unstaged" | "branch" | "both"
  },
  parent_branch = {
    fallback = "main",
    config_key = "codeReviewParent",
  },
  copy = {
    include_changed_files = true,
    -- Clipboard file list: "branch" (vs parent only), "unstaged", or "both"
    changed_files_mode = "branch",
    include_diff_instruction = true,
    include_absolute_paths = true,
  },
  keys = {
    add = "<leader>ra",
    thread = "<leader>rt",
    next = "]r",
    prev = "[r",
    menu = "<leader>rv",
    copy = "<leader>ry",
  },
}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
  return M.options
end

function M.get()
  return M.options or M.defaults
end

return M
