-- Treesitter installation for Lingua Franca
-- Provides :LFInstall command similar to :TSInstall

local M = {}

-- Source paths (where tree-sitter-lf is located)
-- Users can override this via setup()
M.config = {
  -- Path to tree-sitter-lf source directory
  source_path = nil,
  -- Compilers to try (in order)
  compilers = { vim.fn.getenv("CC"), "cc", "gcc", "clang" },
}

local uv = vim.loop

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
    -- Prefer the lazy.nvim managed path (most common modern setup)
    if path:match("lazy/nvim%-treesitter/parser") then
      -- Check if writable
      local test_file = path .. "/.write_test"
      local f = io.open(test_file, "w")
      if f then
        f:close()
        os.remove(test_file)
        return path
      end
    end
  end

  -- Try packer path
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
  -- Neovim looks for queries in runtime path, so we use after/queries
  local data_queries = vim.fn.stdpath("data") .. "/site/queries"
  vim.fn.mkdir(data_queries, "p")
  return data_queries
end

-- Find a working C compiler
local function find_compiler()
  for _, cc in ipairs(M.config.compilers) do
    if cc and type(cc) == "string" and vim.fn.executable(cc) == 1 then
      return cc
    end
  end
  return nil
end

-- Find the tree-sitter-lf source directory
local function find_source_path()
  if M.config.source_path and vim.fn.isdirectory(M.config.source_path) == 1 then
    return M.config.source_path
  end

  -- Try common locations relative to this plugin
  local plugin_path = debug.getinfo(1, "S").source:sub(2)
  local plugin_dir = vim.fn.fnamemodify(plugin_path, ":h:h:h:h") -- Go up to lf.nvim root

  local possible_paths = {
    -- Sibling directory (lf.nvim/../tree-sitter-lf)
    vim.fn.fnamemodify(plugin_dir, ":h") .. "/tree-sitter-lf",
    -- Inside plugin (lf.nvim/tree-sitter-lf)
    plugin_dir .. "/tree-sitter-lf",
    -- User's workspace
    vim.fn.expand("~/Workspace/lf.nvim/tree-sitter-lf"),
    -- Environment variable
    vim.fn.getenv("LF_TREESITTER_PATH"),
  }

  for _, path in ipairs(possible_paths) do
    if path and vim.fn.isdirectory(path) == 1 then
      -- Verify it has grammar.js
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
  local parser_path = parser_dir .. "/lf.so"
  return vim.fn.filereadable(parser_path) == 1
end

-- Check if queries are installed
function M.queries_installed()
  local queries_dir = get_queries_dir()
  local highlights_path = queries_dir .. "/lf/highlights.scm"
  return vim.fn.filereadable(highlights_path) == 1
end

-- Compile the parser from source
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

  -- Build compile command
  local src_files = { parser_c }
  if vim.fn.filereadable(scanner_c) == 1 then
    table.insert(src_files, scanner_c)
  end

  local args = {
    "-shared",
    "-o", output_path,
    "-fPIC",
    "-I" .. source_path .. "/src",
  }

  -- Add optimization flags
  table.insert(args, "-O2")

  -- Add source files
  for _, src in ipairs(src_files) do
    table.insert(args, src)
  end

  vim.notify("[lf.nvim] Compiling parser with " .. cc .. "...", vim.log.levels.INFO)

  -- Run compiler asynchronously
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

  stderr:read_start(function(err, data)
    if data then
      error_output = error_output .. data
    end
  end)
end

-- Copy query files
local function copy_queries(source_path, callback)
  local queries_src = source_path .. "/queries"
  local queries_dst = get_queries_dir() .. "/lf"

  -- Create destination directory
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
    else
      -- Not an error if optional query file doesn't exist
    end
  end

  if #errors > 0 then
    callback(false, table.concat(errors, "\n"))
  else
    callback(true, nil)
  end
end

-- Main install function
function M.install(opts)
  opts = opts or {}
  local force = opts.force or false

  -- Check if already installed
  if M.is_installed() and M.queries_installed() and not force then
    vim.notify("[lf.nvim] LF treesitter parser is already installed. Use :LFInstall! to reinstall.", vim.log.levels.INFO)
    return
  end

  -- Find source path
  local source_path = find_source_path()
  if not source_path then
    vim.notify(
      "[lf.nvim] tree-sitter-lf source not found.\n\n" ..
      "Please set the source path:\n" ..
      "  require('lf.treesitter').setup({ source_path = '/path/to/tree-sitter-lf' })\n\n" ..
      "Or set the LF_TREESITTER_PATH environment variable.",
      vim.log.levels.ERROR
    )
    return
  end

  vim.notify("[lf.nvim] Installing LF treesitter parser from: " .. source_path, vim.log.levels.INFO)

  local parser_dir = get_parser_install_dir()
  local parser_output = parser_dir .. "/lf.so"

  -- Ensure parser directory exists
  vim.fn.mkdir(parser_dir, "p")

  -- Check if pre-compiled parser exists in source
  local precompiled = source_path .. "/lf.so"
  if vim.fn.filereadable(precompiled) == 1 and not opts.compile then
    -- Copy pre-compiled parser
    vim.notify("[lf.nvim] Copying pre-compiled parser...", vim.log.levels.INFO)
    local content = vim.fn.readblob(precompiled)
    if vim.fn.writefile(content, parser_output, "b") == 0 then
      -- Make executable
      vim.fn.setfperm(parser_output, "rwxr-xr-x")

      -- Copy queries
      copy_queries(source_path, function(ok, err)
        if ok then
          vim.notify("[lf.nvim] LF treesitter parser installed successfully!", vim.log.levels.INFO)
          -- Try to reload the parser
          pcall(function()
            vim._ts_remove_language("lf")
            vim.treesitter.language.add("lf")
          end)
        else
          vim.notify("[lf.nvim] Parser installed but query copy failed: " .. (err or "unknown error"), vim.log.levels.WARN)
        end
      end)
      return
    end
  end

  -- Compile from source
  compile_parser(source_path, parser_output, function(ok, err)
    if not ok then
      vim.notify("[lf.nvim] " .. (err or "Unknown compilation error"), vim.log.levels.ERROR)
      return
    end

    -- Make executable
    vim.fn.setfperm(parser_output, "rwxr-xr-x")

    -- Copy queries
    copy_queries(source_path, function(qok, qerr)
      if qok then
        vim.notify("[lf.nvim] LF treesitter parser installed successfully!", vim.log.levels.INFO)
        -- Try to reload the parser
        pcall(function()
          vim._ts_remove_language("lf")
          vim.treesitter.language.add("lf")
        end)
      else
        vim.notify("[lf.nvim] Parser compiled but query copy failed: " .. (qerr or "unknown error"), vim.log.levels.WARN)
      end
    end)
  end)
end

-- Uninstall the parser
function M.uninstall()
  local parser_dir = get_parser_install_dir()
  local parser_path = parser_dir .. "/lf.so"
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
