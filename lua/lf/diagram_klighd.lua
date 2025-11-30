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

-- Parse element ID to extract symbol path and element type info
---@param element_id string
---@return table|nil result Table with symbol_path, element_type, and optional port_info/reaction_info
local function parse_element_id(element_id)
  -- Element IDs encode the full path from root to target element
  -- Format: "$root$N{parent}_{parent}$N{parent}_{inst1}$N{parent}_{inst1}_{inst2}$N..."
  --
  -- Suffixes observed:
  --   $$P{index} - ports (0-indexed, e.g., "$$P0", "$$P1", "$$P2")
  --   $$L{index} - labels on ports/reactions (e.g., "$$P2$$L0" = label on port 2)
  --   $E{index} - edges (ignored)
  --   _reaction_{index} - reactions (1-indexed in KLighD, e.g., "_reaction_1", "_reaction_2")
  --
  -- Examples:
  --   "$root$Nmain_main$Nmain_h" → instance "h"
  --   "$root$Nmain_main$Nmain_h$$P0" → port 0 on instance "h"
  --   "$root$Nmain_main$Nmain_h$$P2$$L0" → label on port 2 of instance "h"
  --   "$root$Nmain_main$Nmain_agents$Nmain_agents_reaction_1" → reaction 1 (0-indexed: 0) on "agents"

  local result = {
    symbol_path = {},
    element_type = "instance",  -- "instance", "port", or "reaction"
    port_index = nil,  -- 0-indexed port number
    reaction_index = nil,  -- 0-indexed reaction number
  }

  -- Check for label suffix: $$L{index} - strip it first, then process the rest
  -- Labels appear on ports, reactions, etc. (e.g., "$$P2$$L0" means label 0 on port 2)
  element_id = element_id:gsub("%$%$L%d+$", "")

  -- Check for port suffix: $$P{index} (0-indexed numeric)
  -- Must check BEFORE edge check since ports can have edges inside them
  local port_match = element_id:match("%$%$P(%d+)")
  if port_match then
    result.element_type = "port"
    result.port_index = tonumber(port_match)
    -- Remove port suffix for path parsing
    element_id = element_id:gsub("%$%$P%d+.*$", "")
  end

  -- Check for edge suffix: $E{index} - ignore edges (connections)
  if element_id:match("%$E%d+$") then
    return nil
  end

  -- Check for reaction suffix: _reaction_{index} (1-indexed in KLighD)
  -- This appears in the last $N segment, e.g., "main_agents_reaction_1"
  local reaction_match = element_id:match("_reaction_(%d+)$")
  if reaction_match then
    result.element_type = "reaction"
    -- Convert from 1-indexed (KLighD) to 0-indexed (internal)
    result.reaction_index = tonumber(reaction_match) - 1
    -- Remove reaction suffix for path parsing
    element_id = element_id:gsub("_reaction_%d+$", "")
  end

  local parts = vim.split(element_id, "$N")

  if #parts < 2 then
    return nil
  end

  -- Handle the case where we're clicking on the main reactor itself or its ports
  if #parts == 2 then
    -- This is the main reactor level (e.g., "$root$Nmain_main")
    -- symbol_path stays empty, meaning the main reactor
    return result
  end

  -- Skip first 2 parts: "$root" and parent reactor (e.g., "main_main")
  -- Start from part 3 onwards to extract instance path

  -- Each part after index 2 contains the cumulative path
  -- e.g., "main_h", "main_pipeline1", "main_pipeline1_pipeline", etc.
  -- We need to extract just the NEW instance name added at each level

  -- Get the parent name from part 2 (e.g., "main_main" → "main")
  local parent_part = parts[2]
  local parent_segments = vim.split(parent_part, "_")
  local parent_name = parent_segments[#parent_segments]

  local prev_cumulative = ""
  for i = 3, #parts do
    local current_part = parts[i]

    local new_instance = nil

    if i == 3 then
      -- First element after main reactor
      -- Format: "main_h" → "h" (instance)
      -- But if current_part equals parent_name, it's still the main reactor
      -- e.g., "main" from "$Nmain_reaction_1" after stripping "_reaction_1"
      if current_part == parent_name then
        -- This is the main reactor itself (e.g., reaction on main reactor)
        -- symbol_path stays empty
        break
      end

      -- Extract instance name by stripping parent prefix
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
      table.insert(result.symbol_path, new_instance)
    end
  end

  return result
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

-- Extract reactor type name from an instantiation line
-- Handles all LF instantiation patterns:
--   instance = new TypeName()           -- standard
--   instance = new TypeName(args)       -- with arguments
--   instance = new[width] TypeName()    -- banked with literal width
--   instance = new[expr] TypeName(args) -- banked with expression and arguments
---@param line_text string The line of code containing the instantiation
---@return string|nil type_name The extracted type name, or nil if not found
local function extract_type_name_from_instantiation(line_text)
  -- Pattern 1: new[...] TypeName - banked reactor (handles any expression in brackets)
  local type_name = line_text:match("new%s*%[.-%]%s*(%w+)")
  if type_name then
    return type_name
  end

  -- Pattern 2: new TypeName - standard instantiation (no brackets)
  type_name = line_text:match("new%s+(%w+)")
  return type_name
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

  -- Extract type name from instantiation (handles standard and banked patterns)
  local type_name = extract_type_name_from_instantiation(line_text)
  if not type_name then
    callback(nil)
    return
  end

  -- Find the character position of the type name in the line
  -- Handle both: "new TypeName" and "new[width] TypeName"
  local type_char_pos = line_text:find(vim.pesc(type_name) .. "%s*%(")
  if not type_char_pos then
    -- Fallback: just find the type name anywhere after "new"
    local new_pos = line_text:find("new")
    if new_pos then
      type_char_pos = line_text:find(vim.pesc(type_name), new_pos)
    end
  end

  if not type_char_pos then
    callback(nil)
    return
  end

  -- Convert to 0-indexed for LSP
  type_char_pos = type_char_pos - 1

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
local function jump_to_symbol_lsp(symbol_path)
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
            vim.schedule(function()
              local target_line = location.range.start.line + 1
              local target_char = location.range.start.character
              vim.api.nvim_win_set_cursor(0, { target_line, target_char })
              vim.cmd('normal! zz')
            end)
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
              vim.schedule(function()
                local target_line = location.range.start.line + 1
                local target_char = location.range.start.character
                vim.api.nvim_win_set_cursor(0, { target_line, target_char })
                vim.cmd('normal! zz')
              end)
            end
            -- If location is nil, it's likely an external reactor - do nothing (VSCode behavior)
          end)
        else
          -- Not the final target - extract the type name and continue navigating
          local range = instance_symbol.location and instance_symbol.location.range or instance_symbol.range
          if range and range.start then
            local line = range.start.line + 1
            local line_text = vim.fn.getline(line)

            -- Extract type name (handles standard and banked patterns)
            local type_name = extract_type_name_from_instantiation(line_text)
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
      local first_type_name = extract_type_name_from_instantiation(line_text)

      if not first_type_name then
        vim.notify("Could not extract type name from first instance", vim.log.levels.WARN)
        return
      end

      navigate_nested_path(2, first_type_name)
    end)
  end, 0)
