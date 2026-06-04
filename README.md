# Claude Feedback for Neovim / LazyVim

A Neovim plugin inspired by [claude-feedback](https://github.com/d4rth-v4d3r/claude-feedback) (VS Code). Collect line-level code review comments in the editor and **paste into Claude Code, Cursor, or anywhere else**.

Use [diffview.nvim](https://github.com/sindrets/diffview.nvim) (or your preferred diff tool) for side-by-side review — this plugin focuses on comments and clipboard output only.

## Why this plugin?

The VS Code extension auto-launches Claude in a terminal. This Neovim port is built for a simpler workflow:

1. Review code with your own diff tool (e.g. Diffview)
2. Add comments on specific lines
3. Copy a formatted batch of comments → paste wherever you want

No Graphite, Git Town, or `gh` — plain git only.

## Features

- **Inline markers** — sign column icon + optional virt_text preview on commented lines
- **Thread float** — reply, edit, delete at the cursor (`<leader>rt`)
- **Jump between comments** — `]r` / `[r` in the current buffer
- **Pending picker** — all pending comments + copy/clear actions
- **Copy to clipboard** — primary send action; copies comments only (optional changed-files list)
- **Parent branch picker** — manual base branch per worktree, or save to git config
- **Re-anchor on save** — comments follow line edits when possible
- **Resolved batches** — view history, re-copy, or **rollback** to pending

## Requirements

| Requirement | Notes |
|-------------|-------|
| Neovim **0.10+** | Uses `vim.system` |
| [snacks.nvim](https://github.com/folke/snacks.nvim) | Input, picker, float windows |
| `git` | On `PATH` (optional changed-files list in copy output) |
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

## Quick start

1. Review your branch with Diffview (or `:DiffviewOpen`)
2. Put cursor on a line → `<leader>ra` → type your review comment
3. Repeat for other lines/files
4. `<leader>ry` (or `:ClaudeFeedbackCopy`) → copy batch to clipboard
5. Paste into Claude Code or your terminal

### Default keymaps

Uses `<leader>r*` (review) to avoid LazyVim conflicts (`<leader>cm` = Mason, `<leader>cr` = LSP rename).

| Key | Action |
|-----|--------|
| `<leader>ra` | Add comment at cursor |
| `<leader>rt` | Open thread float (reply / edit / delete) |
| `<leader>rv` | Quick menu |
| `<leader>ry` | Copy batch + changed files to clipboard |
| `]r` | Next review comment in buffer |
| `[r` | Previous review comment in buffer |

### Thread float keys

| Key | Action |
|-----|--------|
| `r` | Reply |
| `e` | Edit main comment |
| `d` | Delete comment |
| `q` | Close |

### Pending picker keys

| Key | Action |
|-----|--------|
| `Enter` | Open thread for selected comment |
| `y` | Copy to clipboard |
| `c` | Clear pending |
| `p` | Set parent/base branch |
| `a` | Add comment |

### Resolved picker keys

| Key | Action |
|-----|--------|
| `Enter` | Re-copy batch text |
| `r` | Rollback batch to pending |

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
| `:ClaudeFeedbackResolved` | Resolved batch history |
| `:ClaudeFeedbackClear` | Clear pending comments |

## Copied output format

```text
Please address the following code review comments. Run git diff (or git diff HEAD) to see the full context of any changes, especially for deleted lines.

  1. @/abs/path/src/a.ts L42: Comment body
     ↳ You: follow-up reply
```

To include changed file paths in the clipboard output, set `copy.include_changed_files = true` (and optionally `copy.changed_files_mode = "branch"`).

## Parent / base branch

Used when `copy.include_changed_files = true` for the optional changed-files section. Resolution order (plain git):

1. **Worktree override** — set via `:ClaudeFeedbackSetParent` (stored in plugin state)
2. **`git config branch.<name>.codeReviewParent`** — portable, shared with the VS Code extension
3. **`@{upstream}`** — when distinct from self/default
4. **`origin/HEAD`** — remote default branch
5. **Fallback** — `main`, then `master`

## Configuration

```lua
require("claude-feedback").setup({
  signs = {
    enabled = true,
    text = "󰍡",
    show_preview = true,
    preview_max_len = 60,
  },
  float = {
    border = "rounded",
    max_width = 72,
    show_context = true,
  },
  changed_files = {
    mode = "both",             -- "unstaged" | "branch" | "both"
  },
  parent_branch = {
    fallback = "main",
    config_key = "codeReviewParent",
  },
  copy = {
    include_changed_files = false,
    changed_files_mode = "branch",
    include_diff_instruction = true,
    include_absolute_paths = true,
  },
})
```

State is persisted to `stdpath("data")/claude-feedback/state.json`.

## Workflow example

```text
1. :DiffviewOpen                         → review changes side-by-side
2. :ClaudeFeedbackSetParent              → pick base branch (once)
3. <leader>ra on each concern line
4. :ClaudeFeedbackPending                → verify comments
5. <leader>ry                            → copy comments
6. Paste into Claude Code
7. :ClaudeFeedbackResolved → r           → rollback if you copied too early
```

## Comparison with VS Code claude-feedback

| | VS Code extension | This plugin |
|---|-------------------|-------------|
| Primary send | Copy + auto-launch `claude` | **Copy only** |
| Changed files in output | No | **Optional** (off by default) |
| Diff UI | VS Code diff | **Use Diffview / your tool** |
| Parent branch | Graphite, Git Town, gh | **Plain git + manual picker** |
| Comment UI | Native comment threads | Signs + float + picker |

## Help

```vim
:help claude-feedback
```

## License

MIT
