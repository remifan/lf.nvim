-- Diagram synchronization between Neovim and browser
-- Handles cursor position sync and selection sync

local M = {}

local sync_enabled = false
local debounce_timer = nil
local last_synced_pos = nil

-- Enable/disable diagram sync
function M.set_enabled(enabled)
    sync_enabled = enabled
    if enabled then
        M.setup_cursor_sync()
    else
        M.teardown_cursor_sync()
    end
end

-- Setup cursor position tracking
function M.setup_cursor_sync()
    -- Create autocmd for cursor movement
    vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
        group = vim.api.nvim_create_augroup("LFDiagramSync", { clear = true }),
        pattern = "*.lf",
        callback = function()
            M.on_cursor_moved()
        end,
    })
end

-- Teardown cursor tracking
function M.teardown_cursor_sync()
    pcall(vim.api.nvim_del_augroup_by_name, "LFDiagramSync")
end

-- Handle cursor movement
function M.on_cursor_moved()
    if not sync_enabled then
        return
    end

    -- Debounce to avoid too many updates
    if debounce_timer then
        vim.fn.timer_stop(debounce_timer)
    end

    debounce_timer = vim.fn.timer_start(150, function()
        M.sync_cursor_position()
    end)
end

-- Sync current cursor position to diagram
function M.sync_cursor_position()
    local pos = vim.api.nvim_win_get_cursor(0)
    local line = pos[1]
    local col = pos[2]

    -- Check if position changed
    if last_synced_pos and last_synced_pos[1] == line and last_synced_pos[2] == col then
        return
    end

    last_synced_pos = {line, col}

    -- Get current file URI
    local uri = vim.uri_from_bufnr(0)

    -- TODO: Send position to diagram via sidecar
    -- This would require the LSP to provide element IDs based on source position
    -- For now, just log it
    vim.schedule(function()
        -- vim.cmd('echo "Cursor at ' .. line .. ':' .. col .. '"')

        -- The challenge: we need to map source position (line:col) to diagram element ID
        -- This typically requires an LSP request or maintaining a mapping table
        -- KLighD LSP servers may provide this via custom requests
    end)
end

-- Manually trigger sync (for testing)
function M.sync_now()
    M.sync_cursor_position()
end

return M
