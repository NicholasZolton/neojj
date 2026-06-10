local config = require("neojj.config")

describe("NeoJJ config", function()
  before_each(function()
    config.values = config.get_default_values()
  end)

  describe("validation", function()
    describe("for bad configs", function()
      it("should return invalid when the base config isn't a table", function()
        config.values = "INVALID CONFIG"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when disable_hint isn't a boolean", function()
        config.values.disable_hint = "not a boolean"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when disable_context_highlighting isn't a boolean", function()
        config.values.disable_context_highlighting = "not a boolean"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when disable_signs isn't a boolean", function()
        config.values.disable_signs = "not a boolean"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when telescope_sorter isn't a function", function()
        config.values.telescope_sorter = "not a function"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when disable_insert_on_commit isn't a boolean or 'auto'", function()
        config.values.disable_insert_on_commit = "not auto"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)

        config.values.disable_insert_on_commit = 42
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when use_per_project_settings isn't a boolean", function()
        config.values.use_per_project_settings = "not a boolean"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when remember_settings isn't a boolean", function()
        config.values.remember_settings = "not a boolean"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when notification_icon isn't a string", function()
        config.values.notification_icon = false
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when kind isn't a string", function()
        config.values.kind = true
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when kind isn't a valid kind", function()
        config.values.kind = "not a valid kind"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when floating isn't a table", function()
        config.values.floating = "not a table"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when floating fields have wrong types", function()
        config.values.floating.relative = false
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)

        config.values = config.get_default_values()
        config.values.floating.width = "not a number"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)

        config.values = config.get_default_values()
        config.values.floating.height = "not a number"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)

        config.values = config.get_default_values()
        config.values.floating.style = false
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)

        config.values = config.get_default_values()
        config.values.floating.border = false
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when disable_line_numbers isn't a boolean", function()
        config.values.disable_line_numbers = "not a boolean"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when disable_relative_line_numbers isn't a boolean", function()
        config.values.disable_relative_line_numbers = "not a boolean"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when console_timeout isn't a number", function()
        config.values.console_timeout = "not a number"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when auto_show_console isn't a boolean", function()
        config.values.auto_show_console = "not a boolean"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when auto_show_console_on isn't a string", function()
        config.values.auto_show_console_on = true
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when auto_close_console isn't a boolean", function()
        config.values.auto_close_console = "not a boolean"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return valid when workspace hook commands are functions", function()
        config.values.workspace_initialize_command = function() end
        config.values.workspace_open_command = function() end
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
      end)

      -- status
      it("should return invalid when status isn't a table", function()
        config.values.status = "not a table"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when status.recent_commit_count isn't a number", function()
        config.values.status.recent_commit_count = "not a number"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when status.show_head_commit_hash isn't a boolean", function()
        config.values.status.show_head_commit_hash = "not a boolean"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when status.mode_padding isn't a number", function()
        config.values.status.mode_padding = "not a number"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when status.HEAD_padding isn't a number", function()
        config.values.status.HEAD_padding = "not a number"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when status.mode_text isn't a table", function()
        config.values.status.mode_text = "not a table"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      -- commit_editor
      it("should return invalid when commit_editor isn't a table", function()
        config.values.commit_editor = "not a table"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when commit_editor.kind isn't a string", function()
        config.values.commit_editor.kind = false
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when commit_editor.kind isn't a valid kind", function()
        config.values.commit_editor.kind = "not a valid kind"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when commit_editor.spell_check isn't a boolean", function()
        config.values.commit_editor.spell_check = "not a boolean"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      -- commit_view
      it("should return invalid when commit_view isn't a table", function()
        config.values.commit_view = "not a table"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when commit_view.kind isn't a valid kind", function()
        config.values.commit_view.kind = "not a valid kind"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      -- log_view
      it("should return invalid when log_view isn't a table", function()
        config.values.log_view = "not a table"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when log_view.kind isn't a valid kind", function()
        config.values.log_view.kind = "not a valid kind"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      -- reflog_view
      it("should return invalid when reflog_view isn't a table", function()
        config.values.reflog_view = "not a table"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when reflog_view.kind isn't a valid kind", function()
        config.values.reflog_view.kind = "not a valid kind"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      -- refs_view
      it("should return invalid when refs_view isn't a table", function()
        config.values.refs_view = "not a table"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when refs_view.kind isn't a valid kind", function()
        config.values.refs_view.kind = "not a valid kind"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      -- preview_buffer
      it("should return invalid when preview_buffer isn't a table", function()
        config.values.preview_buffer = "not a table"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when preview_buffer.kind isn't a valid kind", function()
        config.values.preview_buffer.kind = "not a valid kind"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      -- popup
      it("should return invalid when popup isn't a table", function()
        config.values.popup = "not a table"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when popup.kind isn't a valid kind", function()
        config.values.popup.kind = "not a valid kind"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      -- signs
      it("should return invalid when signs isn't a table", function()
        config.values.signs = "not a table"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when signs.hunk isn't valid", function()
        config.values.signs.hunk = "not a table"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when signs.hunk is not of size 2", function()
        config.values.signs.hunk = { "" }
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when signs.hunk elements aren't strings", function()
        config.values.signs.hunk = { false, "" }
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)

        config.values.signs.hunk = { "", false }
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)

        config.values.signs.hunk = { false, false }
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when signs.item isn't valid", function()
        config.values.signs.item = "not a table"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when signs.item is not of size 2", function()
        config.values.signs.item = { "" }
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when signs.item elements aren't strings", function()
        config.values.signs.item = { false, "" }
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)

        config.values.signs.item = { "", false }
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)

        config.values.signs.item = { false, false }
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when signs.section isn't valid", function()
        config.values.signs.section = "not a table"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when signs.section is not of size 2", function()
        config.values.signs.section = { "" }
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when signs.section elements aren't strings", function()
        config.values.signs.section = { false, "" }
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)

        config.values.signs.section = { "", false }
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)

        config.values.signs.section = { false, false }
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      -- integrations
      it("should return invalid when integrations isn't a table", function()
        config.values.integrations = false
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      -- diff_viewer
      it("should return invalid when diff_viewer isn't a valid viewer", function()
        config.values.diff_viewer = "invalid_viewer"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      -- sections
      it("should return invalid when sections isn't a table", function()
        config.values.sections = "not a table"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when sections.untracked isn't a table", function()
        config.values.sections.untracked = "not a table"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when sections.untracked.folded isn't a boolean", function()
        config.values.sections.untracked.folded = "not a boolean"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when sections.untracked.hidden isn't a boolean", function()
        config.values.sections.untracked.hidden = "not a boolean"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when sections.recent isn't a table", function()
        config.values.sections.recent = "not a table"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when sections.recent.folded isn't a boolean", function()
        config.values.sections.recent.folded = "not a boolean"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when sections.sequencer isn't a table", function()
        config.values.sections.sequencer = "not a table"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when sections.sequencer.folded isn't a boolean", function()
        config.values.sections.sequencer.folded = "not a boolean"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      -- ignored_settings
      it("should return invalid when ignored_settings isn't a table", function()
        config.values.ignored_settings = "not a table"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      it("should return invalid when ignored_settings has an invalid setting format", function()
        config.values.ignored_settings = { "invalid setting format!", "Filetype-yep", "NeoJJ+example" }
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)

        config.values.ignored_settings = { "Valid--format", "Invalid-format" }
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      -- mappings
      it("should return invalid when mappings isn't a table", function()
        config.values.mappings = "not a table"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
      end)

      describe("finder mappings", function()
        it("should return invalid when it's not a table", function()
          config.values.mappings.finder = "not a table"
          assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
        end)

        it("should return invalid when a individual mapping is not a string", function()
          config.values.mappings.finder = {
            ["c"] = { { "Close" } },
          }
          assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
        end)

        it("should return invalid when a command mapping is not known", function()
          config.values.mappings.finder = {
            ["c"] = { "Invalid Command" },
          }
          assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
        end)
      end)

      describe("status mappings", function()
        it("should return invalid when it's not a table", function()
          config.values.mappings.status = "not a table"
          assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
        end)

        it("should return invalid when a mapping is not a string or boolean", function()
          config.values.mappings.status = {
            ["Close"] = {},
          }
          assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
        end)

        it("should return invalid when a command mapping is not known", function()
          config.values.mappings.status = {
            ["Invalid Command"] = "c",
          }
          assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
        end)
      end)

      describe("popup mappings", function()
        it("should return invalid when it's not a table", function()
          config.values.mappings.popup = "not a table"
          assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
        end)

        it("should return invalid when a command mapping is not known", function()
          config.values.mappings.popup = {
            ["z"] = "InvalidPopupCommand",
          }
          assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
        end)
      end)

      describe("commit_editor mappings", function()
        it("should return invalid when it's not a table", function()
          config.values.mappings.commit_editor = "not a table"
          assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
        end)

        it("should return invalid when a command mapping is not known", function()
          config.values.mappings.commit_editor = {
            ["z"] = "InvalidCommand",
          }
          assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
        end)
      end)

      describe("commit_editor_I mappings", function()
        it("should return invalid when it's not a table", function()
          config.values.mappings.commit_editor_I = "not a table"
          assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
        end)

        it("should return invalid when a command mapping is not known", function()
          config.values.mappings.commit_editor_I = {
            ["z"] = "InvalidCommand",
          }
          assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
        end)
      end)

      describe("forge", function()
        it("should return invalid when forge isn't a table", function()
          config.values.forge = "not a table"
          assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
        end)

        it("should return invalid when forge.pr_integration isn't a boolean", function()
          config.values.forge.pr_integration = "not a boolean"
          assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
        end)

        it("should return invalid when forge.hosts isn't a table of string lists", function()
          config.values.forge.hosts = "not a table"
          assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)

          config.values = config.get_default_values()
          config.values.forge.hosts = { github = "not a list" }
          assert.True(vim.tbl_count(require("neojj.config").validate_config()) ~= 0)
        end)
      end)
    end)

    describe("for good configs", function()
      it("should return valid for the default config", function()
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
      end)

      it("should return valid for a forge config with extra hosts", function()
        config.values.forge = {
          pr_integration = false,
          hosts = { github = { "git.corp.com" } },
        }
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
      end)

      it("should return valid when kind is a valid window kind", function()
        config.values.kind = "floating"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
      end)

      it("should return valid for all valid window kinds", function()
        local valid_kinds = {
          "split",
          "vsplit",
          "split_above",
          "split_above_all",
          "split_below",
          "split_below_all",
          "vsplit_left",
          "tab",
          "floating",
          "floating_console",
          "replace",
          "auto",
        }
        for _, kind in ipairs(valid_kinds) do
          config.values = config.get_default_values()
          config.values.kind = kind
          assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
        end
      end)

      it("should return valid when disable_line_numbers is a boolean", function()
        config.values.disable_line_numbers = true
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
      end)

      it("should return valid when disable_insert_on_commit is true", function()
        config.values.disable_insert_on_commit = true
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
      end)

      it("should return valid when disable_insert_on_commit is false", function()
        config.values.disable_insert_on_commit = false
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
      end)

      it("should return valid when disable_insert_on_commit is 'auto'", function()
        config.values.disable_insert_on_commit = "auto"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
      end)

      it("should return valid when commit_editor.kind is a valid window kind", function()
        config.values.commit_editor.kind = "replace"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
      end)

      it("should return valid when commit_view.kind is a valid window kind", function()
        config.values.commit_view.kind = "split_above"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
      end)

      it("should return valid when log_view.kind is a valid window kind", function()
        config.values.log_view.kind = "vsplit"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
      end)

      it("should return valid when reflog_view.kind is a valid window kind", function()
        config.values.reflog_view.kind = "vsplit"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
      end)

      it("should return valid when refs_view.kind is a valid window kind", function()
        config.values.refs_view.kind = "tab"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
      end)

      it("should return valid when preview_buffer.kind is a valid window kind", function()
        config.values.preview_buffer.kind = "floating"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
      end)

      it("should return valid when popup.kind is a valid window kind", function()
        config.values.popup.kind = "floating"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
      end)

      it("should return valid when diff_viewer is nil", function()
        config.values.diff_viewer = nil
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
      end)

      it("should return valid when diff_viewer is 'diffview'", function()
        config.values.diff_viewer = "diffview"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
      end)

      it("should return valid when diff_viewer is 'codediff'", function()
        config.values.diff_viewer = "codediff"
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
      end)

      it("should return valid when ignored_settings has a valid setting", function()
        config.values.ignored_settings = { "Valid--setting-format" }
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
      end)

      it("should return valid when a command mappings.status is a boolean", function()
        config.values.mappings.status["c"] = false
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
      end)

      it("should return valid when a command mappings.status is a function", function()
        config.values.mappings.status["c"] = function()
          print("custom function")
        end
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
      end)

      it("should return valid when a command mappings.finder is a boolean", function()
        config.values.mappings.finder["c"] = false
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
      end)

      it("should return valid when a command mappings.popup is a boolean", function()
        config.values.mappings.popup["z"] = false
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
      end)

      it("should return valid when a command mappings.commit_editor is a function", function()
        config.values.mappings.commit_editor["z"] = function()
          print("custom function")
        end
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
      end)

      it("should return valid when a command mappings.commit_editor_I is a function", function()
        config.values.mappings.commit_editor_I["z"] = function()
          print("custom function")
        end
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
      end)

      it("should return valid when sections have valid folded and hidden booleans", function()
        config.values.sections.untracked = { folded = true, hidden = true }
        config.values.sections.recent = { folded = false, hidden = false }
        config.values.sections.sequencer = { folded = true, hidden = false }
        assert.True(vim.tbl_count(require("neojj.config").validate_config()) == 0)
      end)
    end)
  end)

  describe("default popup mappings", function()
    it("uses lowercase keys for all popup triggers", function()
      local popup_maps = config.get_default_values().mappings.popup
      assert.are.same("SquashPopup", popup_maps["s"])
      assert.are.same("WorkspacePopup", popup_maps["w"])
      assert.are.same("PushPopup", popup_maps["p"])
      assert.are.same("RemotePopup", popup_maps["m"])
      assert.Nil(popup_maps["S"])
      assert.Nil(popup_maps["W"])
      assert.Nil(popup_maps["P"])
      assert.Nil(popup_maps["M"])
    end)
  end)

  describe("check_integration", function()
    it("should resolve mini_pick to mini.pick module", function()
      -- When mini.pick is available, check_integration("mini_pick") should find it
      -- via the integration_modules mapping instead of trying require("mini-pick")
      config.values.integrations = {}
      local has_mini_pick = pcall(require, "mini.pick")
      assert.are.equal(has_mini_pick, config.check_integration("mini_pick"))
    end)

    it("should respect explicit integration overrides", function()
      config.values.integrations = { mini_pick = false }
      assert.is_false(config.check_integration("mini_pick"))
    end)

    it("should respect explicit true override", function()
      config.values.integrations = { mini_pick = true }
      assert.is_true(config.check_integration("mini_pick"))
    end)
  end)
end)
