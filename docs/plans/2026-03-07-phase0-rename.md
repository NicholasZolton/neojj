# Phase 0: Mechanical Rename (neogit → neojj) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rename all references from neogit/Neogit to neojj/NeoJJ across the entire codebase.

**Architecture:** Scripted find-and-replace using `sed` and `git mv`. Each task handles one category of renames. Verify plugin loads after all renames complete.

**Tech Stack:** Lua (Neovim plugin), bash (sed, git mv)

---

### Task 1: Rename directory structure

Move the main module directory and test directory.

**Step 1: Move lua/neogit/ → lua/neojj/**

```bash
git mv lua/neogit lua/neojj
```

**Step 2: Move lua/neogit.lua → lua/neojj.lua**

```bash
git mv lua/neogit.lua lua/neojj.lua
```

**Step 3: Move plugin/neogit.lua → plugin/neojj.lua**

```bash
git mv plugin/neogit.lua plugin/neojj.lua
```

**Step 4: Move doc/neogit.txt → doc/neojj.txt**

```bash
git mv doc/neogit.txt doc/neojj.txt
```

**Step 5: Move tests/specs/neogit/ → tests/specs/neojj/**

```bash
git mv tests/specs/neogit tests/specs/neojj
```

**Step 6: Commit**

```bash
git add -A && git commit -m "refactor: rename file/directory structure neogit → neojj"
```

---

### Task 2: Replace all require statements

708 occurrences across 152 files. All `require("neogit` → `require("neojj`.

**Step 1: Run sed replacement across all Lua files**

```bash
find lua/ plugin/ tests/ -name '*.lua' -exec sed -i '' 's/require("neogit/require("neojj/g' {} +
```

**Step 2: Verify no remaining references**

```bash
grep -r 'require("neogit' lua/ plugin/ tests/ | wc -l
```

Expected: 0

**Step 3: Commit**

```bash
git add -A && git commit -m "refactor: rename all require('neogit') → require('neojj')"
```

---

### Task 3: Rename user-facing commands

4 commands in plugin/neojj.lua (already moved).

**Step 1: Replace command names**

In `plugin/neojj.lua`, replace:
- `Neogit` → `NeoJJ` (command names)
- `neogit` → `neojj` (any remaining lowercase references)

```bash
sed -i '' 's/NeogitResetState/NeoJJResetState/g; s/NeogitLogCurrent/NeoJJLogCurrent/g; s/NeogitCommit/NeoJJCommit/g; s/:Neogit/:NeoJJ/g' plugin/neojj.lua
```

**Step 2: Also replace command references throughout codebase**

Other files reference these commands (docs, lua code, tests):

```bash
find lua/ tests/ doc/ -type f \( -name '*.lua' -o -name '*.txt' -o -name '*.md' \) -exec sed -i '' 's/NeogitResetState/NeoJJResetState/g; s/NeogitLogCurrent/NeoJJLogCurrent/g; s/NeogitCommit/NeoJJCommit/g' {} +
```

**Step 3: Replace the main :Neogit command references**

```bash
find lua/ tests/ doc/ -type f \( -name '*.lua' -o -name '*.txt' -o -name '*.md' \) -exec sed -i '' 's/:Neogit\b/:NeoJJ/g' {} +
```

**Step 4: Verify**

```bash
grep -rn 'NeogitResetState\|NeogitLogCurrent\|NeogitCommit' lua/ plugin/ tests/ doc/ | wc -l
```

Expected: 0

**Step 5: Commit**

```bash
git add -A && git commit -m "refactor: rename user-facing commands Neogit → NeoJJ"
```

---

### Task 4: Rename highlight groups

164 highlight groups in lib/hl.lua, referenced in 91 files (618 occurrences).

**Step 1: Replace all Neogit highlight prefixes**

```bash
find lua/ tests/ doc/ -type f \( -name '*.lua' -o -name '*.txt' \) -exec sed -i '' 's/Neogit\([A-Z]\)/NeoJJ\1/g' {} +
```

This pattern matches `Neogit` followed by an uppercase letter (all highlight groups like `NeogitDiffAdd`, `NeogitGraphRed`, etc.) and replaces with `NeoJJ`.

**Step 2: Verify highlight definitions renamed**

```bash
grep -c 'NeoJJ' lua/neojj/lib/hl.lua
```

Expected: 164+ (all highlight groups renamed)

```bash
grep -c 'Neogit[A-Z]' lua/neojj/lib/hl.lua
```

Expected: 0

**Step 3: Commit**

```bash
git add -A && git commit -m "refactor: rename highlight groups Neogit* → NeoJJ*"
```

---

### Task 5: Rename autocmd groups and buffer name schemes

**Step 1: Replace autocmd group names**

In `lua/neojj.lua` and `lua/neojj/lib/buffer.lua`:

```bash
find lua/ -name '*.lua' -exec sed -i '' 's/"Neogit"/"NeoJJ"/g; s/"Neogit-/"NeoJJ-/g' {} +
```

**Step 2: Replace buffer URL scheme**

```bash
find lua/ -name '*.lua' -exec sed -i '' 's/neogit:\/\//neojj:\/\//g' {} +
```

**Step 3: Verify**

```bash
grep -rn '"Neogit"' lua/ | wc -l
grep -rn 'neogit://' lua/ | wc -l
```

Expected: 0 for both

**Step 4: Commit**

```bash
git add -A && git commit -m "refactor: rename autocmd groups and buffer URL scheme"
```

---

### Task 6: Rename remaining string references

Catch-all for remaining lowercase `neogit` references in strings, comments, error messages, and identifiers.

**Step 1: Find remaining lowercase references**

```bash
grep -rn 'neogit' lua/ plugin/ tests/ --include='*.lua' | grep -v 'require("neojj' | head -50
```

Review output to understand what's left.

**Step 2: Replace remaining lowercase neogit → neojj in Lua files**

```bash
find lua/ plugin/ tests/ -name '*.lua' -exec sed -i '' 's/neogit/neojj/g' {} +
```

**Step 3: Replace remaining capitalized Neogit → NeoJJ (strings, comments)**

```bash
find lua/ plugin/ tests/ -name '*.lua' -exec sed -i '' 's/Neogit/NeoJJ/g' {} +
```

**Step 4: Verify no remaining references**

```bash
grep -rni 'neogit' lua/ plugin/ tests/ --include='*.lua' | wc -l
```

Expected: 0

**Step 5: Commit**

```bash
git add -A && git commit -m "refactor: rename all remaining neogit/Neogit references in Lua files"
```

---

### Task 7: Update documentation

**Step 1: Rename in doc/neojj.txt**

```bash
sed -i '' 's/neogit/neojj/g; s/Neogit/NeoJJ/g; s/NEOGIT/NEOJJ/g' doc/neojj.txt
```

**Step 2: Update README.md**

```bash
sed -i '' 's/neogit/neojj/g; s/Neogit/NeoJJ/g; s/NeogitOrg\/neogit/NeoJJ/g' README.md
```

**Step 3: Update CONTRIBUTING.md**

```bash
sed -i '' 's/neogit/neojj/g; s/Neogit/NeoJJ/g' CONTRIBUTING.md
```

**Step 4: Verify**

```bash
grep -rni 'neogit' doc/ README.md CONTRIBUTING.md | wc -l
```

Expected: 0 (or only in git URLs / historical references that are fine to keep)

**Step 5: Commit**

```bash
git add -A && git commit -m "refactor: rename neogit → neojj in documentation"
```

---

### Task 8: Update test infrastructure

**Step 1: Rename references in test utilities**

```bash
find tests/ -type f -name '*.lua' -exec sed -i '' 's/neogit/neojj/g; s/Neogit/NeoJJ/g' {} +
```

**Step 2: Update test Makefile/config if needed**

```bash
grep -rn 'neogit' Makefile tests/ --include='*.lua' --include='Makefile' | wc -l
```

Expected: 0

**Step 3: Commit**

```bash
git add -A && git commit -m "refactor: rename neogit → neojj in test files"
```

---

### Task 9: Final verification

**Step 1: Full codebase grep for any remaining references**

```bash
grep -rni 'neogit' lua/ plugin/ tests/ doc/ README.md CONTRIBUTING.md --include='*.lua' --include='*.txt' --include='*.md' | grep -v '.llm-docs' | grep -v 'docs/plans'
```

Expected: 0 results (plan files excluded)

**Step 2: Check no broken requires by loading the plugin**

Open Neovim and run:
```vim
:lua require("neojj")
```

Or verify with a headless check:
```bash
nvim --headless -c "lua require('neojj')" -c "echo 'OK'" -c "qa!" 2>&1
```

**Step 3: Update the plan checklist**

Mark all Phase 0 items as complete in `docs/plans/2026-03-07-neojj-port-plan.md`.

**Step 4: Final commit if any fixups needed**

```bash
git add -A && git commit -m "refactor: phase 0 complete — neogit fully renamed to neojj"
```
