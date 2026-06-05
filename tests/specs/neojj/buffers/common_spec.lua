local MODULE = "neojj.buffers.common"

---@param stubs table<string, any>
---@param fn fun(common: table)
local function with_common_module(stubs, fn)
  local saved = {}
  for name, mod in pairs(stubs) do
    saved[name] = package.loaded[name]
    package.loaded[name] = mod
  end

  local saved_subject = package.loaded[MODULE]
  package.loaded[MODULE] = nil

  local ok, err = pcall(function()
    local common = require(MODULE)
    fn(common)
  end)

  package.loaded[MODULE] = saved_subject
  for name, _ in pairs(stubs) do
    package.loaded[name] = saved[name]
  end

  assert.is_true(ok, err)
end

---Builds stubs for the modules abandon helpers touch, plus spies.
---@param opts? { abandon_code?: integer, permission?: boolean }
local function base_stubs(opts)
  opts = opts or {}
  local spies = {
    abandoned = {},
    warnings = {},
    infos = {},
  }
  local stubs = {
    ["neojj.lib.jj"] = {
      cli = {
        abandon = {
          args = function(rev)
            table.insert(spies.abandoned, rev)
            return {
              call = function()
                return { code = opts.abandon_code or 0 }
              end,
            }
          end,
        },
      },
    },
    ["neojj.lib.notification"] = {
      info = function(msg)
        table.insert(spies.infos, msg)
      end,
      warn = function(msg)
        table.insert(spies.warnings, msg)
      end,
    },
    ["neojj.lib.input"] = {
      get_permission = function()
        return opts.permission ~= false
      end,
    },
  }
  return stubs, spies
end

describe("buffers.common abandon helpers", function()
  describe("abandon_change", function()
    it("abandons by change_id and refreshes on success", function()
      local stubs, spies = base_stubs()
      with_common_module(stubs, function(common)
        local refreshed = false
        common.abandon_change({ change_id = "abcdefgh12345678" }, function()
          refreshed = true
        end)
        assert.are.same({ "abcdefgh12345678" }, spies.abandoned)
        assert.True(refreshed)
        assert.are.same(1, #spies.infos)
      end)
    end)

    it("warns and does nothing for an immutable change", function()
      local stubs, spies = base_stubs()
      with_common_module(stubs, function(common)
        local refreshed = false
        common.abandon_change({ change_id = "abcdefgh12345678", immutable = true }, function()
          refreshed = true
        end)
        assert.are.same({}, spies.abandoned)
        assert.False(refreshed)
        assert.are.same(1, #spies.warnings)
      end)
    end)

    it("does nothing when permission is denied", function()
      local stubs, spies = base_stubs { permission = false }
      with_common_module(stubs, function(common)
        local refreshed = false
        common.abandon_change({ change_id = "abcdefgh12345678" }, function()
          refreshed = true
        end)
        assert.are.same({}, spies.abandoned)
        assert.False(refreshed)
      end)
    end)

    it("warns and does not refresh when the CLI fails", function()
      local stubs, spies = base_stubs { abandon_code = 1 }
      with_common_module(stubs, function(common)
        local refreshed = false
        common.abandon_change({ change_id = "abcdefgh12345678" }, function()
          refreshed = true
        end)
        assert.are.same({ "abcdefgh12345678" }, spies.abandoned)
        assert.False(refreshed)
        assert.are.same(1, #spies.warnings)
      end)
    end)
  end)

  describe("abandon_at_cursor", function()
    it("routes variant rows to abandon_variant (by commit_id)", function()
      local stubs, spies = base_stubs()
      with_common_module(stubs, function(common)
        local refreshed = false
        common.abandon_at_cursor(
          { change_id = "abcdefgh12345678", commit_id = "1111222233334444", change_offset = 0 },
          function()
            refreshed = true
          end
        )
        assert.are.same({ "1111222233334444" }, spies.abandoned)
        assert.True(refreshed)
      end)
    end)

    it("warns and does nothing on a divergent parent row", function()
      local stubs, spies = base_stubs()
      with_common_module(stubs, function(common)
        local refreshed = false
        common.abandon_at_cursor({ change_id = "abcdefgh12345678", variants = {} }, function()
          refreshed = true
        end)
        assert.are.same({}, spies.abandoned)
        assert.False(refreshed)
        assert.are.same(1, #spies.warnings)
      end)
    end)

    it("routes normal change rows to abandon_change (by change_id)", function()
      local stubs, spies = base_stubs()
      with_common_module(stubs, function(common)
        local refreshed = false
        common.abandon_at_cursor({ change_id = "abcdefgh12345678" }, function()
          refreshed = true
        end)
        assert.are.same({ "abcdefgh12345678" }, spies.abandoned)
        assert.True(refreshed)
      end)
    end)

    it("does nothing for nil items or items without ids", function()
      local stubs, spies = base_stubs()
      with_common_module(stubs, function(common)
        common.abandon_at_cursor(nil, function() end)
        common.abandon_at_cursor({ name = "some-bookmark" }, function() end)
        assert.are.same({}, spies.abandoned)
        assert.are.same({}, spies.warnings)
      end)
    end)
  end)
end)
