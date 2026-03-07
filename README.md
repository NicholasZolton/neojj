<div align="center">
    <div>
        <div><h1>NeoJJ</h1></div>
    </div>
    <table>
        <tr>
            <td>
                <strong>A <a href="https://github.com/jj-vcs/jj">jj (Jujutsu)</a> interface for <a href="https://neovim.io">Neovim</a>, inspired by <a href="https://magit.vc">Magit</a>.</strong>
            </td>
        </tr>
    </table>

  [![Lua](https://img.shields.io/badge/Lua-blue.svg?style=for-the-badge&logo=lua)](http://www.lua.org)
  [![Neovim](https://img.shields.io/badge/Neovim%200.10+-green.svg?style=for-the-badge&logo=neovim)](https://neovim.io)
  [![MIT](https://img.shields.io/badge/MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)
</div>

NeoJJ is a hard fork of [Neogit](https://github.com/NeogitOrg/neogit), adapted to work with [jj (Jujutsu VCS)](https://github.com/jj-vcs/jj) instead of git.

## Installation

Requires [jj (Jujutsu VCS)](https://github.com/jj-vcs/jj) to be installed and available on your `PATH`.

Here's an example spec for [Lazy](https://github.com/folke/lazy.nvim), but you're free to use whichever plugin manager suits you.

```lua
{
  "NeoJJ/neojj",
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
  cmd = "NeoJJ",
  keys = {
    { "<leader>gg", "<cmd>NeoJJ<cr>", desc = "Show NeoJJ UI" }
  }
}
```

## Usage

You can either open NeoJJ by using the `NeoJJ` command:

```vim
:NeoJJ             " Open the status buffer in a new tab
:NeoJJ cwd=<cwd>   " Use a different repository path
:NeoJJ cwd=%:p:h   " Uses the repository of the current file
:NeoJJ kind=<kind> " Open specified popup directly
:NeoJJ commit      " Open commit popup
:NeoJJ bookmark    " Open bookmark popup
:NeoJJ change      " Open change popup

" Map it to a key
nnoremap <leader>gg <cmd>NeoJJ<cr>
```

```lua
-- Or via lua api
vim.keymap.set("n", "<leader>gg", "<cmd>NeoJJ<cr>", { desc = "Open NeoJJ UI" })
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
vim.keymap.set("n", "<leader>gg", neojj.open, { desc = "Open NeoJJ UI" })

-- Wrap in a function to pass additional arguments
vim.keymap.set(
    "n",
    "<leader>gg",
    function() neojj.open({ kind = "split" }) end,
    { desc = "Open NeoJJ UI" }
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

You can configure NeoJJ by running the `require('neojj').setup {}` function, passing a table as the argument.

<details>
<summary>Default Config</summary>

```lua
local neojj = require("neojj")

neojj.setup {
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
    interval = 1000,
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
  -- NeoJJ refreshes its internal state after specific events, which can be expensive depending on the repository size.
  -- Disabling `auto_refresh` will make it so you have to manually refresh the status after you open it.
  auto_refresh = true,
  -- Change the default way of opening NeoJJ
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
  -- Automatically close the console if the process exits with a 0 (success) status
  auto_close_console = true,
  notification_icon = "󰊢",
  status = {
    recent_commit_count = 10,
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
    -- NeoJJ only provides inline diffs. If you want a more traditional way to look at diffs, you can use `diffview`.
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
      ["C"] = "ChangePopup",
      ["d"] = "DiffPopup",
      ["f"] = "FetchPopup",
      ["l"] = "LogPopup",
      ["m"] = "MarginPopup",
      ["M"] = "RemotePopup",
      ["P"] = "PushPopup",
      ["r"] = "RebasePopup",
      ["R"] = "ResolvePopup",
      ["s"] = "SquashPopup",
      ["S"] = "SplitPopup",
      ["y"] = "YankPopup",
    },
    status = {
      ["j"] = "MoveDown",
      ["k"] = "MoveUp",
      ["o"] = "OpenTree",
      ["q"] = "Close",
      ["1"] = "Depth1",
      ["2"] = "Depth2",
      ["3"] = "Depth3",
      ["4"] = "Depth4",
      ["Q"] = "Command",
      ["<tab>"] = "Toggle",
      ["za"] = "Toggle",
      ["zo"] = "OpenFold",
      ["x"] = "Discard",
      ["K"] = "Untrack",
      ["$"] = "CommandHistory",
      ["Y"] = "YankSelected",
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

The following popup menus are available from all buffers:

- **Bookmark** - create, move, delete, forget, track bookmarks
- **Change** - create new change, merge
- **Commit** - commit, describe
- **Diff** - view diffs
- **Fetch** - fetch from remotes
- **Help** - show available keybindings
- **Log** - view log with revset support
- **Margin** - toggle margin display
- **Push** - push to remotes
- **Rebase** - rebase changes
- **Remote** - manage remotes
- **Resolve** - conflict resolution
- **Split** - split the current change
- **Squash** - squash changes into parent
- **Yank** - copy change/commit IDs

Many popups will use whatever is currently under the cursor or selected as input for an action. For example, to rebase a range of changes from the log view, a linewise visual selection can be made, and the rebase action will apply to that selection.

## Highlight Groups

See the built-in documentation for a comprehensive list of highlight groups. If your theme doesn't style a particular group, we'll try our best to do a nice job.


## Events

NeoJJ emits the following events:

| Event                       | Description                        | Event Data                                         |
|-----------------------------|------------------------------------|----------------------------------------------------|
| `NeoJJStatusRefreshed`     | Status has been reloaded           | `{}`                                               |
| `NeoJJCommitComplete`     | Commit has been created            | `{}`                                               |
| `NeoJJDescribeComplete`   | Description has been updated       | `{}`                                               |
| `NeoJJNewChangeComplete`  | New change has been created        | `{}`                                               |
| `NeoJJSquashComplete`     | Squash has completed               | `{}`                                               |
| `NeoJJPushComplete`       | Push has completed                 | `{}`                                               |
| `NeoJJFetchComplete`      | Fetch has completed                | `{}`                                               |
| `NeoJJBookmarkCreate`     | Bookmark was created               | `{ bookmark_name: string }`                        |
| `NeoJJBookmarkDelete`     | Bookmark was deleted               | `{ bookmark_name: string }`                        |
| `NeoJJRebaseComplete`     | A rebase finished                  | `{ commit: string, status: "ok"\|"conflict" }`     |
| `NeoJJAbandonComplete`    | A change was abandoned             | `{ change_id: string }`                            |

## Versioning

NeoJJ follows semantic versioning.

## Compatibility

The `master` branch will always be compatible with the latest **stable** release of Neovim, and usually with the latest **nightly** build as well.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for more details.

## Acknowledgements

NeoJJ is a hard fork of [Neogit](https://github.com/NeogitOrg/neogit). Thanks to the Neogit contributors for building the foundation this project is based on.
