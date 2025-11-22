-- Lua module for lf.nvim plugin
local M = {}

-- Default configuration
M.config = {
  -- Target language for syntax highlighting
  -- Options: "C", "Cpp", "Python", "Rust", "TypeScript"
  target_language = nil,

  -- Enable automatic target detection from file content
  auto_detect_target = true,

  -- Indentation settings
  indent = {
    size = 4,
    use_tabs = false,
  },
}

-- Setup function for user configuration
function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", M.config, opts)

  -- Apply configuration
  if M.config.target_language then
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "lf",
      callback = function()
        vim.b.lfTargetLanguage = M.config.target_language
      end,
    })
  end

  -- Auto-detect target language if enabled
  if M.config.auto_detect_target then
    vim.api.nvim_create_autocmd("BufRead", {
      pattern = "*.lf",
      callback = function()
        M.detect_target_language()
      end,
    })
  end

  -- Apply indentation settings
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "lf",
    callback = function()
      vim.bo.shiftwidth = M.config.indent.size
      vim.bo.softtabstop = M.config.indent.size
      vim.bo.tabstop = M.config.indent.size
      vim.bo.expandtab = not M.config.indent.use_tabs
    end,
  })
end

-- Detect target language from file content
function M.detect_target_language()
  local lines = vim.api.nvim_buf_get_lines(0, 0, 50, false)

  for _, line in ipairs(lines) do
    local target = line:match("^%s*target%s+(%w+)")
    if target then
      -- Map target to syntax file names
      local target_map = {
        C = "C",
        Cpp = "Cpp",
        CCpp = "Cpp",
        Python = "Python",
        Py = "Python",
        Rust = "Rust",
        TypeScript = "TypeScript",
        TS = "TypeScript",
      }

      vim.b.lfTargetLanguage = target_map[target] or target
      break
    end
  end
end

-- Get current target language
function M.get_target_language()
  return vim.b.lfTargetLanguage or M.config.target_language or "unknown"
end

-- Command to show current configuration
function M.show_info()
  local target = M.get_target_language()
  print(string.format("Lingua Franca Plugin Info"))
  print(string.format("  Target Language: %s", target))
  print(string.format("  Indent Size: %d", M.config.indent.size))
  print(string.format("  Use Tabs: %s", tostring(M.config.indent.use_tabs)))
end

-- Update syntax from VSCode extension
function M.update_syntax(opts)
  opts = opts or {}
  local dry_run = opts.dry_run or false
  local show_keywords = opts.show_keywords or false

  -- Get the script path
  local script_path = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h") .. "/scripts/update_syntax.lua"

  -- Build arguments
  local args = {}
  if dry_run then
    table.insert(args, "--dry-run")
  end
  if show_keywords then
    table.insert(args, "--show-keywords")
  end

  -- Run the update script
  print("Running syntax update script...")
  local cmd = "nvim -l " .. vim.fn.shellescape(script_path)
  for _, arg in ipairs(args) do
    cmd = cmd .. " " .. arg
  end

  local output = vim.fn.system(cmd)
  print(output)

  if vim.v.shell_error == 0 then
    if not dry_run and not show_keywords then
      -- Reload syntax for current buffer if it's an LF file
      if vim.bo.filetype == "lf" then
        vim.cmd("syntax sync fromstart")
        print("Syntax reloaded for current buffer")
      end
    end
  else
    print("Error running update script. Exit code: " .. vim.v.shell_error)
  end
end

return M
