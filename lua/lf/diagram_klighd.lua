-- Full KLighD/Sprotty integration for interactive diagrams
-- This is the "Pro" mode that matches VSCode functionality
-- V2 Architecture: Uses Node sidecar + Neovim LSP client

local M = {}

-- Get the plugin path
local function get_plugin_path()
  return vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h")
end

-- Get cache file path for tracking build status
local function get_build_cache_file()
  local cache_dir = vim.fn.stdpath("cache") .. "/lf.nvim"
  vim.fn.mkdir(cache_dir, "p")
  return cache_dir .. "/diagram-built"
end

-- Check if dependencies are already built
local function is_built()
  local plugin_path = get_plugin_path()
  local sidecar_dist = plugin_path .. "/diagram-server/dist/server.js"
  local frontend_dist = plugin_path .. "/html/dist"

  return vim.fn.filereadable(sidecar_dist) == 1 and vim.fn.isdirectory(frontend_dist) == 1
end

-- Build diagram dependencies
function M.build_dependencies()
  local plugin_path = get_plugin_path()

  vim.notify("Building diagram dependencies (first time setup)...\nThis may take a few minutes.", vim.log.levels.INFO)

  -- Build diagram-server
  local sidecar_dir = plugin_path .. "/diagram-server"
  vim.notify("Building diagram server...", vim.log.levels.INFO)

  local server_build_cmd = string.format(
    "cd %s && npm install && npm run build",
    vim.fn.shellescape(sidecar_dir)
  )

  local server_result = vim.fn.system(server_build_cmd)
  if vim.v.shell_error ~= 0 then
    vim.notify(
      "Failed to build diagram server:\n" .. server_result ..
      "\n\nPlease run manually:\ncd " .. sidecar_dir .. " && npm install && npm run build",
      vim.log.levels.ERROR
    )
    return false
  end

  -- Build html frontend
  local html_dir = plugin_path .. "/html"
  vim.notify("Building diagram frontend...", vim.log.levels.INFO)

  local html_build_cmd = string.format(
    "cd %s && npm install && npm run build",
    vim.fn.shellescape(html_dir)
  )

  local html_result = vim.fn.system(html_build_cmd)
  if vim.v.shell_error ~= 0 then
    vim.notify(
      "Failed to build diagram frontend:\n" .. html_result ..
      "\n\nPlease run manually:\ncd " .. html_dir .. " && npm install && npm run build",
      vim.log.levels.ERROR
    )
    return false
  end

  -- Mark as built in cache
  local cache_file = get_build_cache_file()
  local f = io.open(cache_file, "w")
  if f then
    f:write(os.time())
    f:close()
  end

  vim.notify("Diagram dependencies built successfully!", vim.log.levels.INFO)
  return true
end

-- Ensure dependencies are built (auto-build on first use)
local function ensure_dependencies_built()
  -- Check if already built
  if is_built() then
    return true
  end

  -- Check if we've already tried building this session (avoid infinite loops)
  local cache_file = get_build_cache_file()
  if vim.fn.filereadable(cache_file) == 1 then
    -- Cache exists but build is not complete - previous build failed
    vim.notify(
      "Diagram dependencies are not built.\nPrevious build may have failed.\nUse :LFDiagramBuild to try again.",
      vim.log.levels.WARN
    )
    return false
  end

  -- Auto-build
  return M.build_dependencies()
end

-- Check if required dependencies are available
function M.check_dependencies()
  local errors = {}

  -- Check Node.js
  local node_check = vim.fn.system("node --version 2>&1")
  if vim.v.shell_error ~= 0 then
    table.insert(errors, "Node.js not installed. Required for diagram sidecar.")
  end

  -- Check if sidecar is built
  local plugin_path = get_plugin_path()
  local sidecar_dir = plugin_path .. "/diagram-server"
  local sidecar_dist = sidecar_dir .. "/dist/server.js"
  if vim.fn.filereadable(sidecar_dist) == 0 then
    table.insert(errors, "Sidecar not built. Run: cd " .. sidecar_dir .. " && npm install && npm run build")
  end

  -- Check if frontend is built
  local dist_dir = plugin_path .. "/html/dist"
  if vim.fn.isdirectory(dist_dir) == 0 then
    table.insert(errors, "Frontend not built. Run: cd " .. plugin_path .. "/html && npm install && npm run build")
  end

  -- Check LSP is running
  local lsp_clients = vim.lsp.get_clients and vim.lsp.get_clients() or vim.lsp.get_active_clients()
  local has_lf_lsp = false
  for _, client in ipairs(lsp_clients) do
    if client.name == "lf-language-server" then
      has_lf_lsp = true
      break
    end
  end
  if not has_lf_lsp then
    table.insert(errors, "LF LSP not running. LSP must be active for diagrams.")
  end

  return #errors == 0, errors
