-- Treesitter installation for Lingua Franca
-- Provides :LFTSInstall command
-- Downloads pre-built parser from GitHub releases, falls back to local compilation

local M = {}

-- Source paths (where tree-sitter-lf is located) for local fallback
-- Users can override this via setup()
M.config = {
  -- Path to tree-sitter-lf source directory (for local fallback)
  source_path = nil,
  -- Compilers to try (in order) for local fallback
  compilers = { vim.fn.getenv("CC"), "cc", "gcc", "clang" },
}

local uv = vim.loop

local GITHUB_REPO = "remifan/lf.nvim"
local RELEASES_API = "https://api.github.com/repos/" .. GITHUB_REPO .. "/releases"
local RELEASES_URL = "https://github.com/" .. GITHUB_REPO .. "/releases"

-- Detect platform: returns artifact name like "lf-linux-x64.so" and parser lib extension
local function get_platform_info()
  local os_name = vim.loop.os_uname().sysname:lower()
  local arch = vim.loop.os_uname().machine

  local platform, ext
  if os_name == "linux" then
    platform = "linux"
    ext = "so"
  elseif os_name == "darwin" then
    platform = "darwin"
    ext = "so"
  elseif os_name:match("windows") or os_name:match("mingw") then
    platform = "win"
    ext = "dll"
  else
    return nil, nil, nil
  end

  local cpu
  if arch == "x86_64" or arch == "amd64" then
    cpu = "x64"
  elseif arch == "aarch64" or arch == "arm64" then
    cpu = "arm64"
  else
    return nil, nil, nil
  end

  return "lf-" .. platform .. "-" .. cpu .. "." .. ext, ext, platform
end

-- Parser library filename for the current platform (lf.so or lf.dll)
local function parser_lib_name()
  local _, ext = get_platform_info()
  return "lf." .. (ext or "so")
end

-- Get nvim-treesitter parser installation directory
local function get_parser_install_dir()
  -- Try to get from nvim-treesitter config first
  local ok, ts_configs = pcall(require, "nvim-treesitter.configs")
  if ok then
    local install_dir = ts_configs.get_parser_install_dir and ts_configs.get_parser_install_dir()
    if install_dir then
      return install_dir
    end
  end

  -- Look for writable parser directories in runtime path
  local paths = vim.api.nvim_get_runtime_file("parser", true)

  -- Priority order: lazy.nvim > packer > user data dir
  for _, path in ipairs(paths) do
    if path:match("lazy/nvim%-treesitter/parser") then
      local test_file = path .. "/.write_test"
      local f = io.open(test_file, "w")
      if f then
        f:close()
        os.remove(test_file)
        return path
      end
    end
  end

  for _, path in ipairs(paths) do
    if path:match("packer/") or path:match("site/pack/") then
      local test_file = path .. "/.write_test"
      local f = io.open(test_file, "w")
      if f then
        f:close()
        os.remove(test_file)
        return path
      end
    end
  end

  -- Fall back to user data directory (always writable)
  local data_parser = vim.fn.stdpath("data") .. "/parser"
  vim.fn.mkdir(data_parser, "p")
  return data_parser
end

-- Get nvim-treesitter queries directory
local function get_queries_dir()
  local parser_dir = get_parser_install_dir()

  -- If using nvim-treesitter (lazy or packer), queries go in same base
  local base = vim.fn.fnamemodify(parser_dir, ":h")
  local queries_in_ts = base .. "/queries"

  -- Check if that directory exists and is writable
  if vim.fn.isdirectory(queries_in_ts) == 1 then
    local test_dir = queries_in_ts .. "/lf"
    vim.fn.mkdir(test_dir, "p")
    if vim.fn.isdirectory(test_dir) == 1 then
      return queries_in_ts
    end
  end

  -- Fall back to user data directory for queries
  local data_queries = vim.fn.stdpath("data") .. "/site/queries"
  vim.fn.mkdir(data_queries, "p")
  return data_queries
end

-- Find a working C compiler (for local fallback)
local function find_compiler()
  for _, cc in ipairs(M.config.compilers) do
    if cc and type(cc) == "string" and vim.fn.executable(cc) == 1 then
      return cc
    end
  end
  return nil
end

