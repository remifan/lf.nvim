-- Reactor library browser for Lingua Franca
-- Provides hierarchical navigation of available reactors

local M = {}

-- Cached library reactors
M.reactors = {}

-- Update cached reactors from server notification
function M.update_reactors(reactors)
  M.reactors = reactors or {}
end

-- Flatten library structure for telescope picker
local function flatten_library(node, prefix, result)
  result = result or {}
  prefix = prefix or ""

  if node.reactor then
    -- This is a reactor node
    table.insert(result, {
      name = node.reactor.name or "Unknown",
      path = node.reactor.path or "",
      file = node.reactor.file or "",
      line = node.reactor.line or 1,
      display = prefix .. (node.reactor.name or "Unknown"),
    })
  end

  -- Recurse into children
  if node.children then
    for _, child in ipairs(node.children) do
      local child_prefix = prefix
      if node.name then
        child_prefix = prefix .. node.name .. "."
      end
      flatten_library(child, child_prefix, result)
    end
  end

  return result
end

-- Request library reactors from LSP server
function M.request_library()
  local lsp = require("lf.lsp")
  local client = lsp.get_client()
  if not client then
    vim.notify("LF Language Server not running", vim.log.levels.ERROR)
    return
  end

  local uri = vim.uri_from_bufnr(0)
  local params = {
    textDocument = { uri = uri },
  }

  lsp.request("generator/getLibraryReactors", params, function(err, result)
    if err then
      vim.notify("Failed to get library reactors: " .. err.message, vim.log.levels.ERROR)
      return
    end

    if result then
      M.update_reactors(result)
      M.show()
    end
  end)
end

-- Show library using telescope if available, otherwise use vim.ui.select
function M.show()
  if #M.reactors == 0 then
    vim.notify("No library reactors available. Requesting from server...", vim.log.levels.INFO)
    M.request_library()
    return
  end

  local flattened = flatten_library({ children = M.reactors })

  if #flattened == 0 then
    vim.notify("No reactors found in library", vim.log.levels.WARN)
    return
  end

  local config = require("lf").get_config()

  -- Try to use telescope if available and enabled
  if config.ui.use_telescope then
    local has_telescope, telescope = pcall(require, "telescope")
    if has_telescope then
      M.show_with_telescope(flattened)
      return
    end
  end

  -- Fallback to vim.ui.select
  M.show_with_select(flattened)
end

-- Show library using telescope
function M.show_with_telescope(reactors)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers
    .new({}, {
      prompt_title = "Lingua Franca Reactor Library",
      finder = finders.new_table({
        results = reactors,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.display,
            ordinal = entry.display,
            filename = entry.file,
            lnum = entry.line,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = conf.grep_previewer({}),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection and selection.value.file then
            M.jump_to_reactor(selection.value)
          end
        end)
        return true
      end,
    })
    :find()
end

-- Show library using vim.ui.select
function M.show_with_select(reactors)
  local items = {}
  for _, reactor in ipairs(reactors) do
    table.insert(items, reactor.display)
  end

  vim.ui.select(items, {
    prompt = "Select reactor:",
    format_item = function(item)
      return item
    end,
  }, function(choice, idx)
    if choice and idx then
      M.jump_to_reactor(reactors[idx])
    end
  end)
end

-- Jump to reactor definition
function M.jump_to_reactor(reactor)
  if not reactor.file or reactor.file == "" then
    vim.notify("No file information for reactor: " .. reactor.name, vim.log.levels.WARN)
    return
  end

  -- Open file and jump to line
  vim.cmd("edit " .. reactor.file)
  if reactor.line and reactor.line > 0 then
    vim.api.nvim_win_set_cursor(0, { reactor.line, 0 })
  end
end

-- Get reactors for the current file
function M.get_current_file_reactors()
  local current_file = vim.fn.expand("%:p")
  local result = {}

  for _, reactor_tree in ipairs(M.reactors) do
    local flattened = flatten_library(reactor_tree)
    for _, reactor in ipairs(flattened) do
      if reactor.file == current_file then
        table.insert(result, reactor)
      end
    end
  end

  return result
end

return M
