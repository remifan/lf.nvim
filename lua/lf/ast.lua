-- AST viewer for Lingua Franca
-- Displays the abstract syntax tree in S-expression format

local M = {}

-- Get AST for the current buffer
function M.get_ast()
  local lsp = require("lf.lsp")
  local client = lsp.get_client()
  if not client then
    vim.notify("LF Language Server not running", vim.log.levels.ERROR)
    return
  end

  local uri = vim.uri_from_bufnr(0)

  -- The parser/ast endpoint expects just a string URI parameter
  lsp.request("parser/ast", uri, function(err, result)
    if err then
      vim.notify("Failed to get AST: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
      return
    end

    -- The result is the AST string directly
    if result and type(result) == "string" then
      M.show_ast(result)
    elseif result then
      vim.notify("Unexpected AST format: " .. vim.inspect(result), vim.log.levels.WARN)
    else
      vim.notify("No AST returned from server", vim.log.levels.WARN)
    end
  end)
end

-- Format S-expression with indentation
local function format_sexp(sexp, indent)
  indent = indent or 0
  local lines = {}
  local line = ""
  local in_string = false
  local paren_depth = 0
  local current_indent = indent

  for i = 1, #sexp do
    local char = sexp:sub(i, i)

    if char == '"' and (i == 1 or sexp:sub(i - 1, i - 1) ~= "\\") then
      in_string = not in_string
      line = line .. char
    elseif not in_string then
      if char == "(" then
        if paren_depth > 0 and #line > 0 then
          table.insert(lines, string.rep("  ", current_indent) .. line)
          line = ""
        end
        paren_depth = paren_depth + 1
        current_indent = current_indent + 1
        line = line .. char
      elseif char == ")" then
        if #line > 0 then
          table.insert(lines, string.rep("  ", current_indent - 1) .. line .. char)
          line = ""
        else
          if #lines > 0 then
            lines[#lines] = lines[#lines] .. char
          end
        end
        paren_depth = paren_depth - 1
        current_indent = current_indent - 1
      elseif char == " " and paren_depth > 0 then
        if #line > 0 then
          table.insert(lines, string.rep("  ", current_indent - 1) .. line)
          line = ""
        end
      else
        line = line .. char
      end
    else
      line = line .. char
    end
  end

  if #line > 0 then
    table.insert(lines, string.rep("  ", current_indent) .. line)
  end

  return table.concat(lines, "\n")
end

-- Show AST in a split window
function M.show_ast(ast_text)
  -- Create a new buffer
  local buf = vim.api.nvim_create_buf(false, true)

  -- Set buffer options
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "swapfile", false)
  vim.api.nvim_buf_set_option(buf, "filetype", "lisp")

  -- Format the AST
  local formatted = format_sexp(ast_text)
  local lines = vim.split(formatted, "\n")

  -- Set buffer content
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Make buffer read-only
  vim.api.nvim_buf_set_option(buf, "modifiable", false)

  -- Open in a vertical split
  vim.cmd("vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)

  -- Set window options
  vim.api.nvim_buf_set_name(buf, "LF AST: " .. vim.fn.expand("%:t"))

  -- Add keybinding to close the window
  vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", {
    noremap = true,
    silent = true,
    desc = "Close AST window",
  })

  -- Enable folding
  vim.api.nvim_win_set_option(win, "foldmethod", "indent")
  vim.api.nvim_win_set_option(win, "foldlevel", 1)
end

-- Export AST to file
function M.export_ast(output_file)
  local lsp = require("lf.lsp")
  local client = lsp.get_client()
  if not client then
    vim.notify("LF Language Server not running", vim.log.levels.ERROR)
    return
  end

  local uri = vim.uri_from_bufnr(0)

  -- The parser/ast endpoint expects just a string URI parameter
  lsp.request("parser/ast", uri, function(err, result)
    if err then
      vim.notify("Failed to get AST: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
      return
    end

    if result and type(result) == "string" then
      -- Write to file
      local file = io.open(output_file, "w")
      if file then
        file:write(result)
        file:close()
        vim.notify("AST exported to: " .. output_file, vim.log.levels.INFO)
      else
        vim.notify("Failed to write AST to file: " .. output_file, vim.log.levels.ERROR)
      end
    else
      vim.notify("No AST returned from server", vim.log.levels.WARN)
    end
  end)
end

return M
