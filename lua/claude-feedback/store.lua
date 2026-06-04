local M = {}

local state_path = nil
local state = { pending = {}, reviews = {}, worktree_parents = {} }
local listeners = {}

local function path()
  if not state_path then
    state_path = vim.fn.stdpath("data") .. "/claude-feedback/state.json"
  end
  return state_path
end

local function ensure_dir()
  local dir = vim.fn.fnamemodify(path(), ":h")
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
end

local function migrate_comment(c)
  c.status = c.status or "pending"
  if not c.messages or #c.messages == 0 then
    local body = (c.comment or ""):gsub("^%s+", ""):gsub("%s+$", "")
    c.messages = body ~= "" and {
      {
        id = c.id .. "-m0",
        author = "You",
        body = body,
        created_at = c.created_at or vim.fn.strftime("%Y-%m-%dT%H:%M:%S"),
      },
    } or {}
  end
  return c
end

local function load()
  ensure_dir()
  local f = io.open(path(), "r")
  if not f then
    return
  end
  local raw = f:read("*a")
  f:close()
  if raw and raw ~= "" then
    local ok, decoded = pcall(vim.json.decode, raw)
    if ok and type(decoded) == "table" then
      state.pending = vim.tbl_map(migrate_comment, decoded.pending or {})
      state.reviews = decoded.reviews or {}
      state.worktree_parents = decoded.worktree_parents or {}
      for _, batch in ipairs(state.reviews) do
        batch.comments = vim.tbl_map(migrate_comment, batch.comments or {})
      end
    end
  end
end

local function save()
  ensure_dir()
  local f = io.open(path(), "w")
  if not f then
    return
  end
  f:write(vim.json.encode(state))
  f:close()
end

function M.init()
  load()
end

function M.on_change(fn)
  listeners[#listeners + 1] = fn
end

local function notify()
  for _, fn in ipairs(listeners) do
    pcall(fn)
  end
end

function M.get_state()
  return state
end

function M.get_pending()
  return state.pending
end

function M.get_active_pending()
  local out = {}
  for _, c in ipairs(state.pending) do
    if c.status == "pending" then
      out[#out + 1] = c
    end
  end
  return out
end

function M.find_by_id(id)
  for _, c in ipairs(state.pending) do
    if c.id == id then
      return c
    end
  end
  for _, batch in ipairs(state.reviews) do
    for _, c in ipairs(batch.comments or {}) do
      if c.id == id then
        return c
      end
    end
  end
end

function M.update(mutator)
  mutator(state)
  save()
  notify()
end

function M.make_id()
  return string.format("%d-%s", vim.loop.hrtime(), math.random(100000, 999999))
end

function M.comment_body_for_send(comment)
  local messages = comment.messages or {}
  if #messages == 0 then
    return (comment.comment or ""):gsub("^%s+", ""):gsub("%s+$", "")
  end
  if #messages == 1 then
    return messages[1].body:gsub("^%s+", ""):gsub("%s+$", "")
  end
  local lines = {}
  for i, m in ipairs(messages) do
    local body = m.body:gsub("^%s+", ""):gsub("%s+$", "")
    if i == 1 then
      lines[#lines + 1] = body
    else
      lines[#lines + 1] = string.format("↳ %s: %s", m.author or "You", body)
    end
  end
  return table.concat(lines, "\n")
end

function M.get_worktree_parent(worktree_root)
  return state.worktree_parents[worktree_root]
end

function M.set_worktree_parent(worktree_root, parent_ref)
  state.worktree_parents[worktree_root] = parent_ref
  save()
  notify()
end

function M.clear_worktree_parent(worktree_root)
  if state.worktree_parents[worktree_root] then
    state.worktree_parents[worktree_root] = nil
    save()
    notify()
    return true
  end
  return false
end

function M.get_worktree_parents()
  return state.worktree_parents
end

return M
