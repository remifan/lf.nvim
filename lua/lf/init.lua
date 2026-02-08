-- lf.nvim - Lingua Franca plugin for Neovim
-- Main entry point and setup function

local M = {}

-- Default configuration
M.config = {
  -- Enable LSP features (requires Mac/Linux, disabled on Windows)
  -- When false, only syntax highlighting is enabled
  enable_lsp = true,

  -- Syntax highlighting configuration (always available)
  syntax = {
    target_language = nil, -- "C" | "Cpp" | "Python" | "Rust" | "TypeScript"
    auto_detect_target = true,
    indent = {
      size = 4,
      use_tabs = false,
    },
  },

  -- LSP configuration (only when enable_lsp = true and on Mac/Linux)
  lsp = {
    jar_path = nil, -- Path to lsp-all.jar (will try common locations if nil)
    java_cmd = "java",
    java_args = { "-Xmx2G" },
    auto_start = true,
    on_attach = nil,
    capabilities = nil,
    settings = {},
  },
  build = {
    auto_validate = true,
    show_progress = true,
    open_quickfix = true,
  },
  ui = {
    use_telescope = true,
    progress_style = "notify", -- "notify" or "echo"
  },
  keymaps = {
    build = "<leader>lb",
    run = "<leader>lr",
    show_ast = "<leader>la",
    library = "<leader>ll",
    diagram = "<leader>ld",
  },
  diagram = {
    -- Don't auto-open browser (useful for SSH)
    no_browser = true,
    -- Auto-update diagram when switching files (requires diagram viewer to be open)
    auto_update = true,
  },
}

-- Merge user config with defaults
local function merge_config(user_config)
  if not user_config then
    return M.config
  end

  local config = vim.tbl_deep_extend("force", M.config, user_config)
  return config
end

-- Try to find LSP JAR in common locations
local function find_lsp_jar()
  -- First, check environment variable LF_LSP_JAR
  local env_jar = vim.env.LF_LSP_JAR
  if env_jar and vim.fn.filereadable(env_jar) == 1 then
    return env_jar
  end

  -- If env var is set but invalid, expand it (might contain wildcards)
  if env_jar then
    local expanded = vim.fn.glob(vim.fn.expand(env_jar), false, true)
    if #expanded > 0 and vim.fn.filereadable(expanded[1]) == 1 then
      return expanded[1]
    end
  end

  -- Fall back to common paths
  local common_paths = {
    -- User's home build
    vim.fn.expand("~/lingua-franca/lsp/build/libs/lsp-*-all.jar"),
    -- Current directory build
    vim.fn.getcwd() .. "/lsp/build/libs/lsp-*-all.jar",
    -- Parent directory build
    vim.fn.fnamemodify(vim.fn.getcwd(), ":h") .. "/lingua-franca/lsp/build/libs/lsp-*-all.jar",
  }

  for _, path_pattern in ipairs(common_paths) do
    local jars = vim.fn.glob(path_pattern, false, true)
    if #jars > 0 then
      return jars[1]
    end
  end

  return nil
end

-- Validate configuration
local function validate_config(config)
  -- Check if Java is available
  if vim.fn.executable(config.lsp.java_cmd) == 0 then
    vim.notify(
      string.format("lf.nvim: Java command not found: %s", config.lsp.java_cmd),
      vim.log.levels.ERROR
    )
    return false
  end

  -- If jar_path is explicitly set, validate it
  if config.lsp.jar_path then
    if vim.fn.filereadable(config.lsp.jar_path) == 0 then
      vim.notify(
        string.format("lf.nvim: LSP JAR not found at: %s", config.lsp.jar_path),
        vim.log.levels.ERROR
      )
      return false
    end
  else
    -- Try to find JAR automatically
    local found_jar = find_lsp_jar()
    if found_jar then
      config.lsp.jar_path = found_jar
      -- Silently set JAR path, message available in :messages if needed
    else
      vim.notify(
        "lf.nvim: LSP JAR not found. Please build and configure it.\n\n" ..
        "Build LSP server:\n" ..
        "  cd /path/to/lingua-franca\n" ..
        "  ./gradlew buildLsp\n\n" ..
        "Then configure in your Neovim config:\n" ..
        "  lsp = {\n" ..
        "    jar_path = vim.fn.expand('~/path/to/lingua-franca/lsp/build/libs/lsp-*-all.jar')\n" ..
        "  }",
        vim.log.levels.ERROR
      )
      return false
    end
  end

  return true
