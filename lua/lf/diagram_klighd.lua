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

  -- Wait for sidecar to be ready, then open browser or display URL
  vim.defer_fn(function()
    local port = sidecar.get_http_port()
    local url = string.format("http://localhost:%d/", port)

    -- Get configuration
    local lf = require('lf')
    local no_browser = lf.config.diagram.no_browser

    -- Always display the URL
    vim.notify(
      string.format("Diagram viewer available at:\n%s", url),
      vim.log.levels.INFO
    )

    -- Auto-open browser unless no_browser is set
    if not no_browser then
      local browser_cmd
      if vim.fn.has("mac") == 1 then
        browser_cmd = "open"
      elseif vim.fn.has("unix") == 1 then
        browser_cmd = "xdg-open"
      else
        vim.notify("Could not detect browser command. Use the URL above to open manually.", vim.log.levels.WARN)
        return
      end

      vim.fn.jobstart({ browser_cmd, url }, { detach = true })
    end

    -- Browser will automatically request diagram when it connects
    -- Enable diagram sync (cursor tracking) after a delay
    vim.defer_fn(function()
      local sync = require("lf.diagram_sync")
      sync.set_enabled(true)
    end, 1000)
  end, 3000)
end

-- Request diagram from LSP server and push to browser
-- This is used for reactive updates when switching files
---@param file_path string
function M.request_diagram(file_path)
  -- Check if sidecar is running (browser is connected)
  local sidecar = require("lf.sidecar")
  if not sidecar.is_running() then
    return
  end

  -- Instead of sending directly to LSP, trigger the browser to send a new requestModel
  -- This ensures the full bounds computation cycle works correctly
  -- We send a special action to tell the browser to refresh
  sidecar.send_action_to_browser({
    clientId = "lf-diagram-viewer",
    action = {
      kind = "refreshDiagram"  -- Custom action to trigger browser refresh
    }
  })
end

-- Request diagram for current file (helper)
function M.request_diagram_for_current_file()
  if vim.bo.filetype ~= 'lf' then
    return
  end

  local current_file = vim.fn.expand("%:p")
  if current_file == "" then
    return
  end

  M.request_diagram(current_file)
end

