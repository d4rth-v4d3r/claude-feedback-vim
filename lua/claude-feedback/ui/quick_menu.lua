local M = {}

function M.open()
  local Snacks = require("snacks")
  Snacks.picker.select({
    "Add review comment",
    "Open pending list",
    "Copy to clipboard",
    "Open diff vs parent",
    "Set parent branch",
    "Resolved batches",
  }, { prompt = "Code Review" }, function(choice)
    if not choice then
      return
    end
    local cf = require("claude-feedback")
    if choice == "Add review comment" then
      cf.add_comment()
    elseif choice == "Open pending list" then
      cf.pending()
    elseif choice == "Copy to clipboard" then
      cf.copy()
    elseif choice == "Open diff vs parent" then
      cf.diff()
    elseif choice == "Set parent branch" then
      cf.set_parent()
    elseif choice == "Resolved batches" then
      cf.resolved()
    end
  end)
end

return M
