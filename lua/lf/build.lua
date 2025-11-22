-- Build system integration for Lingua Franca
-- Handles full build, partial build, and build-and-run operations

local M = {}

-- Current build state
M.current_build = {
  in_progress = false,
  progress_token = nil,
  cancel_fn = nil,
}

-- Progress stages from IntegratedBuilder
local PROGRESS_STAGES = {
  START = { percentage = 0, message = "Starting build..." },
  VALIDATED = { percentage = 33, message = "Validated" },
  GENERATED = { percentage = 67, message = "Generated code" },
  COMPILED = { percentage = 100, message = "Compiled" },
}

-- Show progress notification or echo
local function show_progress(message, percentage)
  local config = require("lf").get_config()

  if config.ui.progress_style == "notify" then
    vim.notify(
      string.format("%s (%d%%)", message, percentage),
      vim.log.levels.INFO,
      { title = "LF Build" }
    )
  else
    vim.api.nvim_echo({
      { string.format("LF Build: %s (%d%%)", message, percentage), "Normal" },
    }, false, {})
  end
end

-- Handle build progress updates
local function handle_progress(progress)
  if not progress then
    return
  end

  local percentage = progress.percentage or 0
  local message = progress.message or "Building..."

  show_progress(message, percentage)
end

-- Parse diagnostics from build result
local function parse_diagnostics(result)
  if not result or not result.diagnostics then
    return {}
  end

  local items = {}
  for _, diag in ipairs(result.diagnostics) do
    table.insert(items, {
      filename = diag.uri and vim.uri_to_fname(diag.uri) or "",
      lnum = (diag.range and diag.range.start.line or 0) + 1,
      col = (diag.range and diag.range.start.character or 0) + 1,
      text = diag.message or "",
      type = diag.severity == 1 and "E" or diag.severity == 2 and "W" or "I",
    })
  end

  return items
end

-- Set quickfix list with build results
local function set_quickfix(result)
  local config = require("lf").get_config()
  local items = parse_diagnostics(result)

  if #items > 0 then
    vim.fn.setqflist(items, "r")
    if config.build.open_quickfix then
      vim.cmd("copen")
    end
  else
    vim.fn.setqflist({}, "r")
    vim.cmd("cclose")
  end
end

