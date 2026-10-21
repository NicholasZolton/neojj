local root = vim.fn.fnamemodify(arg[0], ":p:h:h")
local ok, err = pcall(function()
  dofile(root .. "/lua/neojj/lib/jj/chunk_editor.lua").run(arg[1], arg[2], arg[3])
end)
if not ok then
  io.stderr:write("NeoJJ chunk editor: " .. tostring(err) .. "\n")
  vim.cmd("cquit 1")
end
