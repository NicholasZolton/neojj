local cli = require("neojj.lib.jj.cli")

describe("jj cli builder", function()
  describe("tostring", function()
    it("produces a command string containing the jj binary", function()
      local str = tostring(cli.log)
      assert.truthy(str:find("jj "))
    end)

    it("includes --no-pager and --color=never", function()
      local str = tostring(cli.log)
      assert.truthy(str:find("%-%-no%-pager"))
      assert.truthy(str:find("%-%-color=never"))
    end)
  end)

  describe("log command", function()
    it("includes --no-graph flag", function()
      local str = tostring(cli.log.no_graph)
      assert.truthy(str:find("%-%-no%-graph"))
    end)

    it("includes --ignore-working-copy as a readonly command", function()
      local str = tostring(cli.log)
      assert.truthy(str:find("%-%-ignore%-working%-copy"))
    end)

    it("includes -r when revisions is called", function()
      local str = tostring(cli.log.revisions("@"))
      assert.truthy(str:find("%-r"))
      assert.truthy(str:find("@"))
    end)

    it("includes -T when template is called", function()
      local str = tostring(cli.log.template("json(self)"))
      assert.truthy(str:find("%-T"))
      assert.truthy(str:find("json%(self%)"))
    end)

    it("includes -n when limit is called", function()
      local str = tostring(cli.log.limit(10))
      assert.truthy(str:find("%-n"))
      assert.truthy(str:find("10"))
    end)

    it("chains multiple options correctly", function()
      local str = tostring(cli.log.no_graph.revisions("@").template("json(self)"))
      assert.truthy(str:find("%-%-no%-graph"))
      assert.truthy(str:find("%-r"))
      assert.truthy(str:find("%-T"))
    end)
  end)

  describe("multi-word commands", function()
    it("git_push produces jj git push", function()
      local str = tostring(cli.git_push)
      assert.truthy(str:find("git"))
      assert.truthy(str:find("push"))
    end)

    it("bookmark_list produces jj bookmark list", function()
      local str = tostring(cli.bookmark_list)
      assert.truthy(str:find("bookmark"))
      assert.truthy(str:find("list"))
    end)

    it("bookmark_create produces jj bookmark create with name argument", function()
      local str = tostring(cli.bookmark_create.args("main"))
      assert.truthy(str:find("bookmark"))
      assert.truthy(str:find("create"))
      assert.truthy(str:find("main"))
    end)

    it("git_fetch produces jj git fetch", function()
      local str = tostring(cli.git_fetch)
      assert.truthy(str:find("git"))
      assert.truthy(str:find("fetch"))
    end)

    it("op_log produces jj op log", function()
      local str = tostring(cli.op_log)
      assert.truthy(str:find("op"))
      assert.truthy(str:find("log"))
    end)
  end)

  describe("describe command", function()
    it("includes -m when message is called", function()
      local str = tostring(cli.describe.message("test"))
      assert.truthy(str:find("%-m"))
      assert.truthy(str:find("test"))
    end)

    it("includes --no-edit flag", function()
      local str = tostring(cli.describe.no_edit)
      assert.truthy(str:find("%-%-no%-edit"))
    end)
  end)

  describe("readonly vs mutating commands", function()
    it("readonly commands get --ignore-working-copy", function()
      local readonly = { "log", "show", "bookmark_list", "op_log" }
      for _, cmd_name in ipairs(readonly) do
        local str = tostring(cli[cmd_name])
        assert.truthy(
          str:find("%-%-ignore%-working%-copy"),
          cmd_name .. " should have --ignore-working-copy: " .. str
        )
      end
    end)

    it("mutating commands do NOT get --ignore-working-copy", function()
      local mutating = { "describe", "new", "commit", "squash", "abandon", "rebase" }
      for _, cmd_name in ipairs(mutating) do
        local str = tostring(cli[cmd_name])
        assert.falsy(
          str:find("%-%-ignore%-working%-copy"),
          cmd_name .. " should NOT have --ignore-working-copy: " .. str
        )
      end
    end)
  end)

  describe("diff command", function()
    it("includes --git flag", function()
      local str = tostring(cli.diff.git)
      assert.truthy(str:find("%-%-git"))
    end)

    it("includes -s for summary", function()
      local str = tostring(cli.diff.summary)
      assert.truthy(str:find("%-s"))
    end)

    it("includes -r for revision option", function()
      local str = tostring(cli.diff.revision("abc"))
      assert.truthy(str:find("%-r"))
      assert.truthy(str:find("abc"))
    end)

    it("includes --from and --to options", function()
      local str = tostring(cli.diff.from("aaa").to("bbb"))
      assert.truthy(str:find("%-%-from"))
      assert.truthy(str:find("aaa"))
      assert.truthy(str:find("%-%-to"))
      assert.truthy(str:find("bbb"))
    end)
  end)

  describe("git push command", function()
    it("includes --bookmark option", function()
      local str = tostring(cli.git_push.bookmark("main"))
      assert.truthy(str:find("%-%-bookmark"))
      assert.truthy(str:find("main"))
    end)

    it("includes --all flag", function()
      local str = tostring(cli.git_push.all)
      assert.truthy(str:find("%-%-all"))
    end)

    it("includes --dry-run flag", function()
      local str = tostring(cli.git_push.dry_run)
      assert.truthy(str:find("%-%-dry%-run"))
    end)
  end)

  describe("args / files helpers", function()
    it("args appends positional arguments", function()
      local str = tostring(cli.abandon.args("abc123"))
      assert.truthy(str:find("abc123"))
    end)

    it("files appends file paths", function()
      local str = tostring(cli.diff.git.files("src/main.lua"))
      assert.truthy(str:find("src/main.lua"))
    end)
  end)

  describe("errors", function()
    it("errors on unknown command", function()
      assert.has_error(function()
        local _ = cli.nonexistent_command
      end)
    end)

    it("errors on unknown option", function()
      assert.has_error(function()
        local _ = cli.log.nonexistent_option
      end)
    end)
  end)

  describe("file show command", function()
    it("includes --ignore-working-copy as a readonly command", function()
      local str = tostring(cli.file_show)
      assert.truthy(str:find("%-%-ignore%-working%-copy"))
    end)

    it("includes -r when revision is called", function()
      local str = tostring(cli.file_show.revision("abc123"))
      assert.truthy(str:find("%-r"))
      assert.truthy(str:find("abc123"))
    end)

    it("includes file path as argument", function()
      local str = tostring(cli.file_show.revision("abc123").args("src/main.lua"))
      assert.truthy(str:find("src/main.lua"))
    end)
  end)

  describe("config get command", function()
    it("builds correct command", function()
      local str = tostring(cli.config_get.args("neojj.popup.push.force"))
      assert.truthy(str:find("config get"))
      assert.truthy(str:find("neojj.popup.push.force"))
    end)

    it("does not include --ignore-working-copy", function()
      local str = tostring(cli.config_get)
      assert.falsy(str:find("%-%-ignore%-working%-copy"))
    end)
  end)

  describe("config set command", function()
    it("includes --repo flag", function()
      local str = tostring(cli.config_set.repo.args("key", "value"))
      assert.truthy(str:find("%-%-repo"))
      assert.truthy(str:find("config set"))
    end)
  end)

  describe("config unset command", function()
    it("includes --repo flag", function()
      local str = tostring(cli.config_unset.repo.args("key"))
      assert.truthy(str:find("%-%-repo"))
      assert.truthy(str:find("config unset"))
    end)
  end)
end)
