local notify = require("claude-feedback.notify")

local M = {}

local actions = {
  ["Add review comment"] = "add_comment",
  ["Open pending list"] = "pending",
  ["Copy to clipboard"] = "copy",
  ["Set parent branch"] = "set_parent",
  ["Resolved batches"] = "resolved",
}

function M.open()
  local Snacks = require("snacks")
  Snacks.picker.select({
    "Add review comment",
    "Open pending list",
    "Copy to clipboard",
    "Set parent branch",
    "Resolved batches",
  }, { prompt = "Code Review" }, function(choice)
    if not choice then
      return
    end
    local fn_name = actions[choice]
    if not fn_name then
      return
    end
    vim.schedule(function()
      local cf = require("claude-feedback")
      local fn = cf[fn_name]
      if type(fn) ~= "function" then
        notify.show("Unknown action: " .. fn_name, vim.log.levels.ERROR)
        return
      end
      local ok, err = pcall(fn)
      if not ok then
        notify.show(tostring(err), vim.log.levels.ERROR)
      end
    end)
  end)
end

return M
