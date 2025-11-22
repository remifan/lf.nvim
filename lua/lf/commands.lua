-- User commands for Lingua Franca
-- Defines all :LF* commands

local M = {}

function M.setup()
  -- Build commands
  vim.api.nvim_create_user_command("LFBuild", function(opts)
    local build = require("lf.build")
    -- Only parse args if there are any
    local args = nil
    if opts.args and opts.args ~= "" then
      args = vim.split(opts.args, "%s+")
    end
    build.build(args)
  end, {
    nargs = "*",
    desc = "Build the current LF file",
  })

  vim.api.nvim_create_user_command("LFRun", function(opts)
    local build = require("lf.build")
    -- Only parse args if there are any
    local args = nil
    if opts.args and opts.args ~= "" then
      args = vim.split(opts.args, "%s+")
    end
    build.build_and_run(args)
  end, {
    nargs = "*",
    desc = "Build and run the current LF file",
  })

  vim.api.nvim_create_user_command("LFCancel", function()
    local build = require("lf.build")
    build.cancel()
  end, {
    desc = "Cancel current build",
  })

  vim.api.nvim_create_user_command("LFValidate", function()
    local build = require("lf.build")
    build.partial_build()
  end, {
    desc = "Validate the current LF file (no compilation)",
  })

  -- AST commands
  vim.api.nvim_create_user_command("LFShowAST", function()
    local ast = require("lf.ast")
    ast.get_ast()
  end, {
    desc = "Show the abstract syntax tree",
  })

  vim.api.nvim_create_user_command("LFExportAST", function(opts)
    local ast = require("lf.ast")
    local output_file = opts.args ~= "" and opts.args or vim.fn.expand("%:r") .. ".sexp"
    ast.export_ast(output_file)
  end, {
    nargs = "?",
    complete = "file",
    desc = "Export AST to file",
  })

  -- Library commands
  vim.api.nvim_create_user_command("LFLibrary", function()
    local library = require("lf.library")
    library.request_library()
  end, {
    desc = "Browse reactor library",
  })

  -- KLighD Diagram commands (primary, interactive)
  vim.api.nvim_create_user_command("LFDiagramOpen", function()
    local diagram_klighd = require("lf.diagram_klighd")
    diagram_klighd.open()
  end, {
    desc = "Open interactive KLighD diagram viewer with jump-to-source",
  })

  -- Alias for convenience
  vim.api.nvim_create_user_command("LFDiagram", function()
    local diagram_klighd = require("lf.diagram_klighd")
    diagram_klighd.open()
  end, {
    desc = "Open interactive KLighD diagram viewer (alias for LFDiagramOpen)",
  })

  vim.api.nvim_create_user_command("LFDiagramClose", function()
    local diagram_klighd = require("lf.diagram_klighd")
    diagram_klighd.stop()
  end, {
    desc = "Close KLighD diagram viewer and services",
  })

  vim.api.nvim_create_user_command("LFDiagramToggle", function()
    local diagram_klighd = require("lf.diagram_klighd")
    if diagram_klighd.is_running() then
      diagram_klighd.stop()
    else
      diagram_klighd.open()
    end
  end, {
    desc = "Toggle KLighD diagram viewer",
  })

  vim.api.nvim_create_user_command("LFDiagramBuild", function()
    local diagram_klighd = require("lf.diagram_klighd")
    diagram_klighd.build_dependencies()
  end, {
    desc = "Build diagram dependencies (diagram-server and frontend)",
  })

  -- Static diagram export commands
  vim.api.nvim_create_user_command("LFDiagramExport", function()
    local diagram = require("lf.diagram")
    diagram.view_diagram_external()
  end, {
    desc = "Generate and view static diagram (external viewer)",
  })

  vim.api.nvim_create_user_command("LFExportDiagram", function(opts)
    local diagram = require("lf.diagram")
    local args = vim.split(opts.args, "%s+")
    local output_file = args[1] or vim.fn.expand("%:r") .. ".svg"
    local format = args[2] or "svg"
    diagram.export_diagram(output_file, format)
  end, {
    nargs = "*",
    complete = "file",
    desc = "Export diagram to file (format: svg, png, pdf)",
  })

  -- LSP commands
  vim.api.nvim_create_user_command("LFStart", function()
    local lsp = require("lf.lsp")
    lsp.start()
  end, {
    desc = "Start LF Language Server",
  })

  vim.api.nvim_create_user_command("LFStop", function()
    local lsp = require("lf.lsp")
    lsp.stop()
  end, {
    desc = "Stop LF Language Server",
  })

  vim.api.nvim_create_user_command("LFRestart", function()
    local lsp = require("lf.lsp")
    lsp.restart()
  end, {
    desc = "Restart LF Language Server",
  })

  vim.api.nvim_create_user_command("LFInfo", function()
    local lsp = require("lf.lsp")
    local client = lsp.get_client()

    if not client then
      vim.notify("LF Language Server is not running", vim.log.levels.WARN)
      return
    end

    local config = require("lf").get_config()
    local info = {
      "Lingua Franca Language Server",
      "",
      "Status: Running",
      "Client ID: " .. (lsp.client_id or "N/A"),
      "Server Name: " .. client.name,
      "Root Dir: " .. (client.config.root_dir or "N/A"),
      "Java Command: " .. config.lsp.java_cmd,
      "JAR Path: " .. config.lsp.jar_path,
      "",
      "Capabilities:",
      "  - Hover: " .. (client.server_capabilities.hoverProvider and "Yes" or "No"),
      "  - Completion: " .. (client.server_capabilities.completionProvider and "Yes" or "No"),
      "  - Definition: " .. (client.server_capabilities.definitionProvider and "Yes" or "No"),
      "  - References: " .. (client.server_capabilities.referencesProvider and "Yes" or "No"),
      "  - Document Symbols: "
        .. (client.server_capabilities.documentSymbolProvider and "Yes" or "No"),
      "",
      "Custom Endpoints:",
      "  - parser/ast",
      "  - generator/build",
      "  - generator/buildAndRun",
      "  - generator/getLibraryReactors",
      "  - generator/getTargetPosition",
    }

    -- Create floating window
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, info)
    vim.api.nvim_buf_set_option(buf, "modifiable", false)
    vim.api.nvim_buf_set_option(buf, "filetype", "markdown")

    local width = 60
    local height = #info
    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = width,
      height = height,
      col = (vim.o.columns - width) / 2,
      row = (vim.o.lines - height) / 2,
      style = "minimal",
      border = "rounded",
      title = " LF Language Server Info ",
      title_pos = "center",
    })

    -- Close on q or Escape
    vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", {
      noremap = true,
      silent = true,
    })
    vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":close<CR>", {
      noremap = true,
      silent = true,
    })
  end, {
    desc = "Show LF Language Server information",
  })

  -- Target position command
  vim.api.nvim_create_user_command("LFTargetPosition", function()
    local lsp = require("lf.lsp")
    local client = lsp.get_client()
    if not client then
      vim.notify("LF Language Server not running", vim.log.levels.ERROR)
      return
    end

    local uri = vim.uri_from_bufnr(0)
    lsp.request("generator/getTargetPosition", { textDocument = { uri = uri } }, function(err, result)
      if err then
        vim.notify("Failed to get target position: " .. err.message, vim.log.levels.ERROR)
        return
      end

      if result and result.line then
        vim.api.nvim_win_set_cursor(0, { result.line + 1, result.column or 0 })
        vim.notify(
          string.format("Target position: line %d, column %d", result.line + 1, result.column or 0),
          vim.log.levels.INFO
        )
      else
        vim.notify("No target declaration found in this file", vim.log.levels.WARN)
      end
    end)
  end, {
    desc = "Jump to target declaration",
  })
end

return M
