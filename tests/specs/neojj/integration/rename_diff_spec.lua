local harness = require("tests.util.jj_harness")
local diff = require("neojj.lib.jj.diff")
local status = require("neojj.lib.jj.status")

local function run(root, ...)
  local cmd = { "jj", "--no-pager", "--color=never", "-R", root }
  vim.list_extend(cmd, { ... })
  local result = vim.system(cmd):wait()
  assert.are.equal(0, result.code, result.stderr)
  return vim.split(vim.trim(result.stdout), "\n", { plain = true })
end

for _, colocated in ipairs { false, true } do
  describe("rename diffs (colocated=" .. tostring(colocated) .. ")", function()
    local cwd
    before_each(function()
      cwd = vim.fn.getcwd()
    end)
    after_each(function()
      vim.api.nvim_set_current_dir(cwd)
    end)

    for _, modified in ipairs { false, true } do
      it("loads a renamed file " .. (modified and "with" or "without") .. " content changes", function()
        if not harness.jj_available() then
          pending("jj binary not available")
          return
        end
        local root = harness.prepare_repository { colocated = colocated }
        vim.fn.mkdir(root .. "/rules")
        local before = {
          "Name: old",
          "Priority: 22",
          "Statement: unchanged",
          "Action: Allow",
          "Label: unchanged",
          "Visibility: unchanged",
        }
        vim.fn.writefile(before, root .. "/rules/old.yaml")
        run(root, "new", "-m", "rename fixture")
        assert.are.equal(0, vim.fn.rename(root .. "/rules/old.yaml", root .. "/rules/new.yaml"))
        -- Snapshot the exact rename before editing, so jj records its source.
        run(root, "status")
        if modified then
          local after = vim.deepcopy(before)
          after[1], after[4] = "Name: new", "Action: Count"
          vim.fn.writefile(after, root .. "/rules/new.yaml")
        end
        vim.fn.writefile({ "unrelated edit" }, root .. "/a.txt")

        local items = status.parse_status_files(run(root, "status"), root)
        local item
        for _, candidate in ipairs(items) do
          if candidate.mode == "R" then
            item = candidate
          end
        end
        assert.is_not_nil(item, "fixture must contain a detected rename")
        diff.build(item)

        local raw = require("plenary.async").util.block_on(function()
          return diff.file_diff(item, "@")
        end)
        for _, parsed in ipairs { item.diff, diff.parse(raw) } do
          assert.are.equal("renamed", parsed.kind)
          assert.are.equal("rules/new.yaml", parsed.file)
          assert.are.equal(modified and 1 or 0, #parsed.hunks)
          if modified then
            assert.are.same({
              "-Name: old",
              "+Name: new",
              " Priority: 22",
              " Statement: unchanged",
              "-Action: Allow",
              "+Action: Count",
              " Label: unchanged",
              " Visibility: unchanged",
            }, parsed.hunks[1].lines)
          end
        end
      end)
    end
  end)
end