-- Find the tree-sitter-lf source directory (for local fallback)
local function find_source_path()
  if M.config.source_path and vim.fn.isdirectory(M.config.source_path) == 1 then
    return M.config.source_path
  end

  local plugin_path = debug.getinfo(1, "S").source:sub(2)
  local plugin_dir = vim.fn.fnamemodify(plugin_path, ":h:h:h:h")

  local possible_paths = {
    vim.fn.fnamemodify(plugin_dir, ":h") .. "/tree-sitter-lf",
    plugin_dir .. "/tree-sitter-lf",
    vim.fn.expand("~/Workspace/lf.nvim/tree-sitter-lf"),
    vim.fn.getenv("LF_TREESITTER_PATH"),
  }

  for _, path in ipairs(possible_paths) do
    if path and vim.fn.isdirectory(path) == 1 then
      if vim.fn.filereadable(path .. "/grammar.js") == 1 then
        return path
      end
    end
  end

  return nil
end

-- Check if parser is already installed
function M.is_installed()
  local parser_dir = get_parser_install_dir()
  local parser_path = parser_dir .. "/" .. parser_lib_name()
  return vim.fn.filereadable(parser_path) == 1
end

-- Check if queries are installed
function M.queries_installed()
  local queries_dir = get_queries_dir()
  local highlights_path = queries_dir .. "/lf/highlights.scm"
  return vim.fn.filereadable(highlights_path) == 1
end

-- Parse GitHub releases JSON to find the latest ts-* tag
local function parse_ts_tag(json_str)
  local ok, releases = pcall(vim.json.decode, json_str)
  if not ok or type(releases) ~= "table" then
    return nil
  end
  for _, rel in ipairs(releases) do
    local tag = rel.tag_name or ""
    if tag:match("^ts%-") then
      return tag
    end
  end
  return nil
end

--- Spawn a command asynchronously, collect stdout, call back with (code, stdout_str)
---@param cmd string
---@param args string[]
---@param callback fun(code: number, stdout: string)
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

--- Fetch the latest treesitter release tag from GitHub (curl only, no gh required)
---@param callback fun(tag: string|nil, err: string|nil)
local function fetch_latest_ts_tag(callback)
  if vim.fn.executable("curl") == 0 then
    callback(nil, "curl not found")
    return
  end

  local ok = spawn_collect("curl", { "-fsSL", RELEASES_API }, function(code, output)
    if code ~= 0 then
      callback(nil, "Failed to fetch releases from GitHub")
      return
    end
    local tag = parse_ts_tag(output)
    if tag then
      callback(tag, nil)
    else
      callback(nil, "No tree-sitter release found")
    end
  end)

  if not ok then
    callback(nil, "Failed to spawn curl")
  end
end

--- Download a file via curl
---@param url string
---@param dest string
---@param callback fun(ok: boolean, err: string|nil)
local function download_file(url, dest, callback)
  if vim.fn.executable("curl") == 0 then
    callback(false, "curl is required for download")
    return
  end

  local ok = spawn_collect("curl", { "-fSL", "-o", dest, url }, function(code)
    if code == 0 then
      callback(true, nil)
    else
      vim.fn.delete(dest)
      callback(false, "Download failed (HTTP error)")
    end
  end)

  if not ok then
    callback(false, "Failed to spawn curl")
  end
end

--- Download parser binary and queries from GitHub, then install
---@param callback fun(ok: boolean, err: string|nil)
local function install_from_github(callback)
  local artifact = get_platform_info()
  if not artifact then
    callback(false, "Unsupported platform")
    return
  end

  vim.notify("[lf.nvim] Fetching latest tree-sitter release...", vim.log.levels.INFO)

  fetch_latest_ts_tag(function(tag, err)
    if not tag then
      callback(false, err or "No release found")
      return
    end

    local lib_name = parser_lib_name()
    local parser_dir = get_parser_install_dir()
    local parser_output = parser_dir .. "/" .. lib_name
    vim.fn.mkdir(parser_dir, "p")

    local parser_url = RELEASES_URL .. "/download/" .. tag .. "/" .. artifact
    local queries_url = RELEASES_URL .. "/download/" .. tag .. "/queries.tar.gz"

    -- Use a temp dir for downloads
    local tmp_dir = vim.fn.tempname()
    vim.fn.mkdir(tmp_dir, "p")
    local tmp_parser = tmp_dir .. "/" .. lib_name
    local tmp_queries = tmp_dir .. "/queries.tar.gz"

    vim.notify("[lf.nvim] Downloading parser (" .. tag .. ")...", vim.log.levels.INFO)

    download_file(parser_url, tmp_parser, function(p_ok, p_err)
      if not p_ok then
        vim.fn.delete(tmp_dir, "rf")
        callback(false, "Parser download failed: " .. (p_err or ""))
        return
      end

      download_file(queries_url, tmp_queries, function(q_ok, q_err)
        if not q_ok then
          vim.fn.delete(tmp_dir, "rf")
          callback(false, "Queries download failed: " .. (q_err or ""))
          return
        end

        -- Install parser binary
        local content = vim.fn.readblob(tmp_parser)
        if vim.fn.writefile(content, parser_output, "b") ~= 0 then
          vim.fn.delete(tmp_dir, "rf")
          callback(false, "Failed to write parser to " .. parser_output)
          return
        end
        vim.fn.setfperm(parser_output, "rwxr-xr-x")

        -- Extract queries
        local queries_dst = get_queries_dir() .. "/lf"
        vim.fn.mkdir(queries_dst, "p")
        local tar_ret = os.execute("tar xzf " .. vim.fn.shellescape(tmp_queries) .. " -C " .. vim.fn.shellescape(queries_dst))

        vim.fn.delete(tmp_dir, "rf")

        if tar_ret ~= 0 then
          callback(false, "Failed to extract queries")
          return
        end

        callback(true, nil)
      end)
    end)
  end)
