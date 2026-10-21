local M = {}
local running = {}

---Capture rendered rows, not hunk.first/last: folding changes their screen positions.
---@param ui Ui
---@param visual boolean
---@param root string
---@param commit string
---@return table
function M.select(ui, visual, root, commit)
  local cursor = vim.fn.line(".")
  local first, last = cursor, cursor
  if visual then
    assert(vim.fn.mode() ~= "\22", "Blockwise chunk selection is unsupported; use linewise visual mode")
    first, last = math.min(cursor, vim.fn.line("v")), math.max(cursor, vim.fn.line("v"))
  end

  local files, by_name = {}, {}
  local function file_for(item)
    assert(
      not ((item.mode == "R" or item.mode == "C") and not item.original_name),
      "Status has no separate source/destination paths for this rename/copy; use native jj commands"
    )
    local file = by_name[item.name]
    if not file then
      file = { path = item.name, original_path = item.original_name, hunks = {} }
      by_name[item.name] = file
      table.insert(files, file)
    end
    return file
  end

  for _, section in ipairs(ui.item_index) do
    if section.name == "files" and section.first <= last and section.last >= first then
      local entire_section = first <= section.first and last >= section.first
      for _, item in ipairs(section.items) do
        if entire_section or (item.first <= last and item.last >= first) then
          local file = file_for(item)
          if entire_section or (first <= item.first and last >= item.first) then
            file.whole = true
          else
            local diff = item.diff
            assert(
              not item.original_name and diff.kind ~= "renamed",
              "Select renamed files by their file header"
            )
            assert(not item.conflict, "Select conflicted files by their file header")
            local chosen = {}
            for row = math.max(first, item.first + 1), math.min(last, item.last) do
              local component = ui:get_component_on_line(row, function(node)
                return node.options.hunk ~= nil
              end)
              if component then
                local hunk = assert(component.options.hunk, "Selected component has no hunk")
                local header = component:row_range_abs()
                if not visual or row == header then
                  chosen[hunk] = true
                elseif chosen[hunk] ~= true then
                  local offset = row - header
                  local prefix = (hunk.lines[offset] or ""):sub(1, 1)
                  if prefix == "+" or prefix == "-" then
                    chosen[hunk] = chosen[hunk] or {}
                    chosen[hunk][tostring(offset)] = true
                  end
                end
              end
            end
            for _, hunk in ipairs(diff.hunks) do
              table.insert(file.hunks, {
                index_from = hunk.index_from,
                index_len = hunk.index_len,
                disk_from = hunk.disk_from,
                disk_len = hunk.disk_len,
                lines = hunk.lines,
                selected = chosen[hunk] or false,
              })
              if chosen[hunk] then
                file.has_selection = true
              end
            end
          end
        end
      end
    end
  end
  files = vim.tbl_filter(function(file)
    return file.whole or file.has_selection
  end, files)
  assert(#files > 0, "No changed lines selected")
  return { files = files, root = root, commit = commit }
end

---@param self StatusBuffer
---@param operation string
---@param visual boolean
function M.action(self, operation, visual)
  return require("plenary.async").void(function()
    local notification = require("neojj.lib.notification")
    local jj = require("neojj.lib.jj")
    local root = jj.repo.worktree_root
    if running[root] then
      notification.warn("A chunk command is already running", { dismiss = true })
      return
    end
    local ok, selection = pcall(M.select, self.buffer.ui, visual, root, jj.repo.state.head.commit_id)
    if not ok then
      notification.warn(tostring(selection), { dismiss = true })
      return
    end
    if visual then
      vim.cmd("normal! \27")
    end

    local input = require("neojj.lib.input")
    if
      operation == "discard"
      and not input.get_permission(("Discard selected changes in %d file(s)?"):format(#selection.files))
    then
      return
    end
    running[root] = true
    local success, result = pcall(require("neojj.lib.jj.chunks").run, selection, operation)
    running[root] = nil
    if not success then
      notification.error(tostring(result))
    elseif not result or result.code ~= 0 then
      local output = result and (#result.stderr > 0 and result.stderr or result.stdout) or {}
      notification.error("Chunk command failed: " .. table.concat(output, "\n"))
    elseif operation ~= "discard" then
      local event = ({
        commit = "NeojjCommitComplete",
        split = "NeojjSplitComplete",
        squash = "NeojjSquashComplete",
      })[operation]
      vim.api.nvim_exec_autocmds("User", { pattern = event, modeline = false })
    end
    self:dispatch_refresh(nil, "chunks_" .. operation)
  end)
end

return M