-- Parse element ID to extract symbol path
---@param element_id string
---@return table|nil symbol_path Array of symbol names from root to target
local function parse_element_id(element_id)
  -- Element IDs encode the full path from root to target element
  -- Format: "$root$N{parent}_{parent}$N{parent}_{inst1}$N{parent}_{inst1}_{inst2}$N..."
  -- Examples:
  --   "$root$Nmain_main$Nmain_h" → ["h"]
  --   "$root$Nmain_main$Nmain_pipeline1$Nmain_pipeline1_pipeline" → ["pipeline1", "pipeline"]
  --   "$root$Nmain_main$Nmain_pipeline1$Nmain_pipeline1_pipeline$Nmain_pipeline1_pipeline_filter" → ["pipeline1", "pipeline", "filter"]

  local parts = vim.split(element_id, "$N")

  if #parts < 3 then
    return nil
  end

  -- Skip first 2 parts: "$root" and parent reactor (e.g., "main_main")
  -- Start from part 3 onwards to extract instance path
  local symbol_path = {}

  -- Each part after index 2 contains the cumulative path
  -- e.g., "main_h", "main_pipeline1", "main_pipeline1_pipeline", etc.
  -- We need to extract just the NEW instance name added at each level

  local prev_cumulative = ""
  for i = 3, #parts do
    local current_part = parts[i]

    -- Strip port suffix if present (e.g., "h$$P0" → "h")
    current_part = current_part:match("^(.+)%$%$") or current_part

    local new_instance = nil

    if i == 3 then
      -- First instance (top-level): strip parent prefix
      -- Format: "main_h" → "h"
      local parent_part = parts[2]
      local parent_segments = vim.split(parent_part, "_")
      local parent_name = parent_segments[#parent_segments]

      local pattern = "^" .. vim.pesc(parent_name) .. "_(.+)$"
      new_instance = current_part:match(pattern)
      if not new_instance then
        new_instance = current_part:match("^[^_]+_(.+)$") or current_part
      end

      prev_cumulative = current_part
    else
      -- Nested instance: strip the previous cumulative path
      -- Format: "main_pipeline1_pipeline" with prev="main_pipeline1" → "pipeline"
      local pattern = "^" .. vim.pesc(prev_cumulative) .. "_(.+)$"
      new_instance = current_part:match(pattern)

      if not new_instance then
        -- Fallback: just take the last segment after splitting by underscore
        local segments = vim.split(current_part, "_")
        new_instance = segments[#segments]
      end

      prev_cumulative = current_part
    end

    if new_instance then
      table.insert(symbol_path, new_instance)
    end
  end

  return symbol_path
end

-- Helper function to find an instance child within a reactor's children
local function find_instance_in_reactor(reactor_symbol, instance_name)
  if not reactor_symbol.children then
    return nil
  end

  for _, child in ipairs(reactor_symbol.children) do
    local child_base_name = child.name:match("%.(.+)$") or child.name
    if child_base_name == instance_name then
      return child
    end
  end

  return nil
end

-- Helper function to get type definition location without moving cursor
-- Extracts the type name from an instance declaration and resolves its definition
local function get_type_definition_location(client, instance_symbol, callback)
  local range = instance_symbol.location and instance_symbol.location.range or instance_symbol.range
  if not range or not range.start then
    callback(nil)
    return
  end

  local line = range.start.line + 1
  local line_text = vim.fn.getline(line)

  -- Extract type name from "instance = new TypeName()" pattern
  local type_name = line_text:match("new%s+(%w+)")
  if not type_name then
    callback(nil)
    return
  end

  -- Find the position of the type name in the line
  local type_start_pos = line_text:find("new%s+" .. vim.pesc(type_name))
  if not type_start_pos then
    callback(nil)
    return
  end

  -- Calculate the character position of the type name (after "new ")
  local type_char_pos = type_start_pos + 3  -- skip "new"
  type_char_pos = line_text:match("^%s*()", type_char_pos + 1) - 1  -- find first non-whitespace

  -- Make LSP definition request at the type name position
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(),
    position = {
      line = range.start.line,  -- LSP uses 0-indexed lines
      character = type_char_pos
    }
  }

  client.request('textDocument/definition', params, function(err, result)
    if err or not result then
      callback(nil)
      return
    end

    -- result can be Location | Location[] | LocationLink[]
    local location = nil
    if vim.islist(result) then
      location = result[1]
    else
      location = result
    end

    if location then
      -- Handle LocationLink vs Location
      local target_uri = nil
      local target_range = nil

      if location.targetUri then
        -- LocationLink
        target_uri = location.targetUri
        target_range = location.targetRange or location.targetSelectionRange
      else
        -- Location
        target_uri = location.uri
        target_range = location.range
      end

      -- Check if the definition is in the current file
      -- External/imported reactors will have definitions in different files
      -- Following VSCode behavior: ignore external reactor definitions
      local current_uri = vim.uri_from_bufnr(0)
      if target_uri ~= current_uri then
        -- External reactor - do nothing (VSCode behavior)
        callback(nil)
        return
      end

      callback({
        uri = target_uri,
        range = target_range
      })
    else
      callback(nil)
    end
  end, 0)
end

-- Jump to symbol using LSP document symbols
---@param symbol_path table Array of symbol names (e.g., {"pipeline1"} or {"pipeline1", "pipeline", "filter"})
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

    vim.schedule(function()
      -- Strategy for any-level nesting:
      -- 1. Start with top-level instance (always found at top level in LSP symbols)
      -- 2. For each subsequent level, find the REACTOR TYPE of the previous instance
      -- 3. Search that reactor type's children for the next instance
      -- 4. Repeat until we reach the final target
      -- 5. Jump to the final target's type definition

      if #symbol_path == 0 then
        vim.notify("Empty symbol path", vim.log.levels.WARN)
        return
      end

      -- Step 1: Find the first instance at top level
      local first_instance_name = symbol_path[1]
      local first_instance = nil

      for _, symbol in ipairs(result) do
        if symbol.name == first_instance_name or symbol.name:match("^" .. vim.pesc(first_instance_name)) then
          first_instance = symbol
          break
        end
      end

      if not first_instance then
        vim.notify("Could not find top-level instance: " .. first_instance_name, vim.log.levels.WARN)
        return
      end

      -- If this is the only element in the path, jump to its type definition
      if #symbol_path == 1 then
        get_type_definition_location(client, first_instance, function(location)
          if location and location.range then
            local target_line = location.range.start.line + 1
            local target_char = location.range.start.character
            vim.api.nvim_win_set_cursor(0, { target_line, target_char })
            vim.cmd('normal! zz')
          end
          -- If location is nil, it's likely an external reactor - do nothing (VSCode behavior)
        end)
        return
      end

      -- For nested paths, navigate through each level
      -- We need to find reactor types and search their children
      local function navigate_nested_path(path_index, current_reactor_name)
        if path_index > #symbol_path then
          return
        end

        local target_instance_name = symbol_path[path_index]

        -- Find the reactor type definition
        local reactor_type = nil
        for _, symbol in ipairs(result) do
          if symbol.name == current_reactor_name then
            reactor_type = symbol
            break
          end
        end

        if not reactor_type then
          -- Reactor type not found in current file - likely an external/imported reactor
          -- VSCode behavior: do nothing, so we silently return
          return
        end

        -- Find the instance within this reactor's children
        local instance_symbol = find_instance_in_reactor(reactor_type, target_instance_name)
        if not instance_symbol then
          -- Instance not found - likely part of external reactor
          -- VSCode behavior: do nothing, so we silently return
          return
        end

        -- If this is the final target, jump to its type definition
        if path_index == #symbol_path then
          get_type_definition_location(client, instance_symbol, function(location)
            if location and location.range then
              local target_line = location.range.start.line + 1
              local target_char = location.range.start.character
              vim.api.nvim_win_set_cursor(0, { target_line, target_char })
              vim.cmd('normal! zz')
            end
            -- If location is nil, it's likely an external reactor - do nothing (VSCode behavior)
          end)
        else
          -- Not the final target - extract the type name and continue navigating
          local range = instance_symbol.location and instance_symbol.location.range or instance_symbol.range
          if range and range.start then
            local line = range.start.line + 1
            local line_text = vim.fn.getline(line)

            -- Extract type name from "instance = new TypeName()" pattern
            local type_name = line_text:match("new%s+(%w+)")
            if type_name then
              navigate_nested_path(path_index + 1, type_name)
            end
            -- If can't extract type name, silently fail (VSCode behavior)
          end
        end
      end

      -- Start navigation from the first instance
      -- First, get its type name
      local range = first_instance.location and first_instance.location.range or first_instance.range
      if not range or not range.start then
        vim.notify("Could not get location for first instance", vim.log.levels.WARN)
        return
      end

      local line = range.start.line + 1
      local line_text = vim.fn.getline(line)
      local first_type_name = line_text:match("new%s+(%w+)")

      if not first_type_name then
        vim.notify("Could not extract type name from first instance", vim.log.levels.WARN)
        return
      end

      navigate_nested_path(2, first_type_name)
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
