-- Diagram visualization for Lingua Franca
-- Provides reactor diagram viewing using KLighD server

local M = {}

-- Configuration
M.config = {
  enabled = true,
  port = 8765,
  auto_open = true,
  browser_cmd = nil, -- Auto-detect
  live_update = true,
  throttle_ms = 100,
}

-- Setup autocmds for live updates
local augroup = nil

-- Open interactive diagram in browser
function M.open_interactive()
  local server = require("lf.diagram_server")

  -- Check if we have a valid LF file
  local filetype = vim.bo.filetype
  if filetype ~= "lf" then
    vim.notify("Not an LF file. Diagrams are only available for .lf files.", vim.log.levels.WARN)
    return
  end

  local current_file = vim.fn.expand("%:p")
  if current_file == "" then
    vim.notify("No file open. Please open an LF file first.", vim.log.levels.WARN)
    return
  end

  -- Check if lfd is available
  if vim.fn.executable("lfd") == 0 then
    vim.notify("lfd command not found. Please install Lingua Franca CLI tools.", vim.log.levels.ERROR)
    return
  end

  -- Generate diagram SVG using lfd
  vim.notify("Generating diagram with lfd...", vim.log.levels.INFO)

  local plugin_path = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h")
  local html_dir = plugin_path .. "/html"
  local svg_file = html_dir .. "/generated_diagram.svg"

  -- Create temporary directory for lfd to work in
  local temp_dir = vim.fn.tempname()
  vim.fn.mkdir(temp_dir, "p")

  -- Get filename without extension (lfd creates filename.svg in current directory)
  local filename = vim.fn.fnamemodify(current_file, ":t:r")
  local temp_svg = temp_dir .. "/" .. filename .. ".svg"

  -- Run lfd from the temp directory so SVG is created there
  -- lfd creates the SVG in the current working directory
  local cmd = string.format("cd %s && lfd %s 2>&1", vim.fn.shellescape(temp_dir), vim.fn.shellescape(current_file))
  local result = vim.fn.system(cmd)

  -- Check if SVG was generated
  if vim.fn.filereadable(temp_svg) == 0 then
    -- Try to provide helpful error message
    local error_msg = "lfd failed to generate diagram"
    if result and result ~= "" then
      error_msg = error_msg .. ": " .. result
    end
    vim.notify(error_msg, vim.log.levels.ERROR)
    vim.fn.delete(temp_dir, "rf")
    return
  end

  -- Copy SVG to html directory
  local copy_result = vim.fn.system({ "cp", temp_svg, svg_file })
  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to copy diagram file: " .. copy_result, vim.log.levels.ERROR)
    vim.fn.delete(temp_dir, "rf")
    return
  end

  -- Clean up temp directory
  vim.fn.delete(temp_dir, "rf")

  -- Enhance SVG with source location metadata
  local enhancer = require("lf.diagram_enhancer")
  local ok, err = enhancer.enhance_svg(svg_file, current_file)
  if not ok then
    vim.notify("Warning: Could not enhance diagram with source locations: " .. (err or "unknown error"), vim.log.levels.WARN)
  end

  vim.notify("Diagram generated successfully", vim.log.levels.INFO)

  -- Start the HTTP server
  if not server.start() then
    return
  end

  -- Get file URI for passing to browser
  local uri = vim.uri_from_fname(current_file)

  -- Build URL with file parameter
  local url = string.format("http://localhost:%d/?file=%s", M.config.port, vim.fn.shellescape(uri))

  -- Open browser
  vim.notify("Opening diagram viewer in browser...", vim.log.levels.INFO)

  local browser_cmd = M.config.browser_cmd
  if not browser_cmd then
    -- Auto-detect browser command
    if vim.fn.has("mac") == 1 then
      browser_cmd = "open"
    elseif vim.fn.has("unix") == 1 then
      browser_cmd = "xdg-open"
    elseif vim.fn.has("win32") == 1 then
      browser_cmd = "xdg-open"
    elseif vim.fn.has("win32") == 1 then
      browser_cmd = "start"
    else
      vim.notify("Could not detect browser command. Set config.browser_cmd manually.", vim.log.levels.ERROR)
      return
    end
  end

  -- Open browser (remove shell escaping from URL for the command)
  local clean_url = string.format("http://localhost:%d/?file=%s", M.config.port, uri)
  vim.fn.jobstart({ browser_cmd, clean_url }, { detach = true })

  -- Setup live updates if enabled
  if M.config.live_update then
    M.setup_live_updates()
  end

  vim.notify("Diagram viewer opened. Server running on port " .. M.config.port, vim.log.levels.INFO)
end

-- Close the diagram server
function M.close()
  local server = require("lf.diagram_server")
  server.stop()

  -- Clear autocmds
  if augroup then
    vim.api.nvim_del_augroup_by_id(augroup)
    augroup = nil
  end