end

-- Open full KLighD diagram
function M.open()
  -- Check if we have a valid LF file
  local filetype = vim.bo.filetype
  if filetype ~= "lf" then
    -- Silently ignore
    return
  end

  local current_file = vim.fn.expand("%:p")
  if current_file == "" then
    -- Silently ignore
    return
  end

  -- Ensure dependencies are built (auto-build on first use)
  if not ensure_dependencies_built() then
    return
  end

  -- Check other dependencies (Node.js, LSP)
  local ok, errors = M.check_dependencies()
  if not ok then
    vim.notify(
      "KLighD dependencies not met:\n" .. table.concat(errors, "\n"),
      vim.log.levels.ERROR
    )
    return
  end

  -- Start sidecar
  local sidecar = require("lf.sidecar")
  if not sidecar.is_running() then
    if not sidecar.start() then
      vim.notify("Failed to start diagram sidecar", vim.log.levels.ERROR)
      return
    end
  end

  -- Wait for sidecar to be ready, then open browser
  -- The browser will send RequestModelAction which triggers diagram generation
  vim.defer_fn(function()
    local uri = vim.uri_from_fname(current_file)
    local port = sidecar.get_http_port()
    local url = string.format("http://localhost:%d/?file=%s", port, uri)

    -- Silently ignore

    local browser_cmd
    if vim.fn.has("mac") == 1 then
      browser_cmd = "open"
    elseif vim.fn.has("unix") == 1 then
      browser_cmd = "xdg-open"
    else
      vim.notify("Could not detect browser command", vim.log.levels.ERROR)
      return
    end

    vim.fn.jobstart({ browser_cmd, url }, { detach = true })
    -- Silently ignore

    -- Enable diagram sync (cursor tracking)
    vim.defer_fn(function()
      local sync = require("lf.diagram_sync")
      sync.set_enabled(true)
      -- Silently ignore
    end, 1000)
  end, 3000)
end

-- Request diagram from LSP server
---@param file_path string
function M.request_diagram(file_path)
  local uri = vim.uri_from_fname(file_path)

  -- Get the LF LSP client
  local client = nil
  local lsp_clients = vim.lsp.get_clients and vim.lsp.get_clients() or vim.lsp.get_active_clients()
  for _, c in ipairs(lsp_clients) do
    if c.name == "lf-language-server" then
      client = c
      break
    end
  end

  if not client then
    vim.notify("LF LSP client not found", vim.log.levels.ERROR)
    return
  end

  -- Silently ignore

  -- Send workspace/executeCommand to generate diagram
  local params = {
    command = "diagram/generate",
    arguments = { uri }
  }

  client.request("workspace/executeCommand", params, function(err, result)
    if err then
      vim.notify("Diagram request failed: " .. vim.inspect(err), vim.log.levels.ERROR)
      return
    end

    if result then
      -- Silently ignore

      -- Send diagram model to browser via sidecar
      local sidecar = require("lf.sidecar")
      sidecar.send_action_to_browser({
        clientId = uri,
        action = result  -- result should be a SetModelAction
      })
    end
  end, 0)  -- buffer 0 = current buffer
end

