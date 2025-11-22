-- LSP client configuration for Lingua Franca
-- Manages the connection to the Java-based LF Language Server

local M = {}

M.client_id = nil
M.config = {}

-- Get LSP capabilities with custom LF extensions
local function get_capabilities()
  local capabilities = vim.lsp.protocol.make_client_capabilities()

  -- Add custom LF capabilities
  capabilities.experimental = capabilities.experimental or {}
  capabilities.experimental.linguaFranca = {
    ast = true,
    build = true,
    diagram = true,
    libraryReactors = true,
  }

  -- Merge with user capabilities if provided
  if M.config.capabilities then
    capabilities = vim.tbl_deep_extend("force", capabilities, M.config.capabilities)
  end

  return capabilities
end

-- Custom on_attach handler
local function on_attach(client, bufnr)
  -- Enable completion triggered by <c-x><c-o>
  vim.bo[bufnr].omnifunc = "v:lua.vim.lsp.omnifunc"

  -- Default LSP keybindings
  local opts = { noremap = true, silent = true, buffer = bufnr }

  vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
  vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
  vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
  vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
  vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, opts)
  vim.keymap.set("n", "<leader>wa", vim.lsp.buf.add_workspace_folder, opts)
  vim.keymap.set("n", "<leader>wr", vim.lsp.buf.remove_workspace_folder, opts)
  vim.keymap.set("n", "<leader>wl", function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
  end, opts)
  vim.keymap.set("n", "<leader>D", vim.lsp.buf.type_definition, opts)
  vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
  vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts)
  vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
  vim.keymap.set("n", "<leader>f", function()
    vim.lsp.buf.format({ async = true })
  end, opts)

  -- Call user on_attach if provided
  if M.config.on_attach then
    M.config.on_attach(client, bufnr)
  end
end

-- Build LSP server command
local function build_cmd()
  local cmd = { M.config.java_cmd }

  -- Add Java arguments
  if M.config.java_args and #M.config.java_args > 0 then
    vim.list_extend(cmd, M.config.java_args)
  end

  -- Add JAR path
  table.insert(cmd, "-jar")
  table.insert(cmd, M.config.jar_path)

  return cmd
end

-- Find root directory for LF project
local function find_root_dir()
  -- Look for gradle files, .git, or fallback to current directory
  local root_pattern = vim.fs.root(0, {
    "build.gradle",
    "build.gradle.kts",
    "settings.gradle",
    ".git",
    "src-gen",
  })

  return root_pattern or vim.fn.getcwd()
end

-- Setup LSP configuration
function M.setup(config)
  M.config = config

  -- Register LF filetype if not already registered
  vim.filetype.add({
    extension = {
      lf = "lf",
    },
  })
end

-- Start the LSP client
function M.start()
  -- Don't start if already running
  if M.client_id then
    local client = vim.lsp.get_client_by_id(M.client_id)
    if client then
      return M.client_id
    end
  end

  local cmd = build_cmd()
  local root_dir = find_root_dir()

  -- Start LSP client
  M.client_id = vim.lsp.start({
    name = "lf-language-server",
    cmd = cmd,
    root_dir = root_dir,
    capabilities = get_capabilities(),
    on_attach = on_attach,
    settings = M.config.settings or {},
    filetypes = { "lf" },

    -- Custom handlers for LF-specific notifications
    handlers = {
      -- Suppress window/logMessage to avoid blocking
      ["window/logMessage"] = function(err, result, ctx, config)
        -- Silently ignore log messages from LSP server
      end,
      ["window/showMessage"] = function(err, result, ctx, config)
        -- Silently ignore show messages from LSP server
      end,
      -- Handle library reactor notifications from server
      ["notify/sendLibraryReactors"] = function(err, result, ctx, config)
        if err then
          vim.notify("Failed to receive library reactors: " .. err.message, vim.log.levels.ERROR)
          return
        end
        -- Store library reactors for later use
        local library = require("lf.library")
        library.update_reactors(result)
      end,

      -- Handle diagram updates from LSP server
      ["diagram/accept"] = function(err, result, ctx, config)
        if err then
          vim.notify("Diagram notification error: " .. err.message, vim.log.levels.ERROR)
          return
        end

        -- Forward diagram to browser via sidecar
        -- result should already be an ActionMessage from LSP
        local sidecar = require("lf.sidecar")
        if sidecar.is_running() then
          sidecar.send_action_to_browser(result)
        else
          -- Silently ignore
        end
      end,

      -- Handle jump to source requests from LSP
      ["diagram/openInTextEditor"] = function(err, result, ctx, config)
        if err then
          vim.notify("Error opening text editor: " .. err.message, vim.log.levels.ERROR)
          return
        end

        -- Silently ignore

        -- result should have: { location: { uri: ..., range: ... }, forceOpen: bool }
        if result and result.location then
          local location = result.location
          local uri = location.uri
          local range = location.range

          -- Open file
          local file_path = vim.uri_to_fname(uri)

          -- Use edit or split based on forceOpen
          if result.forceOpen then
            vim.cmd("edit " .. vim.fn.fnameescape(file_path))
          else
            vim.cmd("edit " .. vim.fn.fnameescape(file_path))
          end

          -- Jump to position
          if range and range.start then
            local line = range.start.line + 1  -- LSP is 0-indexed, Vim is 1-indexed
            local col = range.start.character
            vim.api.nvim_win_set_cursor(0, { line, col })
            -- Use DEBUG level to avoid blocking
            -- Silently ignore
          end
        end
      end,

      -- Override default hover to handle IndexOutOfBoundsException gracefully
      ["textDocument/hover"] = function(err, result, ctx, config)
        if err then
          -- Silently ignore IndexOutOfBoundsException from hover
          if err.message and err.message:match("IndexOutOfBoundsException") then
            return
          end
          -- Silently ignore
          return
        end

        return vim.lsp.handlers["textDocument/hover"](err, result, ctx, config)
      end,
    },
  })

  if M.client_id then
    -- Silently ignore
  else
    vim.notify("Failed to start LF Language Server", vim.log.levels.ERROR)
  end

  return M.client_id
end

-- Stop the LSP client
function M.stop()
  if M.client_id then
    vim.lsp.stop_client(M.client_id)
    M.client_id = nil
    -- Silently ignore
  end
end

-- Restart the LSP client
function M.restart()
  M.stop()
  vim.defer_fn(function()
    M.start()
  end, 500)
end

-- Get the active client
function M.get_client()
  if M.client_id then
    return vim.lsp.get_client_by_id(M.client_id)
  end
  return nil
end

-- Execute a custom LSP request
function M.request(method, params, handler)
  local client = M.get_client()
  if not client then
    vim.notify("LF Language Server not running", vim.log.levels.ERROR)
    return
  end

  return client.request(method, params, handler, 0)
end

-- Execute a custom LSP notification
function M.notify_server(method, params)
  local client = M.get_client()
  if not client then
    vim.notify("LF Language Server not running", vim.log.levels.ERROR)
    return
  end

  -- Use rpc.notify instead of client.notify for proper parameter handling
  if client.rpc and client.rpc.notify then
    return client.rpc.notify(method, params)
  else
    -- Fallback to request without expecting a response
    return client.request(method, params, function() end, 0)
  end
end

return M
