-- Path resolution for jj's git backing store.
--
-- Layout reference:
--   <workspace>/.jj/repo                 -- dir in primary workspace;
--                                           file in secondary workspace
--                                           (contents: path relative to .jj/)
--   <repo>/store/git_target              -- file whose contents are a path
--                                           relative to <repo>/store/ pointing
--                                           to the git backing dir
--
-- Colocated workspaces point `git_target` at the sibling `.git` directory.
-- Non-colocated workspaces keep a bare git repo inside `.jj/repo/store/git`.

local M = {}

local JJ_DIR = ".jj"
local REPO_NAME = "repo"
local STORE_NAME = "store"
local GIT_TARGET_FILE = "git_target"
local INTERNAL_GIT_NAME = "git"

---@param path string|nil
---@return string|nil workspace_root Absolute path to the jj workspace root, or nil if none found
function M.find_jj_workspace(path)
  if not path or path == "" then
    return nil
  end
  local p = vim.fn.fnamemodify(path, ":p")
  if vim.fn.isdirectory(p) == 0 then
    p = vim.fn.fnamemodify(p, ":h")
  end
  while p and p ~= "" and p ~= "/" do
    if vim.fn.isdirectory(p .. "/" .. JJ_DIR) == 1 then
      return p
    end
    local parent = vim.fn.fnamemodify(p, ":h")
    if parent == p then
      break
    end
    p = parent
  end
  return nil
end

---@param path string
---@return string|nil
local function read_pointer_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local contents = f:read("*a") or ""
  f:close()
  contents = vim.trim(contents)
  if contents == "" then
    return nil
  end
  return contents
end

---@param workspace string
---@return string|nil repo_dir Absolute path to the jj repo dir (`.jj/repo` resolved)
function M.resolve_jj_repo_dir(workspace)
  local jj_dir = workspace .. "/" .. JJ_DIR
  local repo_path = jj_dir .. "/" .. REPO_NAME
  local stat = vim.uv.fs_stat(repo_path)
  if not stat then
    return nil
  end
  if stat.type == "directory" then
    return vim.fn.resolve(repo_path)
  end
  if stat.type ~= "file" then
    return nil
  end

  local rel = read_pointer_file(repo_path)
  if not rel then
    return nil
  end
  local absolute = rel:sub(1, 1) == "/" and rel or (jj_dir .. "/" .. rel)
  return vim.fn.resolve(absolute)
end

---@param workspace string
---@return string|nil git_dir Absolute path to the git backing dir
function M.jj_backing_git_dir(workspace)
  local repo_dir = M.resolve_jj_repo_dir(workspace)
  if not repo_dir then
    return nil
  end

  local store_dir = repo_dir .. "/" .. STORE_NAME
  local target = read_pointer_file(store_dir .. "/" .. GIT_TARGET_FILE)
  if target then
    local absolute = target:sub(1, 1) == "/" and target or (store_dir .. "/" .. target)
    local resolved = vim.fn.resolve(absolute)
    if vim.fn.isdirectory(resolved) == 1 then
      return resolved
    end
  end

  local internal = store_dir .. "/" .. INTERNAL_GIT_NAME
  if vim.fn.isdirectory(internal) == 1 then
    return internal
  end
  return nil
end

---@param workspace string
---@return string|nil git_dir Shared Git directory for a colocated jj workspace
function M.colocated_git_dir(workspace)
  local repo_dir = M.resolve_jj_repo_dir(workspace)
  local git_dir = M.jj_backing_git_dir(workspace)
  if not repo_dir or not git_dir then
    return nil
  end

  local primary_jj_dir = vim.fn.fnamemodify(repo_dir, ":h")
  local primary_workspace = vim.fn.fnamemodify(primary_jj_dir, ":h")
  local expected_git_dir = vim.fn.resolve(primary_workspace .. "/.git")
  if
    vim.fn.isdirectory(expected_git_dir) ~= 1
    or vim.fs.normalize(git_dir) ~= vim.fs.normalize(expected_git_dir)
  then
    return nil
  end
  return git_dir
end

return M
