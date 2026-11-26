local paths = require("neojj.lib.jj.paths")

describe("jj display paths", function()
  for _, case in ipairs {
    { "{old.txt => new.txt}", "new.txt", "old.txt" },
    { "rules/{old.yaml => new.yaml}", "rules/new.yaml", "rules/old.yaml" },
    { "{old => new}/file.txt", "new/file.txt", "old/file.txt" },
    { "src/{old => new}/file.txt", "src/new/file.txt", "src/old/file.txt" },
    { "{old/file.txt => new/other.txt}", "new/other.txt", "old/file.txt" },
    {
      "dir with spaces/{old name => new name}.txt",
      "dir with spaces/new name.txt",
      "dir with spaces/old name.txt",
    },
    { "dir{literal}/{old => new}.txt", "dir{literal}/new.txt", "dir{literal}/old.txt" },
  } do
    it("expands " .. case[1], function()
      local name, original_name = paths.parse(case[1], "R")
      assert.are.equal(case[2], name)
      assert.are.equal(case[3], original_name)
    end)
  end

  it("expands copy paths", function()
    local name, original_name = paths.parse("src/{original => copy}.lua", "C")
    assert.are.equal("src/copy.lua", name)
    assert.are.equal("src/original.lua", original_name)
  end)

  it("does not interpret ordinary filenames as renames", function()
    for _, mode in ipairs { "A", "M", "D" } do
      local name, original_name = paths.parse("{old => new}.txt", mode)
      assert.are.equal("{old => new}.txt", name)
      assert.is_nil(original_name)
    end
  end)

  it("does not expand an already normalized destination a second time", function()
    local name, original_name = paths.parse("{old => new}.txt", "R", "source.txt")
    assert.are.equal("{old => new}.txt", name)
    assert.are.equal("source.txt", original_name)
  end)

  it("preserves paths without rename notation", function()
    local name, original_name = paths.parse("new.txt", "R")
    assert.are.equal("new.txt", name)
    assert.is_nil(original_name)
  end)
end)
