# File Status Highlights Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Color each status-file mode label with NeoJJ's existing Neogit-derived highlight group, including Neogit's readable deleted-file red, while leaving filenames unchanged.

**Architecture:** Keep file-state presentation inside the existing status UI module. A local mode-to-highlight table selects the existing `NeojjChange*` group, and the renderer falls back to `NeojjFileMode` for unknown modes. Derive the red palette from `ErrorMsg`, matching current Neogit and avoiding colorschemes that reverse the `Error` foreground and background.

**Tech Stack:** Lua, Neovim UI components, Plenary/Busted tests, Stylua

## Global Constraints

- Apply the state highlight only to the configured mode label.
- Leave the filename without an explicit highlight.
- Reuse existing `NeojjChange*` groups.
- Derive red from `ErrorMsg`, matching current Neogit.
- Keep bookmark styling out of scope.
- Do not create a commit unless the user requests one.

---

### Task 1: Render File-State Highlights

**Files:**
- Create: `tests/specs/neojj/buffers/status/ui_spec.lua`
- Modify: `lua/neojj/buffers/status/ui.lua:201-303`

**Interfaces:**
- Consumes: `item.mode: string`, `config.status.mode_text: table<string, string>`, and the existing `Ui.text.highlight(group)` component builder.
- Produces: status-label text components whose `options.highlight` is the matching `NeojjChange*` group; unknown modes use `NeojjFileMode`.

- [ ] **Step 1: Write the failing status-renderer spec**

Create `tests/specs/neojj/buffers/status/ui_spec.lua`:

```lua
local status_ui = require("neojj.buffers.status.ui")
local config = require("neojj.config")

local function find_file_items(component, result)
  result = result or {}
  if component.options and component.options.kind == "file" then
    table.insert(result, component)
  end
  for _, child in ipairs(component.children or {}) do
    find_file_items(child, result)
  end
  return result
end

describe("status file highlights", function()
  it("colors mode labels by file state without coloring filenames", function()
    local values = config.get_default_values()
    values.disable_hint = true

    local state = {
      worktree_root = "/workspace",
      head = {
        change_id = "abcdefgh",
        commit_id = "12345678",
        description = "working copy",
        bookmarks = {},
        empty = false,
        conflict = false,
      },
      parent = {
        change_id = "ijklmnop",
        commit_id = "87654321",
        description = "parent",
        bookmarks = {},
      },
      files = {
        items = {
          { name = "modified.lua", mode = "M" },
          { name = "added.lua", mode = "A" },
          { name = "deleted.lua", mode = "D" },
          { name = "unknown.lua", mode = "X" },
        },
      },
      conflicts = { items = {} },
      recent = { items = {} },
      bookmarks = { items = {} },
    }

    local layout = status_ui.Status(state, values)
    local items = find_file_items(layout[1])
    local expected = {
      M = "NeojjChangeModified",
      A = "NeojjChangeAdded",
      D = "NeojjChangeDeleted",
      X = "NeojjFileMode",
    }

    assert.are.equal(4, #items)
    for _, item_component in ipairs(items) do
      local row = item_component.children[1]
      local mode_label = row.children[1]
      local filename = row.children[2]
      local mode = item_component.options.item.mode

      assert.are.equal(expected[mode], mode_label.options.highlight)
      assert.is_nil(filename.options.highlight)
    end
  end)
end)
```

- [ ] **Step 2: Run the focused spec and verify RED**

Run:

```bash
TEST_FILES=tests/specs/neojj/buffers/status/ui_spec.lua make test
```

Expected: FAIL because the known mode labels currently have `NeojjFileMode` instead of `NeojjChangeModified`, `NeojjChangeAdded`, or `NeojjChangeDeleted`.

- [ ] **Step 3: Add the mode-to-highlight mapping**

In `lua/neojj/buffers/status/ui.lua`, define this table near `SectionItemFile`:

```lua
local file_mode_highlights = {
  M = "NeojjChangeModified",
  A = "NeojjChangeAdded",
  N = "NeojjChangeNewFile",
  D = "NeojjChangeDeleted",
  R = "NeojjChangeRenamed",
  C = "NeojjChangeCopied",
  U = "NeojjChangeUpdated",
  T = "NeojjChangeUpdated",
  DD = "NeojjChangeUnmerged",
  AU = "NeojjChangeUnmerged",
  UD = "NeojjChangeUnmerged",
  UA = "NeojjChangeUnmerged",
  DU = "NeojjChangeUnmerged",
  AA = "NeojjChangeUnmerged",
  UU = "NeojjChangeUnmerged",
}
```

Replace the current fixed group in `SectionItemFile`:

```lua
local highlight = file_mode_highlights[item.mode] or "NeojjFileMode"
```

Keep the existing component structure so `text.highlight(highlight)(mode_text)` receives the group and `text(name)` remains unhighlighted.

- [ ] **Step 4: Run the focused spec and verify GREEN**

Run:

```bash
TEST_FILES=tests/specs/neojj/buffers/status/ui_spec.lua make test
```

Expected: PASS with one successful spec.

- [ ] **Step 5: Format and run project verification**

Run:

```bash
stylua --check lua/neojj/buffers/status/ui.lua tests/specs/neojj/buffers/status/ui_spec.lua
make test
make lint
make typecheck
git diff --check
```

Expected: every command exits with status 0. Review `git diff` and confirm the status-label changes remain scoped to the status UI module and its focused spec.

---

### Task 2: Match Neogit's Deleted-File Red

**Files:**
- Create: `tests/specs/neojj/lib/hl_spec.lua`
- Modify: `lua/neojj/lib/hl.lua:92`

**Interfaces:**
- Consumes: the active colorscheme's `ErrorMsg` foreground.
- Produces: the red palette used by `NeojjChangeDeleted` and other red highlight groups.

- [ ] **Step 1: Write the failing palette spec**

```lua
local Color = require("neojj.lib.color").Color
local highlight = require("neojj.lib.hl")

describe("highlight palette", function()
  it("derives deleted-file red from ErrorMsg like Neogit", function()
    vim.api.nvim_set_hl(0, "Error", { fg = "#192330" })
    vim.api.nvim_set_hl(0, "ErrorMsg", { fg = "#e26886" })
    vim.api.nvim_set_hl(0, "NeojjChangeDeleted", {})

    highlight.setup { highlight = {} }

    local deleted = vim.api.nvim_get_hl(0, { name = "NeojjChangeDeleted", link = false })
    local expected = Color.from_hex("#e26886"):shade(-0.18):to_css()

    assert.are.equal(expected, string.format("#%06x", deleted.fg))
  end)
end)
```

- [ ] **Step 2: Run the focused spec and verify RED**

Run `TEST_FILES=tests/specs/neojj/lib/hl_spec.lua make test`.

Expected: FAIL with `#141d27` received instead of Neogit's `#b9556e` when `Error` carries the colorscheme background.

- [ ] **Step 3: Use Neogit's palette source**

In `lua/neojj/lib/hl.lua`, change the red fallback source:

```lua
local red = Color.from_hex(config.highlight.red or get_fg("ErrorMsg") or "#E06C75")
```

- [ ] **Step 4: Verify the palette and project**

Run:

```bash
TEST_FILES=tests/specs/neojj/lib/hl_spec.lua make test
stylua --check lua/neojj/lib/hl.lua tests/specs/neojj/lib/hl_spec.lua
make test
make lint
make typecheck
git diff --check
```

Expected: every command exits with status 0, and a Neovim runtime query reports `NeojjChangeDeleted=#b9556e` under the reproduced Catppuccin palette.
