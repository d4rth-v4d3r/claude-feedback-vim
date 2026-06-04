local config = require("claude-feedback.config")
local store = require("claude-feedback.store")
local util = require("claude-feedback.git.util")

local M = {}

local SOURCE_RANK = {
  worktree_override = 100,
  branch_config = 90,
  upstream = 50,
  workspace_setting = 40,
  origin_head = 20,
  fallback = 10,
}

local function upstream_distinct(cwd, origin_sym, branch_name)
  if not branch_name or branch_name == "HEAD" then
    return nil
  end
  if not util.rev_parse(cwd, "@{upstream}") then
    return nil
  end
  local abbrev = util.run_text(cwd, { "rev-parse", "--abbrev-ref", "@{upstream}" })
  if not abbrev or abbrev == "" then
    return nil
  end
  local up_sha = util.rev_parse(cwd, "@{upstream}")
  local head_sha = util.rev_parse(cwd, "HEAD")
  if up_sha and head_sha and up_sha == head_sha then
    return nil
  end
  local tracked = abbrev:match("^[^/]+/(.+)$")
  if tracked and tracked == branch_name then
    return nil
  end
  if origin_sym then
    local def_sha = util.rev_parse(cwd, origin_sym)
    if def_sha and up_sha and def_sha == up_sha then
      return nil
    end
  end
  if not util.merge_base(cwd, abbrev) then
    return nil
  end
  return abbrev
end

local function build_candidates(cwd, worktree_root, branch_name)
  local opts = config.get()
  local key = opts.parent_branch.config_key
  local tiers = {}

  local wt_ov = store.get_worktree_parent(worktree_root)
  if wt_ov and wt_ov ~= "" then
    tiers[#tiers + 1] = { ref = wt_ov, source = "worktree_override" }
  end

  if branch_name and branch_name ~= "HEAD" then
    local cfg = util.git_config(cwd, string.format("branch.%s.%s", branch_name, key))
    if cfg then
      tiers[#tiers + 1] = { ref = cfg, source = "branch_config" }
    end
  end

  local origin_sym = util.origin_head(cwd)
  if branch_name and branch_name ~= "HEAD" then
    local up = upstream_distinct(cwd, origin_sym, branch_name)
    if up then
      tiers[#tiers + 1] = { ref = up, source = "upstream" }
    end
  end

  if origin_sym then
    tiers[#tiers + 1] = { ref = origin_sym, source = "origin_head" }
  end

  tiers[#tiers + 1] = { ref = opts.parent_branch.fallback, source = "fallback" }
  if opts.parent_branch.fallback == "main" then
    tiers[#tiers + 1] = { ref = "master", source = "fallback" }
  elseif opts.parent_branch.fallback == "master" then
    tiers[#tiers + 1] = { ref = "main", source = "fallback" }
  end

  return tiers
end

local function validate(cwd, tiers)
  local out = {}
  local seen_mb = {}
  for _, raw in ipairs(tiers) do
    local sha = util.merge_base(cwd, raw.ref)
    if sha and not seen_mb[sha] then
      seen_mb[sha] = true
      out[#out + 1] = {
        ref = raw.ref,
        source = raw.source,
        merge_base_sha = sha,
      }
    end
  end
  return out
end

function M.resolve(cwd)
  cwd = cwd or vim.fn.getcwd()
  local worktree_root = util.worktree_root(cwd)
  if not worktree_root then
    return nil
  end
  local branch_name = util.normalize_branch(util.branch_name(worktree_root))
  local validated = validate(worktree_root, build_candidates(worktree_root, worktree_root, branch_name))
  local best = validated[1]
  if not best then
    return nil
  end
  return {
    repo_root = worktree_root,
    worktree_root = worktree_root,
    branch_name = branch_name,
    parent_ref = best.ref,
    merge_base_sha = best.merge_base_sha,
    source = best.source,
  }
end

function M.format_source(source)
  local labels = {
    worktree_override = "worktree override",
    branch_config = "git config",
    upstream = "@{upstream}",
    workspace_setting = "setting",
    origin_head = "default branch",
    fallback = "fallback",
  }
  return labels[source] or source
end

function M.suggest_parents(cwd)
  cwd = cwd or vim.fn.getcwd()
  local worktree_root = util.worktree_root(cwd)
  if not worktree_root then
    return {}
  end
  local branch_name = util.normalize_branch(util.branch_name(worktree_root))
  local validated = validate(worktree_root, build_candidates(worktree_root, worktree_root, branch_name))
  local by_ref = {}
  local order = {}
  for _, v in ipairs(validated) do
    if not by_ref[v.ref] then
      by_ref[v.ref] = {}
      order[#order + 1] = v.ref
    end
    if not vim.tbl_contains(by_ref[v.ref], v.source) then
      by_ref[v.ref][#by_ref[v.ref] + 1] = v.source
    end
  end
  local suggestions = {}
  for _, ref in ipairs(order) do
    table.sort(by_ref[ref], function(a, b)
      return (SOURCE_RANK[a] or 0) > (SOURCE_RANK[b] or 0)
    end)
    suggestions[#suggestions + 1] = { ref = ref, sources = by_ref[ref] }
  end
  for _, b in ipairs(util.list_branches(worktree_root)) do
    if not by_ref[b] and util.merge_base(worktree_root, b) then
      suggestions[#suggestions + 1] = { ref = b, sources = { "branch" } }
    end
  end
  return suggestions
end

function M.set_parent_for_branch(cwd, parent_ref)
  cwd = cwd or vim.fn.getcwd()
  local worktree_root = util.worktree_root(cwd)
  if not worktree_root then
    return false
  end
  local branch = util.branch_name(worktree_root)
  if not branch or branch == "HEAD" then
    return false
  end
  local key = string.format("branch.%s.%s", branch, config.get().parent_branch.config_key)
  return util.set_git_config(worktree_root, key, parent_ref)
end

return M