end

-- Compile the parser from local source (fallback)
local function compile_parser(source_path, output_path, callback)
  local cc = find_compiler()
  if not cc then
    callback(false, "No C compiler found. Please install gcc or clang.")
    return
  end

  local parser_c = source_path .. "/src/parser.c"
  local scanner_c = source_path .. "/src/scanner.c"

  if vim.fn.filereadable(parser_c) == 0 then
    callback(false, "parser.c not found. Run 'npx tree-sitter generate' in " .. source_path)
    return
  end

  local src_files = { parser_c }
  if vim.fn.filereadable(scanner_c) == 1 then
    table.insert(src_files, scanner_c)
  end

  local args = {
    "-shared",
    "-o", output_path,
    "-fPIC",
    "-I" .. source_path .. "/src",
    "-O2",
  }
  for _, src in ipairs(src_files) do
    table.insert(args, src)
  end

  vim.notify("[lf.nvim] Compiling parser with " .. cc .. "...", vim.log.levels.INFO)

  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)
  local error_output = ""

  local handle
  handle = uv.spawn(cc, {
    args = args,
    stdio = { nil, stdout, stderr },
  }, function(code)
    stdout:close()
    stderr:close()
    handle:close()

    vim.schedule(function()
      if code == 0 then
        callback(true, nil)
      else
        callback(false, "Compilation failed: " .. error_output)
      end
    end)
  end)

  if not handle then
    callback(false, "Failed to spawn compiler: " .. cc)
    return
  end

  stderr:read_start(function(_, data)
    if data then
      error_output = error_output .. data
    end
  end)
end

-- Copy query files from local source (fallback)
local function copy_queries(source_path, callback)
  local queries_src = source_path .. "/queries"
  local queries_dst = get_queries_dir() .. "/lf"
  vim.fn.mkdir(queries_dst, "p")

  local query_files = {
    "highlights.scm",
    "locals.scm",
    "textobjects.scm",
    "folds.scm",
    "indents.scm",
    "injections.scm",
  }

  local errors = {}
  for _, qf in ipairs(query_files) do
    local src = queries_src .. "/" .. qf
    local dst = queries_dst .. "/" .. qf

    if vim.fn.filereadable(src) == 1 then
      local content = vim.fn.readfile(src)
      local ok = vim.fn.writefile(content, dst)
      if ok ~= 0 then
        table.insert(errors, "Failed to copy " .. qf)
      end
    end
  end

  if #errors > 0 then
    callback(false, table.concat(errors, "\n"))
  else
    callback(true, nil)
  end
end

-- Install from local source (pre-compiled binary or compile from scratch)
local function install_from_local(source_path, opts, callback)
  local lib_name = parser_lib_name()
  local parser_dir = get_parser_install_dir()
  local parser_output = parser_dir .. "/" .. lib_name
  vim.fn.mkdir(parser_dir, "p")

  -- Check if pre-compiled parser exists in source
  local precompiled = source_path .. "/" .. lib_name
  if vim.fn.filereadable(precompiled) == 1 and not opts.compile then
    vim.notify("[lf.nvim] Copying pre-compiled parser...", vim.log.levels.INFO)
    local content = vim.fn.readblob(precompiled)
    if vim.fn.writefile(content, parser_output, "b") == 0 then
      vim.fn.setfperm(parser_output, "rwxr-xr-x")
      copy_queries(source_path, callback)
      return
    end
  end

  -- Compile from source
  compile_parser(source_path, parser_output, function(ok, err)
    if not ok then
      callback(false, err)
      return
    end
    vim.fn.setfperm(parser_output, "rwxr-xr-x")
    copy_queries(source_path, callback)
  end)
