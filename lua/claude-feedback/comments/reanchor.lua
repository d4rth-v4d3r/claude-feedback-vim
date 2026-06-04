local store = require("claude-feedback.store")

local M = {}

local function strip_context_marker(line)
  return line:gsub("^[> ]%s*L%d+:%s?", function(m)
    return m:sub(1, 1) == ">" and ">" or ""
  end)
end

local function strip_leading_marker(line)
  if line:sub(1, 1) == ">" then
    return line:sub(2):gsub("^%s+", "")
  end
  return line:gsub("^%s+", "")
end

function M.locate_anchor_line(document_lines, comment)
  local expected = comment.context or {}
  if #expected == 0 then
    return nil
  end

  local anchor_offset = nil
  local cleaned_expected = {}
  for i, line in ipairs(expected) do
    local stripped = strip_context_marker(line)
    if stripped:sub(1, 1) == ">" then
      anchor_offset = i - 1
    end
    cleaned_expected[i] = strip_leading_marker(stripped)
  end

  if vim.tbl_isempty(cleaned_expected) then
    return nil
  end

  local window_size = #cleaned_expected
  local best_line = nil
  local best_score = 0

  for start = 0, math.max(0, #document_lines - window_size) do
    local score = 0
    for i = 1, window_size do
      local got = (document_lines[start + i] or ""):gsub("^%s+", ""):gsub("%s+$", "")
      local want = cleaned_expected[i]:gsub("^%s+", ""):gsub("%s+$", "")
      if got ~= "" and got == want then
        score = score + (i - 1 == anchor_offset and 2 or 1)
      end
    end
    if score > best_score then
      best_score = score
      best_line = start
    end
  end

  if best_line == nil or best_score == 0 then
    return nil
  end

  local anchor = best_line + (anchor_offset or 0) + 1
  return math.max(1, math.min(#document_lines, anchor))
end

function M.reanchor_buffer(bufnr)
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  if file_path == "" then
    return
  end

  local document_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local updates = {}

  for _, comment in ipairs(store.get_pending()) do
    if comment.file_path == file_path and comment.status == "pending" then
      local next_line = M.locate_anchor_line(document_lines, comment)
      if next_line and next_line ~= comment.line then
        updates[#updates + 1] = { id = comment.id, line = next_line }
      end
    end
  end

  if #updates == 0 then
    return
  end

  store.update(function(state)
    for _, u in ipairs(updates) do
      for _, c in ipairs(state.pending) do
        if c.id == u.id then
          c.line = u.line
        end
      end
    end
  end)
end

return M
