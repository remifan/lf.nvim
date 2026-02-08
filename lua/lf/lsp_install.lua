-- LSP jar installer for lf.nvim
-- Downloads pre-built LSP server jar from GitHub releases

local M = {}

local uv = vim.loop

local GITHUB_REPO = "remifan/lf.nvim"
local RELEASES_URL = "https://github.com/" .. GITHUB_REPO .. "/releases"

-- Where to store the downloaded jar
local function get_install_dir()
  local dir = vim.fn.stdpath("data") .. "/lf-lsp"
  vim.fn.mkdir(dir, "p")
  return dir
end

-- List available versions from GitHub releases via gh CLI
local function fetch_versions(callback)
  local cmd = { "gh", "api", "repos/" .. GITHUB_REPO .. "/releases",
    "--jq", '.[] | select(.tag_name | startswith("lsp-")) | .tag_name | ltrimstr("lsp-")' }

  local stdout_chunks = {}
  local stderr_chunks = {}
  local handle
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)

  handle = uv.spawn(cmd[1], {
    args = vim.list_slice(cmd, 2),
    stdio = { nil, stdout, stderr },
  }, function(code)
    stdout:close()
    stderr:close()
    handle:close()
    vim.schedule(function()
      if code ~= 0 then
        -- Fall back to curl if gh is not available
        fetch_versions_curl(callback)
        return
      end
      local output = table.concat(stdout_chunks)
      local versions = {}
      for v in output:gmatch("[^\n]+") do
        table.insert(versions, v)
      end
      callback(versions, nil)
    end)
  end)

  if not handle then
    vim.schedule(function() fetch_versions_curl(callback) end)
    return
  end

  stdout:read_start(function(_, data)
    if data then table.insert(stdout_chunks, data) end
  end)
  stderr:read_start(function(_, data)
    if data then table.insert(stderr_chunks, data) end
  end)
end

-- Fallback: list versions via curl
local function fetch_versions_curl(callback)
  local url = "https://api.github.com/repos/" .. GITHUB_REPO .. "/releases"
  local cmd = { "curl", "-fsSL", url }

  local stdout_chunks = {}
  local handle
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)

  handle = uv.spawn(cmd[1], {
    args = vim.list_slice(cmd, 2),
    stdio = { nil, stdout, stderr },
  }, function(code)
    stdout:close()
    stderr:close()
    handle:close()
    vim.schedule(function()
      if code ~= 0 then
        callback(nil, "Failed to fetch releases")
        return
      end
      local output = table.concat(stdout_chunks)
      local ok, releases = pcall(vim.json.decode, output)
      if not ok then
        callback(nil, "Failed to parse releases JSON")
        return
      end
      local versions = {}
      for _, rel in ipairs(releases) do
        local tag = rel.tag_name or ""
        if tag:match("^lsp%-") then
          table.insert(versions, tag:gsub("^lsp%-", ""))
        end
      end
      callback(versions, nil)
    end)
  end)

  if not handle then
    callback(nil, "Failed to spawn curl")
    return
  end

  stdout:read_start(function(_, data)
    if data then table.insert(stdout_chunks, data) end
  end)
end

-- Download the jar for a given version (e.g. "v0.11.0")
local function download_jar(version, callback)
  local jar_name = "lsp-" .. version:gsub("^v", "") .. "-all.jar"
  local url = RELEASES_URL .. "/download/lsp-" .. version .. "/" .. jar_name
  local dest = get_install_dir() .. "/" .. jar_name

  -- Check if already downloaded
  if vim.fn.filereadable(dest) == 1 then
    callback(dest, nil)
    return
  end

  vim.notify("[lf.nvim] Downloading " .. jar_name .. "...", vim.log.levels.INFO)

  local stderr_chunks = {}
  local handle
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)

  handle = uv.spawn("curl", {
    args = { "-fSL", "--progress-bar", "-o", dest, url },
    stdio = { nil, stdout, stderr },
  }, function(code)
    stdout:close()
    stderr:close()
    handle:close()
    vim.schedule(function()
      if code ~= 0 then
        vim.fn.delete(dest)
        callback(nil, "Download failed: " .. table.concat(stderr_chunks))
      else
        callback(dest, nil)
      end
    end)
  end)

  if not handle then
    callback(nil, "Failed to spawn curl")
    return
  end

  stdout:read_start(function() end)
  stderr:read_start(function(_, data)
    if data then table.insert(stderr_chunks, data) end
  end)
end

-- Find currently installed jar
function M.get_installed_jar()
  local dir = get_install_dir()
  local jars = vim.fn.glob(dir .. "/lsp-*-all.jar", false, true)
  if #jars > 0 then
    table.sort(jars)
    return jars[#jars] -- latest by name
  end
  return nil
end

-- Install: fetch versions, let user pick, download
function M.install(opts)
  opts = opts or {}

  if vim.fn.executable("curl") == 0 then
    vim.notify("[lf.nvim] curl is required for LFLspInstall", vim.log.levels.ERROR)
    return
  end

  vim.notify("[lf.nvim] Fetching available LSP versions...", vim.log.levels.INFO)

  fetch_versions(function(versions, err)
    if err or not versions or #versions == 0 then
      vim.notify("[lf.nvim] No LSP releases found. " .. (err or ""), vim.log.levels.ERROR)
      return
    end

    -- If only one version, use it directly
    if #versions == 1 then
      download_jar(versions[1], function(path, dl_err)
        if dl_err then
          vim.notify("[lf.nvim] " .. dl_err, vim.log.levels.ERROR)
        else
          on_install_complete(path)
        end
      end)
      return
    end

    -- Let user pick
    vim.ui.select(versions, { prompt = "Select LF LSP version:" }, function(choice)
      if not choice then return end
      download_jar(choice, function(path, dl_err)
        if dl_err then
          vim.notify("[lf.nvim] " .. dl_err, vim.log.levels.ERROR)
        else
          on_install_complete(path)
        end
      end)
    end)
  end)
end

function on_install_complete(path)
  vim.notify(
    "[lf.nvim] LSP server installed: " .. path .. "\n\n" ..
    "Add to your shell profile:\n" ..
    "  export LF_LSP_JAR=" .. path,
    vim.log.levels.INFO
  )
end

-- Show status
function M.status()
  local jar = M.get_installed_jar()
  local dir = get_install_dir()
  local jars = vim.fn.glob(dir .. "/lsp-*-all.jar", false, true)

  local lines = {
    "LF LSP Server Status",
    "====================",
    "",
    "Install directory: " .. dir,
    "Installed versions:",
  }

  if #jars == 0 then
    table.insert(lines, "  (none)")
  else
    for _, j in ipairs(jars) do
      table.insert(lines, "  " .. vim.fn.fnamemodify(j, ":t"))
    end
  end

  -- Check what's currently configured
  local config = require("lf").get_config()
  table.insert(lines, "")
  table.insert(lines, "Current jar_path: " .. (config.lsp.jar_path or "(auto-detect)"))
  table.insert(lines, "LF_LSP_JAR env: " .. (vim.env.LF_LSP_JAR or "(not set)"))

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

return M
