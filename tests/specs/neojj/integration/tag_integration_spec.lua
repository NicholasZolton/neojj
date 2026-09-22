-- Real local repositories exercise jj tag state and Git's tag push behavior.
-- Bare remotes stay in temporary directories; no test contacts a network service.
local harness = require("tests.util.jj_harness")
local util = require("tests.util.util")
local Repo = require("neojj.lib.jj.repository").Repo
local jj_backend = require("neojj.integrations.jj_backend")
local tag = require("neojj.lib.jj.tag")

local function skip_if_tools_missing()
  if not harness.jj_available() or vim.fn.executable("git") ~= 1 then
    pending("jj and git binaries required; skipping tag integration test")
    return true
  end
  return false
end

---@param cmd string[]
---@param opts? table
---@return vim.SystemCompleted
local function run(cmd, opts)
  opts = vim.tbl_extend("force", { text = true }, opts or {})
  return vim.system(cmd, opts):wait()
end

---@param result vim.SystemCompleted
---@param context string
local function assert_success(result, context)
  assert.are.equal(
    0,
    result.code,
    context .. "\nstdout: " .. (result.stdout or "") .. "\nstderr: " .. (result.stderr or "")
  )
end

---@return string
local function bare_remote()
  local remote = util.create_temp_dir("jj-tag-remote")
  assert_success(run { "git", "init", "--bare", remote }, "initialize bare remote")
  return remote
end

---@param workspace string
---@param name string
---@param revision string
local function set_tag(workspace, name, revision)
  assert_success(
    run { "jj", "--repository", workspace, "tag", "set", "--revision", revision, name },
    "set tag " .. name
  )
end

---@param workspace string
---@param name string
---@param revision string
local function move_tag(workspace, name, revision)
  assert_success(
    run { "jj", "--repository", workspace, "tag", "set", "--allow-move", "--revision", revision, name },
    "move tag " .. name
  )
end

---@param workspace string
---@param git_dir string
---@param remote string
---@param args string[]
---@return vim.SystemCompleted
local function push_tags(workspace, git_dir, remote, args)
  local cmd = { "git", "push" }
  if args[1] == "--tags" then
    table.insert(cmd, "--tags")
  end
  vim.list_extend(cmd, { "--", remote })
  if args[1] ~= "--tags" then
    vim.list_extend(cmd, args)
  end
  return run(cmd, { cwd = workspace, env = { GIT_DIR = git_dir } })
end

---@param git_dir string
---@param ref string
---@return string|nil
local function ref_oid(git_dir, ref)
  local result = run { "git", "--git-dir", git_dir, "rev-parse", "--verify", ref }
  if result.code ~= 0 then
    return nil
  end
  return vim.trim(result.stdout or "")
end

describe("jj tags", function()
  it("creates, moves, deletes, and lists local tags through tag library", function()
    if skip_if_tools_missing() then
      return
    end

    local workspace = harness.prepare_repository { colocated = false }
    local repo = Repo.instance()

    set_tag(workspace, "v1.0.0", "@-")

    repo:refresh()
    assert.are.same(
      { "v1.0.0" },
      vim.tbl_map(function(item)
        return item.name
      end, tag.list())
    )
    local initial_target = tag.list()[1].change_id

    move_tag(workspace, "v1.0.0", "@")

    repo:refresh()
    assert.are_not.equal(initial_target, tag.list()[1].change_id)

    assert_success(run { "jj", "--repository", workspace, "tag", "delete", "v1.0.0" }, "delete tag")

    repo:refresh()
    assert.are.same({}, tag.list())
  end)
end)

describe("Git tag fallback", function()
  it("pushes only selected tag to temporary bare remote", function()
    if skip_if_tools_missing() then
      return
    end

    local workspace = harness.prepare_repository { colocated = true, cd = false }
    local git_dir = assert(jj_backend.colocated_git_dir(workspace))
    local remote = bare_remote()
    set_tag(workspace, "v-selected", "@-")
    set_tag(workspace, "v-unselected", "@-")

    local ref = "refs/tags/v-selected"
    assert_success(push_tags(workspace, git_dir, remote, { ref .. ":" .. ref }), "push selected tag")

    assert.is_not_nil(ref_oid(remote, ref))
    assert.is_nil(ref_oid(remote, "refs/tags/v-unselected"))
  end)

  it("pushes all local tags to temporary bare remote", function()
    if skip_if_tools_missing() then
      return
    end

    local workspace = harness.prepare_repository { colocated = true, cd = false }
    local git_dir = assert(jj_backend.colocated_git_dir(workspace))
    local remote = bare_remote()
    set_tag(workspace, "v1.0.0", "@-")
    set_tag(workspace, "v2.0.0", "@-")

    assert_success(push_tags(workspace, git_dir, remote, { "--tags" }), "push all tags")

    assert.is_not_nil(ref_oid(remote, "refs/tags/v1.0.0"))
    assert.is_not_nil(ref_oid(remote, "refs/tags/v2.0.0"))
  end)

  it("rejects moving an already-pushed tag without force", function()
    if skip_if_tools_missing() then
      return
    end

    local workspace = harness.prepare_repository { colocated = true, cd = false }
    local git_dir = assert(jj_backend.colocated_git_dir(workspace))
    local remote = bare_remote()
    local ref = "refs/tags/v-moved"
    set_tag(workspace, "v-moved", "@-")
    assert_success(push_tags(workspace, git_dir, remote, { ref .. ":" .. ref }), "initial tag push")
    local remote_oid = assert(ref_oid(remote, ref))

    move_tag(workspace, "v-moved", "@")
    assert.are_not.equal(remote_oid, ref_oid(git_dir, ref))

    local result = push_tags(workspace, git_dir, remote, { ref .. ":" .. ref })
    assert.are_not.equal(0, result.code)
    assert.are.equal(remote_oid, ref_oid(remote, ref))
  end)

  it("rejects non-colocated workspace before a bare remote can receive tags", function()
    if skip_if_tools_missing() then
      return
    end

    local workspace = harness.prepare_repository { colocated = false, cd = false }
    local remote = bare_remote()
    set_tag(workspace, "v1.0.0", "@-")

    -- Popup action gates Git fallback on this shared resolver before spawning Git.
    assert.is_nil(jj_backend.colocated_git_dir(workspace))
    assert.is_nil(ref_oid(remote, "refs/tags/v1.0.0"))
  end)

  it("resolves primary Git directory from secondary colocated workspace", function()
    if skip_if_tools_missing() then
      return
    end

    local primary = harness.prepare_repository { colocated = true, cd = false }
    local secondary = harness.add_secondary_workspace(primary, "tag-push")
    local git_dir = assert(jj_backend.colocated_git_dir(secondary))
    local remote = bare_remote()
    set_tag(primary, "v-secondary", "@-")

    assert.are.equal(vim.fn.resolve(primary .. "/.git"), vim.fn.resolve(git_dir))
    local ref = "refs/tags/v-secondary"
    assert_success(
      push_tags(secondary, git_dir, remote, { ref .. ":" .. ref }),
      "push from secondary workspace"
    )
    assert.is_not_nil(ref_oid(remote, ref))
  end)
end)
