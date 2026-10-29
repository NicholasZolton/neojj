local M = {}
local source = debug.getinfo(1, "S").source:sub(2)
local plugin_root = vim.fn.fnamemodify(source, ":p:h:h:h:h:h")

---Execute the captured status selection. No real workspace file is edited by our adapter.
---@param selection table
---@param operation string
---@param message string|nil
---@return ProcessResult|nil
function M.run(selection, operation, message)
  assert(vim.tbl_contains({ "discard", "split", "commit", "squash" }, operation), "Invalid chunk operation")
  local jj = require("neojj.lib.jj")
  local cli = jj.cli
  -- Snapshot first: the selection belongs to the revision rendered in status, not a new diff.
  local snapshot = cli.status.args("-R", selection.root).call()
  assert(snapshot and snapshot.code == 0, "Cannot snapshot working copy")
  local head = cli.log.no_graph.revisions("@").template("commit_id").args("-R", selection.root).call()
  local commit = head and head.code == 0 and table.concat(head.stdout, "") or ""
  assert(
    selection.commit ~= "" and commit:sub(1, #selection.commit) == selection.commit,
    "Working copy changed since status was rendered; refresh status and retry"
  )

  local paths, whole = {}, true
  for _, file in ipairs(selection.files) do
    table.insert(paths, "root-file:" .. vim.json.encode(file.path))
    if file.original_path then
      table.insert(paths, "root-file:" .. vim.json.encode(file.original_path))
    end
    whole = whole and file.whole == true
  end
  assert(#paths > 0, "No changes selected")

  local needs_editor = (operation == "commit" or operation == "split") and message == nil
  local command
  if operation == "discard" then
    command = whole and cli.restore or cli.diffedit.revision("@")
  elseif operation == "squash" then
    -- Avoid an unexpected description editor when the last chunk empties the source.
    command = cli.squash.use_destination_message
  else
    command = cli[operation]
    if message ~= nil then
      assert(message ~= "", "A description is required")
      command.message(message)
    end
  end
  if needs_editor then
    command.env(require("neojj.client").get_envs_git_editor(false))
  end
  command.args("-R", selection.root).files(unpack(paths))
  if whole then
    return command.call { pty = needs_editor }
  end

  for _, file in ipairs(selection.files) do
    assert(
      not file.original_path,
      "Renames/copies cannot be mixed with chunks; select them separately as whole files"
    )
  end
  local conflicts =
    cli.log.no_graph.revisions("@ | @-").template("conflict").args("-R", selection.root).call()
  assert(conflicts and conflicts.code == 0, "Cannot check revision conflicts")
  assert(
    not table.concat(conflicts.stdout, ""):find("true", 1, true),
    "Chunk commands require conflict-free revisions; select whole files instead"
  )

  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p", 448)
  local ok, result = xpcall(function()
    local metadata = vim.deepcopy(selection)
    metadata.commit = commit
    metadata.operation = operation
    metadata.jj = require("neojj.lib.jj.shell").resolve_jj()
    vim.fn.writefile({ vim.json.encode(metadata) }, dir .. "/selection.json")
    local config = {
      "[merge-tools.neojj-chunks]",
      "program = " .. vim.json.encode(vim.v.progpath),
      "edit-args = " .. vim.json.encode {
        "--clean",
        "--headless",
        "-l",
        plugin_root .. "/bin/neojj-chunk-editor.lua",
        dir .. "/selection.json",
        "$left",
        "$right",
      },
      "diff-instructions = false",
    }
    vim.fn.writefile(config, dir .. "/tool.toml")
    return command.tool("neojj-chunks").args("--config-file", dir .. "/tool.toml").call { pty = needs_editor }
  end, debug.traceback)
  vim.fn.delete(dir, "rf")
  if not ok then
    error(result, 0)
  end
  return result
end

return M
