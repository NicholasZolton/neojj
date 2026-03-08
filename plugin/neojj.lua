local api = vim.api

api.nvim_create_user_command("Neojj", function(o)
  local neojj = require("neojj")
  neojj.open(require("neojj.lib.util").parse_command_args(o.fargs))
end, {
  nargs = "*",
  desc = "Open Neojj",
  complete = function(arglead)
    local neojj = require("neojj")
    return neojj.complete(arglead)
  end,
})

api.nvim_create_user_command("NeojjResetState", function()
  require("neojj.lib.state")._reset()
end, { nargs = "*", desc = "Reset any saved flags" })

api.nvim_create_user_command("NeojjLogCurrent", function(args)
  local action = require("neojj").action
  local path = vim.fn.expand(args.fargs[1] or "%")

  if args.range > 0 then
    action("log", "log_current", { "-L" .. args.line1 .. "," .. args.line2 .. ":" .. path })()
  else
    action("log", "log_current", { "--", path })()
  end
end, {
  nargs = "?",
  desc = "Open git log (current) for specified file, or current file if unspecified. Optionally accepts a range.",
  range = "%",
  complete = "file",
})

api.nvim_create_user_command("NeojjCommit", function(args)
  local commit = args.fargs[1] or "HEAD"
  local CommitViewBuffer = require("neojj.buffers.commit_view")
  CommitViewBuffer.new(commit):open()
end, {
  nargs = "?",
  desc = "Open git commit view for specified commit, or HEAD",
})
