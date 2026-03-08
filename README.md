<div align="center">
    <div>
        <div><h1>Neojj</h1></div>
    </div>
    <table>
        <tr>
            <td>
                <strong>A <a href="https://github.com/jj-vcs/jj">jj (Jujutsu)</a> interface for <a href="https://neovim.io">Neovim</a>, inspired by <a href="https://magit.vc">Magit</a>, forked from <a href="https://github.com/NeogitOrg/neogit">Neogit</a>.</strong>
            </td>
        </tr>
    </table>

  [![Lua](https://img.shields.io/badge/Lua-blue.svg?style=for-the-badge&logo=lua)](http://www.lua.org)
  [![Neovim](https://img.shields.io/badge/Neovim%200.10+-green.svg?style=for-the-badge&logo=neovim)](https://neovim.io)
  [![MIT](https://img.shields.io/badge/MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)
</div>

Neojj is a hard fork of [Neogit](https://github.com/NeogitOrg/neogit), adapted to work with [jj (Jujutsu VCS)](https://github.com/jj-vcs/jj) instead of git.

**Maintainer:** [Nicholas Zolton](https://github.com/nicholaszolton)

## Installation

Requires [jj (Jujutsu VCS)](https://github.com/jj-vcs/jj) to be installed and available on your `PATH`.

Here's an example spec for [Lazy](https://github.com/folke/lazy.nvim), but you're free to use whichever plugin manager suits you.

```lua
{
  "NicholasZolton/neojj",
  lazy = true,
  dependencies = {
    "nvim-lua/plenary.nvim",         -- required

    -- Only one of these is needed.
    "sindrets/diffview.nvim",        -- optional
    "esmuellert/codediff.nvim",      -- optional

    -- Only one of these is needed.
    "nvim-telescope/telescope.nvim", -- optional
    "ibhagwan/fzf-lua",              -- optional
    "nvim-mini/mini.pick",           -- optional
    "folke/snacks.nvim",             -- optional
  },
  cmd = "Neojj",
  keys = {
    { "<leader>gg", "<cmd>Neojj<cr>", desc = "Show Neojj UI" }
  }
}
```

## Usage

You can either open Neojj by using the `Neojj` command:

```vim
:Neojj             " Open the status buffer in a new tab
:Neojj cwd=<cwd>   " Use a different repository path
:Neojj cwd=%:p:h   " Uses the repository of the current file
:Neojj kind=<kind> " Open specified popup directly
:Neojj commit      " Open commit popup
:Neojj bookmark    " Open bookmark popup
:Neojj workspace   " Open workspace popup

" Map it to a key
nnoremap <leader>gg <cmd>Neojj<cr>
```

```lua
-- Or via lua api
vim.keymap.set("n", "<leader>gg", "<cmd>Neojj<cr>", { desc = "Open Neojj UI" })
```

Or using the lua api:

```lua
local neojj = require('neojj')

-- open using defaults
neojj.open()

-- open a specific popup
neojj.open({ "commit" })

-- open as a split
neojj.open({ kind = "split" })

-- open with different project
neojj.open({ cwd = "~" })

-- You can map this to a key
vim.keymap.set("n", "<leader>gg", neojj.open, { desc = "Open Neojj UI" })

-- Wrap in a function to pass additional arguments
vim.keymap.set(
    "n",
    "<leader>gg",
    function() neojj.open({ kind = "split" }) end,
    { desc = "Open Neojj UI" }
)
```

The `kind` option can be one of the following values:
- `tab`      (default)
- `replace`
- `split`
- `split_above`
- `split_above_all`
- `split_below`
- `split_below_all`
- `vsplit`
- `floating`
- `auto` (`vsplit` if window would have 80 cols, otherwise `split`)

## jj Concepts

If you are coming from git, here are some key differences in jj:

- **Change IDs vs Commit IDs**: Every change has a unique change ID (short, stable identifier) and a commit ID (hash). Change IDs persist across rewrites; commit IDs do not.
- **No staging area**: There is no index/staging concept. All modifications in your working copy are automatically part of the current change.
- **Bookmarks instead of branches**: jj uses "bookmarks" where git uses "branches". Bookmarks are pointers to commits, similar to git branches.
- **Operations log and undo**: Every jj operation is recorded. You can undo any operation with `jj undo`.
- **First-class conflicts**: Conflicts are recorded in commits rather than blocking operations. You can continue working and resolve them later.

## Configuration

You can configure Neojj by running the `require('neojj').setup {}` function, passing a table as the argument.

<details>
<summary>Default Config</summary>

```lua
local neojj = require("neojj")

neojj.setup {
  -- Path to jj binary. "auto" = auto-detect (resolves shims for performance).
  jj_binary = "auto",
  -- Hides the hints at the top of the status buffer
  disable_hint = false,
  -- Disables changing the buffer highlights based on where the cursor is.
  disable_context_highlighting = false,
  -- Disables signs for sections/items/hunks
  disable_signs = false,
  -- Changes what mode the Commit Editor starts in. `true` will leave nvim in normal mode, `false` will change nvim to
  -- insert mode, and `"auto"` will change nvim to insert mode IF the commit message is empty, otherwise leaving it in
  -- normal mode.
  disable_insert_on_commit = "auto",
  -- When enabled, will watch the `.jj/` directory for changes and refresh the status buffer in response to filesystem
  -- events.
  filewatcher = {
    enabled = true,
  },
  -- "ascii"   is the graph the jj CLI generates
  -- "unicode" is a unicode graph style
  graph_style = "ascii",
  -- Show relative date by default. When set, use `strftime` to display dates
  commit_date_format = nil,
  log_date_format = nil,
  -- Show message with spinning animation when a jj command is running.
  process_spinner = false,
  -- Allows a different telescope sorter. Defaults to 'fuzzy_with_index_bias'. The example below will use the native fzf
  -- sorter instead. By default, this function returns `nil`.
  telescope_sorter = function()
    return require("telescope").extensions.fzf.native_fzf_sorter()
  end,
  -- Persist the values of switches/options within and across sessions
  remember_settings = true,
  -- Scope persisted settings on a per-project basis
  use_per_project_settings = true,
  -- Table of settings to never persist. Uses format "Filetype--cli-value"
  ignored_settings = {},
  -- Configure highlight group features
  highlight = {
    italic = true,
    bold = true,
    underline = true
  },
  -- Set to false if you want to be responsible for creating _ALL_ keymappings
  use_default_keymaps = true,
  -- Change the default way of opening Neojj
  kind = "tab",
  -- Floating window style
  floating = {
    relative = "editor",
    width = 0.8,
    height = 0.7,
    style = "minimal",
    border = "rounded",
  },
  -- Disable line numbers
  disable_line_numbers = true,
  -- Disable relative line numbers
  disable_relative_line_numbers = true,
  -- The time after which an output console is shown for slow running commands
  console_timeout = 2000,
  -- Automatically show console if a command takes more than console_timeout milliseconds
  auto_show_console = true,
  -- If `auto_show_console` is enabled, specify "output" (default) to show
  -- the console always, or "error" to auto-show the console only on error
  auto_show_console_on = "output",
  -- Automatically close the console if the process exits with a 0 (success) status
  auto_close_console = true,
  notification_icon = "󰊢",
  -- Shell command to run in new workspace directory after creation. {path} is replaced with the workspace path.
  workspace_open_command = nil,
  -- Shell command to initialize a new workspace before opening. {path} is replaced with the workspace path.
  workspace_initialize_command = nil,
  -- Base directory for quick-add worktrees (used by workspace popup's quick add action)
  workspace_worktrees_directory = "~/.worktrees",
  status = {
    show_head_commit_hash = true,
    recent_commit_count = 10,
    HEAD_padding = 10,
    HEAD_folded = false,
    mode_padding = 3,
    mode_text = {
      M = "modified",
      N = "new file",
      A = "added",
      D = "deleted",
      C = "copied",
      R = "renamed",
      ["?"] = "",
    },
  },
  commit_editor = {
    kind = "tab",
    show_diff = true,
    diff_split_kind = "split",
    spell_check = true,
  },
  commit_select_view = {
    kind = "tab",
  },
  commit_view = {
    kind = "vsplit",
    verify_commit = vim.fn.executable("gpg") == 1,
  },
  log_view = {
    kind = "tab",
  },
  reflog_view = {
    kind = "tab",
  },
  preview_buffer = {
    kind = "floating_console",
  },
  popup = {
    kind = "split",
  },
  signs = {
    -- { CLOSED, OPENED }
    hunk = { "", "" },
    item = { ">", "v" },
    section = { ">", "v" },
  },
  -- Each Integration is auto-detected through plugin presence, however, it can be disabled by setting to `false`
  integrations = {
    -- If enabled, use telescope for menu selection rather than vim.ui.select.
    -- Allows multi-select and some things that vim.ui.select doesn't.
    telescope = nil,
    -- Neojj only provides inline diffs. If you want a more traditional way to look at diffs, you can use `diffview`.
    -- The diffview integration enables the diff popup.
    --
    -- Requires you to have `sindrets/diffview.nvim` installed.
    diffview = nil,

    -- Alternative diff viewer integration.
    -- Requires you to have `esmuellert/codediff.nvim` installed.
    codediff = nil,

    -- If enabled, uses fzf-lua for menu selection. If the telescope integration
    -- is also selected then telescope is used instead
    -- Requires you to have `ibhagwan/fzf-lua` installed.
    fzf_lua = nil,

    -- If enabled, uses mini.pick for menu selection. If the telescope integration
    -- is also selected then telescope is used instead
    -- Requires you to have `echasnovski/mini.pick` installed.
    mini_pick = nil,

    -- If enabled, uses snacks.picker for menu selection. If the telescope integration
    -- is also selected then telescope is used instead
    -- Requires you to have `folke/snacks.nvim` installed.
    snacks = nil,
  },
  -- Which diff viewer to use. nil = auto-detect (tries diffview first, then codediff).
  -- Can be "diffview" or "codediff".
  diff_viewer = nil,
  sections = {
    files = {
      folded = false,
      hidden = false,
    },
    conflicts = {
      folded = false,
      hidden = false,
    },
    untracked = {
      folded = false,
      hidden = false,
    },
    bookmarks = {
      folded = true,
      hidden = false,
      show_deleted = true,
      show_remote = true,
    },
    recent = {
      folded = true,
      hidden = false,
    },
  },
  mappings = {
    commit_editor = {
      ["q"] = "Close",
      ["<c-c><c-c>"] = "Submit",
      ["<c-c><c-k>"] = "Abort",
      ["<m-p>"] = "PrevMessage",
      ["<m-n>"] = "NextMessage",
      ["<m-r>"] = "ResetMessage",
    },
    commit_editor_I = {
      ["<c-c><c-c>"] = "Submit",
      ["<c-c><c-k>"] = "Abort",
    },
    finder = {
      ["<cr>"] = "Select",
      ["<c-c>"] = "Close",
      ["<esc>"] = "Close",
      ["<c-n>"] = "Next",
      ["<c-p>"] = "Previous",
      ["<down>"] = "Next",
      ["<up>"] = "Previous",
      ["<tab>"] = "InsertCompletion",
      ["<c-y>"] = "CopySelection",
      ["<space>"] = "MultiselectToggleNext",
      ["<s-space>"] = "MultiselectTogglePrevious",
      ["<c-j>"] = "NOP",
      ["<ScrollWheelDown>"] = "ScrollWheelDown",
      ["<ScrollWheelUp>"] = "ScrollWheelUp",
      ["<ScrollWheelLeft>"] = "NOP",
      ["<ScrollWheelRight>"] = "NOP",
      ["<LeftMouse>"] = "MouseClick",
      ["<2-LeftMouse>"] = "NOP",
    },
    -- Setting any of these to `false` will disable the mapping.
    popup = {
      ["?"] = "HelpPopup",
      ["b"] = "BookmarkPopup",
      ["c"] = "CommitPopup",
      ["d"] = "DiffPopup",
      ["f"] = "FetchPopup",
      ["l"] = "LogPopup",
      ["M"] = "RemotePopup",
      ["O"] = "OperationsPopup",
      ["P"] = "PushPopup",
      ["r"] = "RebasePopup",
      ["R"] = "ResolvePopup",
      ["s"] = "SplitPopup",
      ["S"] = "SquashPopup",
      ["u"] = "UndoPopup",
      ["W"] = "WorkspacePopup",
      ["y"] = "YankPopup",
    },
    status = {
      ["j"] = "MoveDown",
      ["k"] = "MoveUp",
      ["o"] = "OpenTree",
      ["q"] = "Close",
      ["I"] = "InitRepo",
      ["1"] = "Depth1",
      ["2"] = "Depth2",
      ["3"] = "Depth3",
      ["4"] = "Depth4",
      ["Q"] = "Command",
      ["<tab>"] = "Toggle",
      ["za"] = "Toggle",
      ["zo"] = "OpenFold",
      ["zc"] = "CloseFold",
      ["zC"] = "Depth1",
      ["zO"] = "Depth4",
      ["x"] = "Discard",
      ["K"] = "Untrack",
      ["R"] = "Rename",
      ["y"] = "ShowRefs",
      ["$"] = "CommandHistory",
      ["Y"] = "YankSelected",
      ["gp"] = "GoToParentRepo",
      ["<c-r>"] = "RefreshBuffer",
      ["<cr>"] = "GoToFile",
      ["<s-cr>"] = "PeekFile",
      ["<c-v>"] = "VSplitOpen",
      ["<c-x>"] = "SplitOpen",
      ["<c-t>"] = "TabOpen",
      ["{"] = "GoToPreviousHunkHeader",
      ["}"] = "GoToNextHunkHeader",
      ["[c"] = "OpenOrScrollUp",
      ["]c"] = "OpenOrScrollDown",
      ["<c-k>"] = "PeekUp",
      ["<c-j>"] = "PeekDown",
      ["<c-n>"] = "NextSection",
      ["<c-p>"] = "PreviousSection",
    },
  },
}
```
</details>

## Popups

The following popup menus are available from the status buffer (press `?` for the help popup to see all keybindings):

| Key | Popup | Description |
|-----|-------|-------------|
| `?` | **Help** | Show available keybindings |
| `b` | **Bookmark** | Create, move, delete, forget, rename, track/untrack bookmarks |
| `c` | **Commit** | Commit, new change, describe, edit, abandon, duplicate, revert. Supports bookmark-advancing variants. |
| `d` | **Diff** | View diffs (working copy, range, specific change, diffedit) |
| `f` | **Fetch** | Fetch from remotes |
| `l` | **Log** | View log with revset support |
| `M` | **Remote** | Add, remove, rename remotes |
| `O` | **Operations** | Browse and restore jj operations |
| `P` | **Push** | Push bookmarks to remotes |
| `r` | **Rebase** | Rebase changes (single, range, onto revision) |
| `R` | **Resolve** | Conflict resolution |
| `s` | **Split** | Split the current change |
| `S` | **Squash** | Squash changes into parent |
| `u` | **Undo** | Undo/redo jj operations |
| `W` | **Workspace** | Add, delete, forget, rename, list workspaces. Quick-add to worktrees directory. |
| `y` | **Yank** | Copy change/commit IDs |

Many popups will use whatever is currently under the cursor or selected as input for an action. For example, to rebase a range of changes from the log view, a linewise visual selection can be made, and the rebase action will apply to that selection.

## Status Buffer

The status buffer shows:

- **Change / Parent** headers with change ID, commit ID, bookmarks (highlighted), and description
- **Conflicts** section (if any unresolved conflicts exist)
- **Modified files** with inline diff support (toggle with `<tab>`)
- **Recent Changes** showing ancestor commits
- **Bookmarks** section with local and remote bookmarks (unpushed bookmarks marked with `*`)

## Workspace Support

Neojj includes full support for jj workspaces via the `W` popup:

- **Add** (`a`) / **Add at revision** (`A`) — create a new workspace at a chosen path (defaults to parent of repo root)
- **Quick add** (`q`) / **Quick add at revision** (`Q`) — instantly create a workspace with a random name under a configurable worktrees directory (default `~/.worktrees`)
- **Forget** (`f`) — stop tracking a workspace (files stay on disk)
- **Delete** (`d`) — forget and remove the workspace directory
- **Rename** (`r`) — rename the current workspace
- **List** (`l`) — list all workspaces with paths
- **Update stale** (`u`) — recover a stale workspace

Configure hooks to automatically open new workspaces:

```lua
neojj.setup {
  -- Open a new tmux window in the workspace directory
  workspace_open_command = "tmux new-window -c {path}",
  -- Run a command in the workspace before opening (e.g., install deps)
  workspace_initialize_command = nil,
  -- Base directory for quick-add worktrees
  workspace_worktrees_directory = "~/.worktrees",
}
```

## Highlight Groups

See the built-in documentation for a comprehensive list of highlight groups. If your theme doesn't style a particular group, we'll try our best to do a nice job.


## Events

Neojj emits the following events:

| Event                       | Description                        | Event Data                                         |
|-----------------------------|------------------------------------|----------------------------------------------------|
| `NeojjStatusRefreshed`     | Status has been reloaded           | `{}`                                               |
| `NeojjCommitComplete`     | Commit has been created            | `{}`                                               |
| `NeojjDescribeComplete`   | Description has been updated       | `{}`                                               |
| `NeojjNewChangeComplete`  | New change has been created        | `{}`                                               |
| `NeojjSquashComplete`     | Squash has completed               | `{}`                                               |
| `NeojjPushComplete`       | Push has completed                 | `{}`                                               |
| `NeojjFetchComplete`      | Fetch has completed                | `{}`                                               |
| `NeojjBookmarkCreate`     | Bookmark was created               | `{ bookmark_name: string }`                        |
| `NeojjBookmarkDelete`     | Bookmark was deleted               | `{ bookmark_name: string }`                        |
| `NeojjRebaseComplete`     | A rebase finished                  | `{ commit: string, status: "ok"\|"conflict" }`     |
| `NeojjAbandonComplete`    | A change was abandoned             | `{ change_id: string }`                            |

## Versioning

Neojj follows semantic versioning.

## Acknowledgements

Neojj is a hard fork of [Neogit](https://github.com/NeogitOrg/neogit). Thanks to the Neogit contributors for building the foundation this project is based on. This would not be possible without their work, and I personally use Neogit religiously for all things git.