end

-- Setup keymaps for LF buffers
local function setup_keymaps(bufnr)
  local config = M.config
  if not config.keymaps then
    return
  end

  local opts = { noremap = true, silent = true, buffer = bufnr }

  if config.keymaps.build then
    vim.keymap.set("n", config.keymaps.build, "<cmd>LFBuild<CR>", opts)
  end
  if config.keymaps.run then
    vim.keymap.set("n", config.keymaps.run, "<cmd>LFRun<CR>", opts)
  end
  if config.keymaps.show_ast then
    vim.keymap.set("n", config.keymaps.show_ast, "<cmd>LFShowAST<CR>", opts)
  end
  if config.keymaps.library then
    vim.keymap.set("n", config.keymaps.library, "<cmd>LFLibrary<CR>", opts)
  end
  if config.keymaps.diagram then
    vim.keymap.set("n", config.keymaps.diagram, "<cmd>LFDiagram<CR>", opts)
  end
end

-- Setup autocmds for LF files
local function setup_autocmds()
  local augroup = vim.api.nvim_create_augroup("LFNvim", { clear = true })

  -- Auto-validate on save if enabled
  if M.config.build.auto_validate then
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = augroup,
      pattern = "*.lf",
      callback = function(ev)
        local build = require("lf.build")
        build.partial_build(ev.buf)
      end,
    })
  end

  -- Setup keymaps when entering LF buffer
  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = "lf",
    callback = function(args)
      setup_keymaps(args.buf)
    end,
  })

  -- Auto-update diagram when switching to LF buffer (if diagram viewer is open)
  if M.config.diagram.auto_update then
    vim.api.nvim_create_autocmd("BufEnter", {
      group = augroup,
      pattern = "*.lf",
      callback = function()
        -- Only update if diagram viewer is already running
        local sidecar = require("lf.sidecar")
        if sidecar.is_running() then
          local diagram_klighd = require("lf.diagram_klighd")
          -- Small delay to let buffer fully load
          vim.defer_fn(function()
            diagram_klighd.request_diagram_for_current_file()
          end, 100)
        end
      end,
    })
  end
end

-- Check if platform supports LSP (Mac/Linux only, LF doesn't support Windows)
local function is_lsp_supported()
  return vim.fn.has("mac") == 1 or vim.fn.has("unix") == 1
end

-- Setup syntax highlighting (always available)
local function setup_syntax()
  local lf_nvim = require("lf_nvim")
  lf_nvim.setup(M.config.syntax)
end

-- Main setup function
function M.setup(user_config)
  -- Merge configuration
  M.config = merge_config(user_config)

  -- Always setup syntax highlighting first
  setup_syntax()

  -- Always setup commands (LFInstall, etc. should always be available)
  require("lf.commands").setup()

  -- Check if LSP features should be enabled
  if not M.config.enable_lsp then
    -- Syntax-only mode
    return
  end

  -- Check platform support for LSP features
  if not is_lsp_supported() then
    vim.notify(
      "lf.nvim: LSP features are only supported on Mac and Linux (Lingua Franca doesn't support Windows). Using syntax highlighting only.",
      vim.log.levels.WARN
    )
    return
  end

  -- Validate configuration
  if not validate_config(M.config) then
    -- If LSP validation fails, still have syntax highlighting
    return
  end

  -- Initialize LSP
  local lsp = require("lf.lsp")
  lsp.setup(M.config.lsp)

  -- Setup autocmds
  setup_autocmds()

  -- Auto-start LSP if enabled
  if M.config.lsp.auto_start then
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "lf",
      callback = function()
        lsp.start()
      end,
    })
  end
end

-- Get current config
function M.get_config()
  return M.config
end

return M
