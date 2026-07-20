local harness = require("tests.util.jj_harness")
local Repo = require("neojj.lib.jj.repository").Repo
local jj = require("neojj.lib.jj")

local function skip_if_no_jj()
  if not harness.jj_available() then
    pending("jj binary not available; skipping integration test")
    return true
  end
  return false
end

local function find_file(items, name)
  for _, item in ipairs(items) do
    if item.name == name then
      return item
    end
  end
end

local modes = {
  { name = "colocated", colocated = true },
  { name = "non-colocated", colocated = false },
}

for _, mode in ipairs(modes) do
  describe("file tracking integration — " .. mode.name, function()
    local repo
    local working_dir

    before_each(function()
      if skip_if_no_jj() then
        return
      end
      working_dir = harness.prepare_repository { colocated = mode.colocated, auto_track = false }
      repo = Repo.new(working_dir)
      repo:refresh()
    end)

    it("shows untracked files when auto_track is disabled", function()
      if skip_if_no_jj() then
        return
      end

      local untracked = find_file(repo.state.files.items, "untracked.txt")
      assert.is_not_nil(untracked)
      assert.are.equal("?", untracked.mode)
    end)

    it("tracks an untracked file with jj file track", function()
      if skip_if_no_jj() then
        return
      end

      local result = jj.cli.file_track.files("file:untracked.txt").call { await = true, ignore_error = true }
      assert.is_not_nil(result)
      assert.are.equal(0, result.code)

      repo:refresh()

      local tracked = find_file(repo.state.files.items, "untracked.txt")
      assert.is_not_nil(tracked)
      assert.are.equal("A", tracked.mode)
    end)

    it("untracks an ignored tracked file with jj file untrack", function()
      if skip_if_no_jj() then
        return
      end

      vim.fn.writefile({ "tracked then ignored" }, working_dir .. "/ignored.txt")

      local track_result = jj.cli.file_track.files("file:ignored.txt").call { await = true, ignore_error = true }
      assert.is_not_nil(track_result)
      assert.are.equal(0, track_result.code)

      vim.fn.writefile({ "ignored.txt" }, working_dir .. "/.gitignore")

      repo:refresh()

      local tracked = find_file(repo.state.files.items, "ignored.txt")
      assert.is_not_nil(tracked)
      assert.are.equal("A", tracked.mode)

      local result = jj.cli.file_untrack.files("file:ignored.txt").call { await = true, ignore_error = true }
      assert.is_not_nil(result)
      assert.are.equal(0, result.code)

      repo:refresh()

      assert.is_nil(find_file(repo.state.files.items, "ignored.txt"))
      assert.are.equal(1, vim.fn.filereadable(working_dir .. "/ignored.txt"))
    end)
  end)
end
