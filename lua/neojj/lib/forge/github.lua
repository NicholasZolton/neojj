---GitHub forge provider, backed by the `gh` CLI.
---@type neojj.Forge
local M = {
  name = "github",
  executable = "gh",
  default_hosts = { "github.com" },
  ---Build the `gh pr list` command. The repo is passed explicitly via
  ---`--repo` so gh works in non-colocated jj workspaces, where there is no
  ---`.git` directory for it to discover the repo from. Only open PRs are
  ---listed: `--state all` needs deep pagination and `--search` routes
  ---through the slow search API — both multiply latency several-fold.
  ---@param info neojj.RemoteInfo
  ---@return string[]
  pr_list_cmd = function(info)
    return {
      "gh",
      "pr",
      "list",
      "--repo",
      info.host .. "/" .. info.slug,
      "--state",
      "open",
      "--limit",
      "500",
      "--json",
      "number,title,url,headRefName,isCrossRepository,isDraft",
    }
  end,

  ---Parse `gh pr list --json` output into normalized PRs. Cross-repository
  ---(fork) PRs are dropped: their head ref names live in the fork's namespace
  ---and would falsely match local bookmarks.
  ---@param stdout string|nil
  ---@return neojj.ForgePR[]|nil
  parse_prs = function(stdout)
    if type(stdout) ~= "string" then
      return nil
    end

    local ok, decoded = pcall(vim.json.decode, stdout)
    if not ok or type(decoded) ~= "table" then
      return nil
    end

    local prs = {}
    for _, raw in ipairs(decoded) do
      if not raw.isCrossRepository then
        table.insert(prs, {
          number = raw.number,
          title = raw.title,
          url = raw.url,
          branch = raw.headRefName,
          draft = raw.isDraft == true,
        })
      end
    end

    return prs
  end,
}

return M
