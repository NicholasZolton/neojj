local MODULES = {
  "neojj.integrations.diffview",
  "neojj.lib.jj",
  "neojj.watcher",
  "diffview.vcs",
  "diffview.vcs.adapters.git.rev",
  "diffview.vcs.rev",
  "diffview.api.views.diff.diff_view",
  "diffview.lib",
  "diffview.utils",
}

describe("diffview integration", function()
  it("removes the trailing empty line from revision content", function()
    local saved = {}
    for _, name in ipairs(MODULES) do
      saved[name] = package.loaded[name]
    end

    local captured
    local builder = {}
    function builder.revision()
      return builder
    end
    function builder.args()
      return builder
    end
    function builder.call()
      return { code = 0, stdout = { "content", "" } }
    end

    package.loaded["diffview.vcs"] = { __neojj_patched = true }
    package.loaded["diffview.vcs.adapters.git.rev"] = {
      GitRev = function(value)
        return value
      end,
    }
    package.loaded["diffview.vcs.rev"] = { RevType = { STAGE = "stage", LOCAL = "local" } }
    package.loaded["diffview.api.views.diff.diff_view"] = {
      CDiffView = function(opts)
        captured = opts
        return {
          on_files_staged = function() end,
          open = function() end,
        }
      end,
    }
    package.loaded["diffview.lib"] = { add_view = function() end }
    package.loaded["diffview.utils"] = {
      tbl_pack = function(value)
        return { value }
      end,
    }
    package.loaded["neojj.watcher"] = {
      instance = function()
        return { dispatch_refresh = function() end }
      end,
    }
    package.loaded["neojj.lib.jj"] = {
      repo = {
        worktree_root = vim.fn.getcwd(),
        state = { files = { items = { { name = "file.txt", mode = "M" } } } },
      },
      cli = { file_show = builder },
    }
    package.loaded["neojj.integrations.diffview"] = nil

    require("neojj.integrations.diffview").open("modified", "file.txt", {})
    local lines = captured.get_file_data(nil, "file.txt", "left")

    for _, name in ipairs(MODULES) do
      package.loaded[name] = saved[name]
    end

    assert.are.same({ "content" }, lines)
  end)
end)