end

local function on_install_success()
  vim.notify("[lf.nvim] LF treesitter parser installed successfully!", vim.log.levels.INFO)
  pcall(function()
    vim._ts_remove_language("lf")
    vim.treesitter.language.add("lf")
  end)
end

-- Main install function
function M.install(opts)
  opts = opts or {}
  local force = opts.force or false

  -- Check if already installed
  if M.is_installed() and M.queries_installed() and not force then
    vim.notify("[lf.nvim] LF treesitter parser is already installed. Use :LFTSInstall! to reinstall.", vim.log.levels.INFO)
    return
  end

  -- Try GitHub download first
  install_from_github(function(ok, err)
    if ok then
      on_install_success()
      return
    end

    local gh_err = err or "unknown"

    -- Fall back to local source
    local source_path = find_source_path()
    if not source_path then
      vim.notify(
        "[lf.nvim] Could not download from GitHub (" .. gh_err .. ") and no local source found.\n\n" ..
        "Ensure you have internet access, or set the local source path:\n" ..
        "  require('lf.treesitter').setup({ source_path = '/path/to/tree-sitter-lf' })\n\n" ..
        "Or set the LF_TREESITTER_PATH environment variable.",
        vim.log.levels.ERROR
      )
      return
    end

    vim.notify("[lf.nvim] GitHub download failed (" .. gh_err .. "), falling back to local source: " .. source_path, vim.log.levels.WARN)

    install_from_local(source_path, opts, function(lok, lerr)
      if lok then
        on_install_success()
      else
        vim.notify("[lf.nvim] " .. (lerr or "Unknown error"), vim.log.levels.ERROR)
      end
    end)
  end)
end

-- Uninstall the parser
function M.uninstall()
  local parser_dir = get_parser_install_dir()
  local parser_path = parser_dir .. "/" .. parser_lib_name()
  local queries_dir = get_queries_dir() .. "/lf"

  local removed = false

  if vim.fn.filereadable(parser_path) == 1 then
    vim.fn.delete(parser_path)
    removed = true
  end

  if vim.fn.isdirectory(queries_dir) == 1 then
    vim.fn.delete(queries_dir, "rf")
    removed = true
  end

  -- Also clean up any stale queries in site directory (legacy location)
  local site_queries = vim.fn.stdpath("data") .. "/site/queries/lf"
  if vim.fn.isdirectory(site_queries) == 1 then
    vim.fn.delete(site_queries, "rf")
    removed = true
  end

  if removed then
    vim.notify("[lf.nvim] LF treesitter parser uninstalled.", vim.log.levels.INFO)
    pcall(vim._ts_remove_language, "lf")
  else
    vim.notify("[lf.nvim] LF treesitter parser was not installed.", vim.log.levels.WARN)
  end
end

-- Show installation status
function M.status()
  local parser_dir = get_parser_install_dir()
  local queries_dir = get_queries_dir()

  local lines = {
    "LF Treesitter Status",
    "====================",
    "",
    "Parser directory: " .. parser_dir,
    "Parser installed: " .. (M.is_installed() and "Yes" or "No"),
    "",
    "Queries directory: " .. queries_dir .. "/lf",
    "Queries installed: " .. (M.queries_installed() and "Yes" or "No"),
    "",
    "Source path: " .. (find_source_path() or "Not found"),
    "Platform artifact: " .. (get_platform_info() or "Unsupported"),
  }

  -- Check individual query files
  if M.queries_installed() then
    table.insert(lines, "")
    table.insert(lines, "Query files:")
    local query_files = { "highlights.scm", "locals.scm", "textobjects.scm", "folds.scm", "indents.scm", "injections.scm" }
    for _, qf in ipairs(query_files) do
      local path = queries_dir .. "/lf/" .. qf
      local status = vim.fn.filereadable(path) == 1 and "✓" or "✗"
      table.insert(lines, "  " .. status .. " " .. qf)
    end
  end

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

-- Setup function to configure the module
function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", M.config, opts)
end

-- Command definitions (called from commands.lua)
M.commands = {
  LFInstall = {
    run = function() M.install({ force = false }) end,
    ["run!"] = function() M.install({ force = true }) end,
    args = { "-bang" },
    desc = "Install LF treesitter parser and queries",
  },
  LFUninstall = {
    run = M.uninstall,
    args = {},
    desc = "Uninstall LF treesitter parser and queries",
  },
  LFTSStatus = {
    run = M.status,
    args = {},
    desc = "Show LF treesitter installation status",
  },
}

return M
