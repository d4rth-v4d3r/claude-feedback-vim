# Claude Feedback for Neovim / LazyVim

A Neovim plugin inspired by [claude-feedback](https://github.com/d4rth-v4d3r/claude-feedback) (VS Code). Collect line-level code review comments in the editor, see changed files, and **copy a formatted batch to the clipboard** — paste it into Claude Code, Cursor, or anywhere else.

## Why this plugin?

The VS Code extension auto-launches Claude in a terminal. This Neovim port is built for a simpler workflow:

1. Add comments on specific lines while reviewing code
2. See **unstaged** and **branch-vs-parent** changed file lists in one place
3. Press copy → paste wherever you want

No Graphite, Git Town, or `gh` — plain git only.

## Features

- **Inline markers** — sign column icon + optional virt_text preview on commented lines
- **Thread float** — reply, edit, delete at the cursor (`<leader>ct`)
- **Jump between comments** — `]c` / `[c` in the current buffer
- **Pending picker** — changed files header + all pending comments
- **Copy to clipboard** — primary send action; archives batch to history
- **Parent branch picker** — manual base branch per worktree, or save to git config
- **Re-anchor on save** — comments follow line edits when possible
- **Resolved batches** — rollback sent batches back to pending

## Requirements

| Requirement | Notes |
|-------------|-------|
| Neovim **0.10+** | Uses `vim.system` |
| [snacks.nvim](https://github.com/folke/snacks.nvim) | Input, picker, float windows |
| `git` | On `PATH` |
| Clipboard tool | `pbcopy` (macOS), `wl-copy`, or `xclip` |

## Installation

### LazyVim (recommended)

Create `~/.config/nvim/lua/plugins/claude-feedback.lua`:

```lua
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
```

Then restart Neovim or run `:Lazy sync`.

### lazy.nvim (non-LazyVim)

```lua
{
  "d4rth-v4d3r/claude-feedback-vim",
  dependencies = { "folke/snacks.nvim" },
  config = function()
    require("claude-feedback").setup()
  end,
}
```

### Local development

```lua
{
  dir = "~/dev/claude-feedback-vim",
  name = "claude-feedback",
  dependencies = { "folke/snacks.nvim" },
  config = function()
    require("claude-feedback").setup()
  end,
}
```

## Quick start

1. Open a file in a git repo
2. Put cursor on a line → `<leader>cr` → type your review comment
3. Repeat for other lines/files
4. `<leader>cm` → **Open pending list** (or `:ClaudeFeedbackPending`)
   - Header shows changed files (unstaged + vs parent branch)
   - Press `y` in the picker to **copy to clipboard**
5. Paste into Claude Code or your terminal

### Default keymaps

| Key | Action |
|-----|--------|
| `<leader>cr` | Add comment at cursor |
| `<leader>ct` | Open thread float at cursor |
| `<leader>cm` | Quick menu |
| `<leader>cy` | Copy batch + changed files to clipboard |
| `]c` | Next review comment in buffer |
| `[c` | Previous review comment in buffer |

### Pending picker keys

| Key | Action |
|-----|--------|
| `Enter` | Open thread for selected comment |
| `y` | Copy to clipboard |
| `c` | Clear pending |
| `p` | Set parent/base branch |
| `a` | Add comment |

## Commands

| Command | Description |
|---------|-------------|
| `:ClaudeFeedbackAdd` | Add comment at cursor |
| `:ClaudeFeedbackThread` | Open thread float at cursor |
| `:ClaudeFeedbackNext` / `:ClaudeFeedbackPrev` | Jump between comments |
| `:ClaudeFeedbackMenu` | Quick menu |
| `:ClaudeFeedbackPending` | Pending picker |
| `:ClaudeFeedbackCopy` | Copy to clipboard |
| `:ClaudeFeedbackSetParent` | Choose base/parent branch |
| `:ClaudeFeedbackDiff` | Browse changed files and open in editor |
| `:ClaudeFeedbackResolved` | Resolved batch history |
| `:ClaudeFeedbackClear` | Clear pending comments |

## Copied output format

```text
Changed files (vs origin/development):
  - src/a.ts
  - src/d.ts

Please address the following code review comments. Run git diff (or git diff HEAD) to see the full context of any changes, especially for deleted lines.

  1. @/abs/path/src/a.ts L42: Comment body
     ↳ You: follow-up reply
```

The pending picker still shows **both** unstaged and branch file lists (per `changed_files.mode`). Clipboard copy defaults to **branch-only** file paths (`copy.changed_files_mode = "branch"`) so unstaged working-tree changes are not mixed into the review batch unless you opt in.

## Parent / base branch

Used for the "changed files vs parent" section and per-file diffs. Resolution order (plain git):

1. **Worktree override** — set via `:ClaudeFeedbackSetParent` (stored in plugin state)
2. **`git config branch.<name>.codeReviewParent`** — portable, shared with the VS Code extension
3. **`@{upstream}`** — when distinct from self/default
4. **`origin/HEAD`** — remote default branch
5. **Fallback** — `main`, then `master`

To set manually:

```
:ClaudeFeedbackSetParent
```

Pick a suggestion, type a custom ref, save to git config, or clear the worktree override.

## Configuration

```lua
require("claude-feedback").setup({
  signs = {
    enabled = true,
    text = "󰍡",
    show_preview = true,       -- virt_text after the line
    preview_max_len = 60,
  },
  float = {
    border = "rounded",
    max_width = 72,
    show_context = true,       -- ±2 lines in thread float
  },
  changed_files = {
    mode = "both",             -- "unstaged" | "branch" | "both"
  },
  parent_branch = {
    fallback = "main",         -- also tries "master" automatically
    config_key = "codeReviewParent",
  },
  copy = {
    include_changed_files = true,
    changed_files_mode = "branch", -- clipboard: "branch" | "unstaged" | "both"
    include_diff_instruction = true,
    include_absolute_paths = true,
  },
})
```

State is persisted to `stdpath("data")/claude-feedback/state.json`.

## Workflow example

```text
# Reviewing a feature branch against main

1. :ClaudeFeedbackSetParent          → pick "main"
2. <leader>cr on each concern line
3. :ClaudeFeedbackPending             → verify changed files + comments
4. <leader>cy                         → copy everything
5. Paste into Claude Code terminal
6. :ClaudeFeedbackResolved            → rollback if you sent too early
```

## Comparison with VS Code claude-feedback

| | VS Code extension | This plugin |
|---|-------------------|-------------|
| Primary send | Copy + auto-launch `claude` | **Copy only** |
| Changed files in output | No | **Yes (unstaged + branch)** |
| Parent branch | Graphite, Git Town, gh | **Plain git + manual picker** |
| Comment UI | Native comment threads | Signs + float + picker |

## Help

```vim
:help claude-feedback
```

## License

MIT
