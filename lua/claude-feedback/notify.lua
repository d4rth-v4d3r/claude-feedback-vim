local M = {}

function M.show(msg, level)
  level = level or vim.log.levels.INFO
  local ok = pcall(function()
    require("snacks").notifier.notify(msg, level, { title = "Claude Feedback" })
  end)
  if not ok then
    vim.notify(msg, level, { title = "Claude Feedback" })
  end
end

return M