end

-- Toggle diagram viewer
function M.toggle()
  local server = require("lf.diagram_server")
  if server.is_running() then
    M.close()
  else
    M.open_interactive()
  end
end

-- Setup live updates when file changes
function M.setup_live_updates()
  -- Clear existing autocmds
  if augroup then
    vim.api.nvim_del_augroup_by_id(augroup)
  end

  augroup = vim.api.nvim_create_augroup("LFDiagramLiveUpdate", { clear = true })

  -- Refresh diagram on save
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = augroup,
    pattern = "*.lf",
    callback = function()
      local server = require("lf.diagram_server")
      if server.is_running() then
        -- Notify browser to refresh
        -- For now, we rely on the browser's refresh button
        vim.notify("File saved. Click refresh button in diagram viewer to update.", vim.log.levels.INFO)
      end
    end,
  })

  -- Optional: Send cursor updates (Phase 3 feature)
  -- This would require WebSocket or SSE implementation
  -- vim.api.nvim_create_autocmd("CursorMoved", {
  --   group = augroup,
  --   pattern = "*.lf",
  --   callback = function()
  --     M.send_cursor_update()
  --   end,
  -- })
end

-- Request diagram from LSP server (via KLighD)
-- Note: This is a simplified implementation
-- Full KLighD integration requires more complex handling
function M.generate_diagram()
  local lsp = require("lf.lsp")
  local client = lsp.get_client()
  if not client then
    vim.notify("LF Language Server not running", vim.log.levels.ERROR)
    return
  end

  -- For now, suggest using the interactive viewer
  vim.notify(
    "Use :LFDiagramOpen to open the interactive diagram viewer in your browser.\n"
      .. "For full diagram support, the KLighD diagram server needs WebSocket configuration.",
    vim.log.levels.INFO
  )
end

-- Generate diagram and save to file
function M.export_diagram(output_file, format)
  format = format or "svg"

  local lsp = require("lf.lsp")
  local client = lsp.get_client()
  if not client then
    vim.notify("LF Language Server not running", vim.log.levels.ERROR)
    return
  end

  -- This would require custom endpoint implementation
  -- or integration with the KLighD diagram server's export functionality

  vim.notify(
    string.format(
      "Diagram export to %s format is not yet implemented.\n"
        .. "You can use the lfd tool for diagram generation:\n"
        .. "  lfd %s",
      format,
      vim.fn.expand("%:p")
    ),
    vim.log.levels.INFO
  )
end

-- Open diagram in external viewer
function M.view_diagram_external()
  local current_file = vim.fn.expand("%:p")

  -- Check if lfd (LF diagram tool) is available
  if vim.fn.executable("lfd") == 0 then
    vim.notify(
      "lfd command not found. Please install Lingua Franca CLI tools.\n"
        .. "Build with: ./gradlew :cli:installDist",
      vim.log.levels.ERROR
    )
    return
  end

  -- Generate diagram using lfd
  local temp_dir = vim.fn.tempname()
  vim.fn.mkdir(temp_dir, "p")
  local output_file = temp_dir .. "/diagram.svg"

  vim.notify("Generating diagram...", vim.log.levels.INFO)

  -- Run lfd in background
  vim.fn.jobstart({ "lfd", current_file, "-o", output_file }, {
    on_exit = function(_, exit_code)
      if exit_code == 0 then
        -- Open with default SVG viewer
        if vim.fn.has("mac") == 1 then
          vim.fn.jobstart({ "open", output_file })
        elseif vim.fn.has("unix") == 1 then
          vim.fn.jobstart({ "xdg-open", output_file })
        elseif vim.fn.has("win32") == 1 then
          vim.fn.jobstart({ "start", output_file })
        end
        vim.notify("Diagram opened in external viewer", vim.log.levels.INFO)
      else
        vim.notify("Failed to generate diagram", vim.log.levels.ERROR)
      end
    end,
    on_stderr = function(_, data)
      if data and #data > 0 then
        vim.notify("lfd error: " .. table.concat(data, "\n"), vim.log.levels.ERROR)
      end
    end,
  })
end

-- Show diagram info for current file
function M.info()
  vim.notify(
    "Lingua Franca Diagram Support:\n\n"
      .. "The LF Language Server includes KLighD diagram support.\n"
      .. "For full interactive diagram viewing, use:\n"
      .. "  1. VSCode extension (recommended)\n"
      .. "  2. lfd command-line tool: lfd " .. vim.fn.expand("%:t") .. "\n"
      .. "  3. Web-based diagram viewer\n\n"
      .. "Use :LFDiagram to open with external viewer (requires lfd).",
    vim.log.levels.INFO
  )
end

return M
