local jj_backend = require("neojj.integrations.jj_backend")
local harness = require("tests.util.jj_harness")

local function skip_if_no_jj()
  if not harness.jj_available() then
    pending("jj binary not available; skipping integration test")
    return true
  end
  return false
end

---Canonicalize a path for comparison (resolve symlinks, strip trailing slash).
---@param p string
---@return string
local function canon(p)
  return vim.fn.resolve(p):gsub("/+$", "")
end

describe("jj_backend.find_jj_workspace", function()
  it("returns nil for a non-jj directory", function()
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
    assert.is_nil(jj_backend.find_jj_workspace(tmp))
  end)

  it("returns nil for nil or empty input", function()
    assert.is_nil(jj_backend.find_jj_workspace(nil))
    assert.is_nil(jj_backend.find_jj_workspace(""))
  end)

  it("finds workspace from its root", function()
    if skip_if_no_jj() then
      return
    end
    local ws = harness.prepare_repository { cd = false }
    assert.are.equal(canon(ws), canon(jj_backend.find_jj_workspace(ws)))
  end)

  it("finds workspace from a nested subdirectory", function()
    if skip_if_no_jj() then
      return
    end
    local ws = harness.prepare_repository { cd = false }
    local nested = ws .. "/nested/deeper"
    vim.fn.mkdir(nested, "p")
    assert.are.equal(canon(ws), canon(jj_backend.find_jj_workspace(nested)))
  end)

  it("finds workspace from a file path inside the workspace", function()
    if skip_if_no_jj() then
      return
    end
    local ws = harness.prepare_repository { cd = false }
    assert.are.equal(canon(ws), canon(jj_backend.find_jj_workspace(ws .. "/a.txt")))
  end)
end)

describe("jj_backend.jj_backing_git_dir — non-colocated", function()
  it("resolves to the internal bare repo in `.jj/repo/store/git`", function()
    if skip_if_no_jj() then
      return
    end
    local ws = harness.prepare_repository { colocated = false, cd = false }
    local git_dir = jj_backend.jj_backing_git_dir(ws)
    assert.is_not_nil(git_dir)
    assert.are.equal(canon(ws .. "/.jj/repo/store/git"), canon(git_dir))
    assert.are.equal(1, vim.fn.isdirectory(git_dir))
  end)
end)

describe("jj_backend.jj_backing_git_dir — colocated", function()
  it("resolves to the sibling `.git` directory", function()
    if skip_if_no_jj() then
      return
    end
    local ws = harness.prepare_repository { colocated = true, cd = false }
    local git_dir = jj_backend.jj_backing_git_dir(ws)
    assert.is_not_nil(git_dir)
    assert.are.equal(canon(ws .. "/.git"), canon(git_dir))
    assert.are.equal(1, vim.fn.isdirectory(git_dir))
  end)
end)

describe("jj_backend.jj_backing_git_dir — secondary workspaces", function()
  it("follows the `.jj/repo` pointer file to a non-colocated primary", function()
    if skip_if_no_jj() then
      return
    end
    local primary = harness.prepare_repository { colocated = false, cd = false }
    local secondary = harness.add_secondary_workspace(primary, "secondary-nc")

    -- `.jj/repo` in a secondary workspace is a file, not a dir.
    assert.are.equal("file", vim.uv.fs_stat(secondary .. "/.jj/repo").type)

    local git_dir = jj_backend.jj_backing_git_dir(secondary)
    assert.is_not_nil(git_dir)
    assert.are.equal(canon(primary .. "/.jj/repo/store/git"), canon(git_dir))
  end)

  it("follows the `.jj/repo` pointer file to a colocated primary", function()
    if skip_if_no_jj() then
      return
    end
    local primary = harness.prepare_repository { colocated = true, cd = false }
    local secondary = harness.add_secondary_workspace(primary, "secondary-co")

    assert.are.equal("file", vim.uv.fs_stat(secondary .. "/.jj/repo").type)

    local git_dir = jj_backend.jj_backing_git_dir(secondary)
    assert.is_not_nil(git_dir)
    assert.are.equal(canon(primary .. "/.git"), canon(git_dir))
  end)
end)

describe("jj_backend.colocated_git_dir", function()
  it("rejects an external backing directory named .git", function()
    local root = vim.fn.tempname()
    local workspace = root .. "/workspace"
    local external_git = root .. "/external/.git"
    vim.fn.mkdir(workspace .. "/.jj/repo/store", "p")
    vim.fn.mkdir(external_git, "p")
    vim.fn.writefile({ external_git }, workspace .. "/.jj/repo/store/git_target")

    assert.are.equal(canon(external_git), canon(jj_backend.jj_backing_git_dir(workspace)))
    assert.is_nil(jj_backend.colocated_git_dir(workspace))
  end)

  it("rejects a non-colocated backing Git directory", function()
    if skip_if_no_jj() then
      return
    end
    local ws = harness.prepare_repository { colocated = false, cd = false }
    assert.is_nil(jj_backend.colocated_git_dir(ws))
  end)

  it("resolves shared Git directory from a secondary colocated workspace", function()
    if skip_if_no_jj() then
      return
    end
    local primary = harness.prepare_repository { colocated = true, cd = false }
    local secondary = harness.add_secondary_workspace(primary, "secondary-tag-push")
    assert.are.equal(canon(primary .. "/.git"), canon(jj_backend.colocated_git_dir(secondary)))
  end)
end)

describe("jj_backend.resolve_jj_repo_dir", function()
  it("returns nil when `.jj/repo` is absent", function()
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp .. "/.jj", "p")
    assert.is_nil(jj_backend.resolve_jj_repo_dir(tmp))
  end)
end)