-- Parse element ID to extract symbol path
---@param element_id string
---@return table|nil symbol_path Array of symbol names from root to target
local function parse_element_id(element_id)
  -- Element IDs have different formats:
  -- - Reactor instance: "$root$Nmain_main$Nmain_h" → ["h"] (just the instance name)
  -- - Reaction inside: "$root$Nmain_main$Nmain_w$Nmain_w_reaction_1" → ["w", "reaction_1"]
  -- - Port inside: "$root$Nmain_main$Nmain_w$Nmain_w_in" → ["w", "in"]

  local parts = vim.split(element_id, "$N")
  if #parts == 0 then
    return nil
  end

  -- Get the last part which contains the instance/element name
  local last_part = parts[#parts]
  local segments = vim.split(last_part, "_")

  if #segments == 0 then
    return nil
  end

  -- For reactor instances at top level (e.g., "$root$Nmain_main$Nmain_w"):
  -- - parts = ["$root", "main_main", "main_w"]
  -- - If we have exactly 3 parts, it's a top-level instance
  -- - Just return the instance name

  if #parts == 3 then
    -- Top-level reactor instance - just return the instance name
    local instance_name = segments[#segments]
    return { instance_name }
  end

  -- For nested elements (reactions, ports inside instances):
  -- - parts has 4+ elements
  -- - e.g., "$root$Nmain_main$Nmain_w$Nmain_w_reaction_1"
  if #parts >= 4 then
    local prev_part = parts[#parts - 1]
    local prev_segments = vim.split(prev_part, "_")
    local parent_instance = prev_segments[#prev_segments]
    local instance_name = segments[#segments]

    return { parent_instance, instance_name }
  end

  -- Fallback
  local instance_name = segments[#segments]
  return { instance_name }
end

-- Jump to symbol using LSP document symbols
---@param symbol_path table Array of symbol names (e.g., {"w"} or {"w", "reaction_1"})
---@param callback function|nil Optional callback after jump completes
local function jump_to_symbol_lsp(symbol_path, callback)
  -- Get the LF LSP client
  local lsp_clients = vim.lsp.get_clients and vim.lsp.get_clients() or vim.lsp.get_active_clients()
  local client = nil
  for _, c in ipairs(lsp_clients) do
    if c.name == "lf-language-server" then
      client = c
      break
    end
  end

  if not client then
    vim.notify("LF LSP client not found for jump-to-source", vim.log.levels.ERROR)
    return
  end

  -- Request document symbols
  local params = { textDocument = vim.lsp.util.make_text_document_params() }
  client.request('textDocument/documentSymbol', params, function(err, result)
    if err or not result then
      vim.schedule(function()
        vim.notify("Failed to get document symbols: " .. (err and err.message or "no result"), vim.log.levels.ERROR)
      end)
      return
    end

    -- Navigate through the symbol path
    -- For ["w"], find "w" at top level
    -- For ["w", "reaction_1"], find "w" then find "reaction_1" in its children
    local current_symbols = result
    local target_symbol = nil

    for i, name in ipairs(symbol_path) do
      local found = nil

      for _, symbol in ipairs(current_symbols) do
        -- Match by name or partial name (e.g., "reaction" might match "reaction(in)")
        if symbol.name == name or symbol.name:match("^" .. vim.pesc(name)) then
          found = symbol
          break
        end
      end

      if not found then
        vim.schedule(function()
          vim.notify("Could not find symbol: " .. name .. " (path: " .. table.concat(symbol_path, " > ") .. ")", vim.log.levels.WARN)
        end)
        return
      end

      if i == #symbol_path then
        -- This is the target
        target_symbol = found
      else
        -- Continue searching in children
        current_symbols = found.children or {}
      end
    end

    if not target_symbol then
      vim.schedule(function()
        vim.notify("Could not resolve symbol path: " .. table.concat(symbol_path, " > "), vim.log.levels.WARN)
      end)
      return
    end

    -- Jump to the target symbol
    vim.schedule(function()
      local range = target_symbol.location and target_symbol.location.range or target_symbol.range
      if range and range.start then
        local line = range.start.line + 1
        local col = range.start.character
        vim.api.nvim_win_set_cursor(0, { line, col })
        vim.cmd('normal! zz')
        if callback then callback() end
      end
    end)
  end, 0)
end

-- Handle element click from diagram (openInSource action)
---@param action table Action with kind='openInSource' and elementId
function M.handle_element_click(action)
  -- Extract element ID from openInSource action
  local element_id = action.elementId

  if not element_id then
    -- Fallback: check old format
    if action.selectedElementsIDs and #action.selectedElementsIDs > 0 then
      element_id = action.selectedElementsIDs[1]
    else
      return
    end
  end

  -- Check if action has direct source location info
  if action.uri and action.range then
    local file_path = vim.uri_to_fname(action.uri)
    vim.cmd("edit " .. vim.fn.fnameescape(file_path))

    local range = action.range
    if range.start then
      local line = range.start.line + 1  -- LSP is 0-indexed, Vim is 1-indexed
      local col = range.start.character
      vim.api.nvim_win_set_cursor(0, { line, col })
      vim.cmd('normal! zz') -- Center the cursor
    end
    return
  end

  -- Otherwise, try to resolve element ID to source location using LSP
  local symbol_path = parse_element_id(element_id)

  if symbol_path then
    -- Use LSP to find the symbol and jump to it
    jump_to_symbol_lsp(symbol_path)
  end
end

-- Stop all services
function M.stop()
  local sidecar = require("lf.sidecar")
  sidecar.stop()
  -- Silently ignore
end

-- Check if running
function M.is_running()
  local sidecar = require("lf.sidecar")
  return sidecar.is_running()
end

return M
