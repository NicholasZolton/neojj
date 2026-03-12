local M = {}

local api = vim.api

function M.setup()
  local a = require("plenary.async")
  local status_buffer = require("neojj.buffers.status")
  local jj = require("neojj.lib.jj")
  local group = require("neojj").autocmd_group

  api.nvim_create_autocmd({ "ColorScheme" }, {
    callback = function()
      local config = require("neojj.config")
      local highlight = require("neojj.lib.hl")

      highlight.setup(config.values)
    end,
    group = group,
  })

  local autocmd_disabled = false
  api.nvim_create_autocmd({ "BufWritePost", "ShellCmdPost", "VimResume" }, {
    callback = a.void(function(o)
      if
        not autocmd_disabled
        and status_buffer.is_open()
        and not api.nvim_get_option_value("filetype", { buf = o.buf }):match("^Neojj")
      then
        local path = jj.repo:relpath(o.file)
        if path then
          status_buffer
            .instance()
            :dispatch_refresh({ update_diffs = { "*:" .. path } }, string.format("%s:%s", o.event, path))
        end
      end
    end),
    group = group,
  })

  --- vimpgrep creates and deletes lots of buffers so attaching to each one will
  --- waste lots of resource and even slow down vimgrep.
  api.nvim_create_autocmd({ "QuickFixCmdPre", "QuickFixCmdPost" }, {
    group = group,
    pattern = "*vimgrep*",
    callback = function(args)
      autocmd_disabled = args.event == "QuickFixCmdPre"
    end,
  })

  -- Ensure vim buffers are updated
  api.nvim_create_autocmd("User", {
    pattern = "NeojjStatusRefreshed",
    callback = function()
      vim.cmd("set autoread | checktime")
    end,
  })
end

return M