end

-- Find a port in source code by searching within the reactor's range
-- Ports are in LSP symbols but indexed by KLighD as 0-indexed numbers
---@param reactor_symbol table The reactor symbol from LSP (with range and children)
---@param port_index number The port index (0-indexed)
---@return table|nil location Table with range if found
local function find_port_in_source(reactor_symbol, port_index)
  local range = reactor_symbol.range or (reactor_symbol.location and reactor_symbol.location.range)
  if not range then
    return nil
  end

  local start_line = range.start.line + 1  -- Convert to 1-indexed
  local end_line = range["end"].line + 1

  -- Search for input/output declarations within the reactor's range
  -- Patterns to match:
  --   input name           (standard)
  --   input[width] name    (banked)
  --   output name          (standard)
  --   output[width] name   (banked)
  local port_count = 0
  for line_num = start_line, end_line do
    local line_text = vim.fn.getline(line_num)
    -- Match "input" or "output" at the start of a line (with optional whitespace)
    -- followed by either whitespace (standard) or '[' (banked)
    if line_text:match("^%s*input[%s%[]") or line_text:match("^%s*output[%s%[]") then
      if port_count == port_index then
        -- Find the column where "input" or "output" starts
        local col = (line_text:find("input") or line_text:find("output")) - 1  -- Convert to 0-indexed
        return {
          range = {
            start = { line = line_num - 1, character = col },  -- Convert back to 0-indexed for LSP format
            ["end"] = { line = line_num - 1, character = col + 5 }
          }
        }
      end
      port_count = port_count + 1
    end
  end

  return nil
end

-- Find a reaction in source code by searching within the reactor's range
-- Reactions are NOT included in LSP document symbols, so we search the source directly
---@param reactor_symbol table The reactor symbol from LSP (with range)
---@param reaction_index number The reaction index (0-based)
---@return table|nil location Table with range if found
local function find_reaction_in_source(reactor_symbol, reaction_index)
  local range = reactor_symbol.range or (reactor_symbol.location and reactor_symbol.location.range)
  if not range then
    return nil
  end

  local start_line = range.start.line + 1  -- Convert to 1-indexed
  local end_line = range["end"].line + 1

  -- Search for reaction declarations within the reactor's range
  local reaction_count = 0
  for line_num = start_line, end_line do
    local line_text = vim.fn.getline(line_num)
    -- Match "reaction(" at the start of a line (with optional whitespace)
    if line_text:match("^%s*reaction%s*%(") then
      if reaction_count == reaction_index then
        -- Find the column where "reaction" starts
        local col = line_text:find("reaction") - 1  -- Convert to 0-indexed
        return {
          range = {
            start = { line = line_num - 1, character = col },  -- Convert back to 0-indexed for LSP format
            ["end"] = { line = line_num - 1, character = col + 8 }
          }
        }
      end
      reaction_count = reaction_count + 1
    end
  end

  return nil