-- Build the current file with full compilation
function M.build(args)
  if M.current_build.in_progress then
    vim.notify("Build already in progress", vim.log.levels.WARN)
    return
  end

  local lsp = require("lf.lsp")
  local client = lsp.get_client()
  if not client then
    vim.notify("LF Language Server not running", vim.log.levels.ERROR)
    return
  end

  M.current_build.in_progress = true
  M.current_build.progress_token = vim.fn.strftime("%Y%m%d%H%M%S")

  local uri = vim.uri_from_bufnr(0)

  -- Convert args to JSON object string
  -- The server expects a JSON object string, not an array
  local json_args = "{}"
  if args and type(args) == "table" and next(args) ~= nil then
    -- If it's a non-empty table, encode it as JSON object
    json_args = vim.json.encode(args)
  end

  -- LSP server expects BuildArgs { uri: string, json: string }
  local params = {
    uri = uri,
    json = json_args,
  }

  -- Note: Progress tracking is handled by the LSP server internally
  -- The server sends progress via $/progress notifications which Neovim handles automatically
  vim.notify("Building " .. vim.fn.fnamemodify(vim.uri_to_fname(uri), ":t") .. "...", vim.log.levels.INFO)

  -- Send build request
  lsp.request("generator/build", params, function(err, result)
    M.current_build.in_progress = false
    M.current_build.progress_token = nil

    if err then
      vim.notify("Build failed: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
      return
    end

    -- Handle result
    if result then
      -- The LSP server returns a string message on success
      if type(result) == "string" then
        -- Check if it's a success or error message
        if result:match("Code generation complete") or result:match("executable is at") then
          vim.notify(result, vim.log.levels.INFO)
        elseif result:match("error") or result:match("failed") or result:match("Error") then
          vim.notify(result, vim.log.levels.ERROR)
        else
          vim.notify(result, vim.log.levels.INFO)
        end
      elseif type(result) == "table" then
        -- Handle structured result (if server returns this format)
        local status = result.status or "UNKNOWN"
        if status == "COMPILED" then
          vim.notify("Build successful!", vim.log.levels.INFO)
          set_quickfix(result)
        elseif status == "FAILED" then
          vim.notify("Build failed", vim.log.levels.ERROR)
          set_quickfix(result)
        elseif status == "CANCELLED" then
          vim.notify("Build cancelled", vim.log.levels.WARN)
        else
          vim.notify("Build completed with status: " .. status, vim.log.levels.INFO)
          set_quickfix(result)
        end
      else
        vim.notify("Build completed: " .. vim.inspect(result), vim.log.levels.INFO)
      end
    else
      vim.notify("Build completed but no result returned", vim.log.levels.WARN)
    end
  end)
end

-- Partial build (validation only, no compilation)
function M.partial_build(bufnr)
  local lsp = require("lf.lsp")
  local client = lsp.get_client()
  if not client then
    return
  end

  bufnr = bufnr or 0
  local uri = vim.uri_from_bufnr(bufnr)

  -- Don't send notification if URI is empty
  if not uri or uri == "" then
    return
  end

  local params = {
    textDocument = { uri = uri },
  }

  -- Send notification (no response expected)
  lsp.notify_server("generator/partialBuild", params)
end

-- Build and run the current file
function M.build_and_run(args)
  if M.current_build.in_progress then
    vim.notify("Build already in progress", vim.log.levels.WARN)
    return
  end

  local lsp = require("lf.lsp")
  local client = lsp.get_client()
  if not client then
    vim.notify("LF Language Server not running", vim.log.levels.ERROR)
    return
  end

  M.current_build.in_progress = true

  local uri = vim.uri_from_bufnr(0)

  -- Convert args to JSON object string
  -- The server expects a JSON object string, not an array
  local json_args = "{}"
  if args and type(args) == "table" and next(args) ~= nil then
    -- If it's a non-empty table, encode it as JSON object
    json_args = vim.json.encode(args)
  end

  -- LSP server expects BuildArgs { uri: string, json: string }
  local params = {
    uri = uri,
    json = json_args,
  }

  show_progress("Building for run...", 0)

  -- Send build-and-run request
  lsp.request("generator/buildAndRun", params, function(err, result)
    M.current_build.in_progress = false

    if err then
      vim.notify("Build and run failed: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
      return
    end

    if result then
      local command = nil

      -- Handle different response formats
      if type(result) == "string" then
        command = result
      elseif type(result) == "table" then
        if result.command then
          -- Standard format: { command: "..." }
          command = result.command
        elseif #result >= 2 then
          -- Array format: [directory, executable]
          -- Join them to create the full path
          local dir = result[1]
          local exe = result[2]
          -- Remove trailing "." from directory if present
          dir = dir:gsub("/%.$", "")
          command = dir .. "/" .. exe
        elseif #result == 1 then
          command = result[1]
        end
      end

      if command then
        vim.notify("Build successful! Running...", vim.log.levels.INFO)

        -- Open terminal and run the command
        vim.cmd("botright split")
        vim.cmd("terminal " .. command)
        vim.cmd("startinsert")
      else
        vim.notify("Build completed but couldn't determine command: " .. vim.inspect(result), vim.log.levels.WARN)
      end
    else
      vim.notify("Build and run completed but no result returned", vim.log.levels.WARN)
    end
  end)
end

-- Cancel current build
function M.cancel()
  if not M.current_build.in_progress then
    vim.notify("No build in progress", vim.log.levels.WARN)
    return
  end

  -- LSP supports cancellation via $/cancelRequest
  local lsp = require("lf.lsp")
  local client = lsp.get_client()
  if client and M.current_build.progress_token then
    client.notify("$/cancelRequest", {
      id = M.current_build.progress_token,
    })

    M.current_build.in_progress = false
    M.current_build.progress_token = nil

    vim.notify("Build cancelled", vim.log.levels.INFO)
  end
end

-- Get current build status
function M.status()
  return {
    in_progress = M.current_build.in_progress,
    progress_token = M.current_build.progress_token,
  }
end

return M
