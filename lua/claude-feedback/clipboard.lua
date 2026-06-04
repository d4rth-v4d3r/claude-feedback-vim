local M = {}

local function detect_clipboard_cmd()
  if vim.fn.executable("pbcopy") == 1 then
    return { "pbcopy" }
  end
  if vim.fn.executable("wl-copy") == 1 then
    return { "wl-copy", "--no-newline" }
  end
  if vim.fn.executable("xclip") == 1 then
    return { "xclip", "-selection", "clipboard" }
  end
  return nil
end

function M.copy(text)
  local cmd = detect_clipboard_cmd()
  if cmd then
    if cmd[1] == "pbcopy" then
      vim.fn.system("pbcopy", text)
    else
      vim.system(cmd, { stdin = text }):wait()
    end
    if vim.v.shell_error == 0 then
      vim.fn.setreg("+", text)
      vim.fn.setreg("*", text)
      return true
    end
  end

  vim.fn.setreg("+", text)
  vim.fn.setreg("*", text)
  return true
end

return M
