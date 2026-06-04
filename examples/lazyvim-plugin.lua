return {
  "d4rth-v4d3r/claude-feedback-vim",
  dependencies = { "folke/snacks.nvim" },
  opts = {},
  keys = {
    { "<leader>cr", function() require("claude-feedback").add_comment() end, desc = "Add review comment" },
    { "<leader>ct", function() require("claude-feedback").thread() end, desc = "Open review thread" },
    { "<leader>cm", function() require("claude-feedback").menu() end, desc = "Code review menu" },
    { "<leader>cy", function() require("claude-feedback").copy() end, desc = "Copy review to clipboard" },
    { "]c", function() require("claude-feedback").next_comment() end, desc = "Next review comment" },
    { "[c", function() require("claude-feedback").prev_comment() end, desc = "Prev review comment" },
  },
  config = function(_, opts)
    require("claude-feedback").setup(opts)
  end,
}