end

-- Jump to a specific location in the current file
---@param location table Location with range.start.line and range.start.character
local function jump_to_location(location)
  if location and location.range and location.range.start then
    vim.schedule(function()
      local target_line = location.range.start.line + 1
      local target_char = location.range.start.character
      vim.api.nvim_win_set_cursor(0, { target_line, target_char })
      vim.cmd('normal! zz')
    end)
  end
end

-- Find the main reactor's range in source code
-- The LSP doesn't return "main" as a symbol, so we search the source directly
---@return table|nil range The range {start, end} of the main reactor, or nil if not found
local function find_main_reactor_range()
  local total_lines = vim.api.nvim_buf_line_count(0)
  for line_num = 1, total_lines do
    local line_text = vim.fn.getline(line_num)
    if line_text:match("^%s*main%s+reactor") then
      -- Found main reactor declaration, now find its closing brace
      -- Count only standalone braces { }, ignoring code blocks {= =}
      local start_line = line_num
      local brace_count = 0
      local found_open_brace = false
      local end_line = total_lines  -- Default to end of file
      for search_line = start_line, total_lines do
        local search_text = vim.fn.getline(search_line)
        -- Remove code block delimiters before counting
        local clean_text = search_text:gsub("{=", "XX"):gsub("=}", "XX")
        for _ in clean_text:gmatch("{") do
          brace_count = brace_count + 1
          found_open_brace = true
        end
        for _ in clean_text:gmatch("}") do brace_count = brace_count - 1 end
        -- Only check for end after we've seen the opening brace
        if found_open_brace and brace_count == 0 then
          end_line = search_line
          break
        end
      end
      return {
        start = { line = start_line - 1, character = 0 },
        ["end"] = { line = end_line - 1, character = 0 }
      }
    end
  end
  return nil
end

-- Jump to port or reaction using LSP document symbols
---@param parsed_result table Result from parse_element_id
local function jump_to_port_or_reaction(parsed_result)
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
      local symbol_path = parsed_result.symbol_path

      -- Find the target reactor containing the port/reaction
      local target_reactor = nil

      if #symbol_path == 0 then
        -- Port/reaction is on the main reactor
        local main_range = find_main_reactor_range()
        if main_range then
          target_reactor = { range = main_range }
        end
      else
        -- Navigate to the instance's reactor type
        -- The instance is at the top level (direct child of main reactor)
        local instance_name = symbol_path[#symbol_path]  -- Use the last instance in path

        -- First, find the instance at the top level
        local instance_symbol = nil
        for _, symbol in ipairs(result) do
          if symbol.name == instance_name then
            instance_symbol = symbol
            break
          end
        end

        if not instance_symbol then
          -- Instance not found at top level
          vim.notify("Instance not found: " .. instance_name, vim.log.levels.WARN)
          return
        end

        -- Get the reactor type from the instantiation line
        local range = instance_symbol.location and instance_symbol.location.range or instance_symbol.range
        if range and range.start then
          local line = range.start.line + 1
          local line_text = vim.fn.getline(line)
          local type_name = extract_type_name_from_instantiation(line_text)

          if type_name then
            -- Find the reactor type definition
            for _, symbol in ipairs(result) do
              if symbol.name == type_name then
                target_reactor = symbol
                break
              end
            end
          end
        end
      end

      if not target_reactor then
        vim.notify("Could not find reactor type", vim.log.levels.WARN)
        return
      end

      -- Now find the port or reaction within the reactor
      if parsed_result.element_type == "port" and parsed_result.port_index ~= nil then
        -- Ports use numeric indices, search source directly
        local location = find_port_in_source(target_reactor, parsed_result.port_index)
        if location then
          jump_to_location(location)
        else
          vim.notify("Port not found: index " .. parsed_result.port_index, vim.log.levels.WARN)
        end
      elseif parsed_result.element_type == "reaction" and parsed_result.reaction_index ~= nil then
        -- Reactions are NOT in LSP document symbols, so search the source directly
        local location = find_reaction_in_source(target_reactor, parsed_result.reaction_index)
        if location then
          jump_to_location(location)
        else
          vim.notify("Reaction not found: index " .. parsed_result.reaction_index, vim.log.levels.WARN)
        end
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

  -- Parse element ID to get symbol path and element type
  local parsed_result = parse_element_id(element_id)

  if not parsed_result then
    return
  end

  -- Handle different element types
  if parsed_result.element_type == "port" or parsed_result.element_type == "reaction" then
    -- Jump to port or reaction definition
    jump_to_port_or_reaction(parsed_result)
  elseif #parsed_result.symbol_path > 0 then
    -- Jump to reactor instance (existing behavior)
    jump_to_symbol_lsp(parsed_result.symbol_path)
  end
  -- If symbol_path is empty and not a port/reaction, it's the main reactor - do nothing
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
