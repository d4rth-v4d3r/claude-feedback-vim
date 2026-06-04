return {
  "d4rth-v4d3r/claude-feedback-vim",
  event = "VeryLazy",
  dependencies = { "folke/snacks.nvim" },
  cmd = {
    "ClaudeFeedbackAdd",
    "ClaudeFeedbackThread",
    "ClaudeFeedbackNext",
    "ClaudeFeedbackPrev",
    "ClaudeFeedbackMenu",
    "ClaudeFeedbackPending",
    "ClaudeFeedbackCopy",
    "ClaudeFeedbackSetParent",
    "ClaudeFeedbackResolved",
    "ClaudeFeedbackClear",
  },
  opts = {},
  keys = {
    { "<leader>ra", function() require("claude-feedback").add_comment() end, desc = "Add review comment" },
    { "<leader>rt", function() require("claude-feedback").thread() end, desc = "Open review thread" },
    { "<leader>rv", function() require("claude-feedback").menu() end, desc = "Code review menu" },
    { "<leader>ry", function() require("claude-feedback").copy() end, desc = "Copy review to clipboard" },
    { "]r", function() require("claude-feedback").next_comment() end, desc = "Next review comment" },
    { "[r", function() require("claude-feedback").prev_comment() end, desc = "Prev review comment" },
  },
  config = function(_, opts)
    require("claude-feedback").setup(opts)
  end,
}
