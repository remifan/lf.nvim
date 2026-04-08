-- LSP jar installer for lf.nvim
-- Downloads pre-built LSP server jar from GitHub artifacts release

local M = {}

local uv = vim.loop

local ARTIFACTS_API = "https://api.github.com/repos/remifan/lf.nvim/releases/tags/artifacts"
local ARTIFACTS_URL = "https://github.com/remifan/lf.nvim/releases/download/artifacts"

-- Where to store the downloaded jar
local function get_install_dir()
  local dir = vim.fn.stdpath("data") .. "/lf-lsp"
  vim.fn.mkdir(dir, "p")
  return dir
end

--- Spawn a command asynchronously, call back with exit code and stdout
local function spawn_collect(cmd, args, callback)
  local stdout_chunks = {}
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)
  local handle

  handle = uv.spawn(cmd, {
    args = args,
    stdio = { nil, stdout, stderr },
  }, function(code)
    stdout:close()
    stderr:close()
    handle:close()
    vim.schedule(function()
      callback(code, table.concat(stdout_chunks))
    end)
  end)

  if not handle then
    return false
  end

  stdout:read_start(function(_, data)
    if data then table.insert(stdout_chunks, data) end
  end)
  stderr:read_start(function() end)
  return true
end

-- Fetch available jar names from the artifacts release
local function fetch_versions(callback)
  if vim.fn.executable("curl") == 0 then
    callback(nil, "curl not found")
    return
  end

  local ok = spawn_collect("curl", { "-fsSL", ARTIFACTS_API }, function(code, output)
    if code ~= 0 then
      callback(nil, "Failed to fetch release info from GitHub")
      return
    end

    local parse_ok, release = pcall(vim.json.decode, output)
    if not parse_ok or type(release) ~= "table" then
      callback(nil, "Failed to parse release JSON")
      return
    end

    local jars = {}
    for _, asset in ipairs(release.assets or {}) do
      local name = asset.name or ""
      if name:match("^lsp%-.*%-all%.jar$") then
        table.insert(jars, name)
      end
    end

    if #jars == 0 then
      callback(nil, "No LSP jars found in artifacts release")
    else
      table.sort(jars)
      callback(jars, nil)
    end
  end)

  if not ok then
    callback(nil, "Failed to spawn curl")
  end
end

-- Download a jar by name
local function download_jar(jar_name, callback)
  local url = ARTIFACTS_URL .. "/" .. jar_name
  local dest = get_install_dir() .. "/" .. jar_name

  -- Check if already downloaded
  if vim.fn.filereadable(dest) == 1 then
    callback(dest, nil)
    return
  end

  vim.notify("[lf.nvim] Downloading " .. jar_name .. "...", vim.log.levels.INFO)

  local ok = spawn_collect("curl", { "-fSL", "-o", dest, url }, function(code)
    if code == 0 then
      callback(dest, nil)
    else
      vim.fn.delete(dest)
      callback(nil, "Download failed (HTTP error)")
    end
  end)

  if not ok then
    callback(nil, "Failed to spawn curl")
  end
end

-- Find currently installed jar
function M.get_installed_jar()
  local dir = get_install_dir()
  local jars = vim.fn.glob(dir .. "/lsp-*-all.jar", false, true)
  if #jars > 0 then
    table.sort(jars)
    return jars[#jars]
  end
  return nil
end

-- Install: fetch available jars, let user pick, download
function M.install(opts)
  opts = opts or {}

  if vim.fn.executable("curl") == 0 then
    vim.notify("[lf.nvim] curl is required for LFLspInstall", vim.log.levels.ERROR)
    return
  end

  vim.notify("[lf.nvim] Fetching available LSP versions...", vim.log.levels.INFO)

  fetch_versions(function(jars, err)
    if err or not jars or #jars == 0 then
      vim.notify("[lf.nvim] No LSP releases found. " .. (err or ""), vim.log.levels.ERROR)
      return
    end

    -- If only one version, use it directly
    if #jars == 1 then
      download_jar(jars[1], function(path, dl_err)
        if dl_err then
          vim.notify("[lf.nvim] " .. dl_err, vim.log.levels.ERROR)
        else
          on_install_complete(path)
        end
      end)
      return
    end

    -- Let user pick
    vim.ui.select(jars, { prompt = "Select LF LSP jar:" }, function(choice)
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
