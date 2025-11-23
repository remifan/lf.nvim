---@class LFSidecar
---Manages the Node.js diagram server sidecar process
local M = {}

local sidecar_job_id = nil
local sidecar_port = 8765
local rpc_port = 8766
local rpc_socket = nil

--- Start the diagram sidecar server
---@return boolean success
function M.start()
    if sidecar_job_id then
        -- Already running, silently return
        return true
    end

    -- Get the directory where this Lua script is located
    local plugin_path = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h")
    local sidecar_dir = plugin_path .. "/diagram-server"
    local node_cmd = 'npm'
    local args = {'start'}

    -- Start sidecar silently
    sidecar_job_id = vim.fn.jobstart({node_cmd, unpack(args)}, {
        cwd = sidecar_dir,
        on_stdout = function(_, data)
            -- Silently consume stdout to avoid blocking messages
        end,
        on_stderr = function(_, data)
            -- Silently consume stderr to avoid blocking messages
        end,
        on_exit = function(_, exit_code)
            -- Silently handle exit
            sidecar_job_id = nil
            M.close_rpc()
        end,
    })

    if sidecar_job_id <= 0 then
        vim.notify("Failed to start diagram sidecar", vim.log.levels.ERROR)
        sidecar_job_id = nil
        return false
    end

    -- Wait a bit for server to start
    vim.defer_fn(function()
        M.connect_rpc()
    end, 2000)

    return true
end

--- Stop the diagram sidecar server
function M.stop()
    if sidecar_job_id then
        vim.fn.jobstop(sidecar_job_id)
        sidecar_job_id = nil
    end
    M.close_rpc()
end

--- Connect to the sidecar's RPC endpoint
function M.connect_rpc()
    if rpc_socket then
        -- Already connected
        return
    end

    local uv = vim.loop

    rpc_socket = uv.new_tcp()

    rpc_socket:connect('127.0.0.1', rpc_port, function(err)
        if err then
            vim.schedule(function()
                vim.notify("Failed to connect to sidecar RPC: " .. err, vim.log.levels.ERROR)
            end)
            rpc_socket:close()
            rpc_socket = nil
            return
        end

        vim.schedule(function()
            -- Silently ignore
        end)

        -- Start reading responses
        rpc_socket:read_start(function(read_err, data)
            if read_err then
                vim.schedule(function()
                    vim.notify("RPC read error: " .. read_err, vim.log.levels.ERROR)
                end)
                return
            end

            if data then
                M.handle_rpc_message(data)
            else
                -- Connection closed
                vim.schedule(function()
                    -- Silently ignore
                end)
                M.close_rpc()
            end
        end)
    end)
end

--- Close the RPC connection
function M.close_rpc()
    if rpc_socket then
        rpc_socket:close()
        rpc_socket = nil
    end
end

local rpc_buffer = ''

--- Handle messages received from sidecar RPC
---@param data string
function M.handle_rpc_message(data)
    rpc_buffer = rpc_buffer .. data

    -- Process complete messages (newline-delimited JSON)
    local newline_pos = rpc_buffer:find('\n')
    while newline_pos do
        local line = rpc_buffer:sub(1, newline_pos - 1)
        rpc_buffer = rpc_buffer:sub(newline_pos + 1)

        vim.schedule(function()
            local ok, message = pcall(vim.fn.json_decode, line)
            if ok and message then
                if message.method == 'diagram/action' then
                    -- Action from browser (via sidecar) that we need to handle
                    local action_msg = message.params
                    local action = action_msg.action

                    -- Handle openInSource action from diagram
                    if action.kind == 'openInSource' then
                        vim.schedule(function()
                            local diagram_klighd = require('lf.diagram_klighd')
                            diagram_klighd.handle_element_click(action)
                        end)
                    elseif action.kind == 'requestModel' then
                        -- Browser is requesting a diagram
                        -- Inject the current file's URI and forward to LSP
                        vim.schedule(function()
                            if vim.bo.filetype == 'lf' then
                                local current_file = vim.fn.expand("%:p")
                                if current_file ~= "" then
                                    local uri = vim.uri_from_fname(current_file)

                                    -- Update the action with the current file's URI and layout options
                                    local modified_action = vim.tbl_deep_extend('force', action_msg, {
                                        action = vim.tbl_deep_extend('force', action, {
                                            options = vim.tbl_deep_extend('force', action.options or {}, {
                                                sourceUri = uri,
                                                needsClientLayout = false,  -- Server does layout
                                                needsServerLayout = true    -- Server does layout
                                            })
                                        })
                                    })

                                    -- Forward to LSP via diagram/accept notification
                                    local lsp = require('lf.lsp')
                                    lsp.notify_server('diagram/accept', modified_action)
                                end
                            end
                        end)
                    else
                        -- Forward other actions to LSP via diagram/accept notification
                        -- The LSP will process it and might send back diagram/accept or diagram/openInTextEditor
                        local lsp = require('lf.lsp')
                        lsp.notify_server('diagram/accept', action_msg)
                    end
                elseif message.method == 'browser/connected' then
                    -- Browser will send RequestModel action automatically
                    -- Silently ignore
                elseif message.method == 'browser/disconnected' then
                    -- Silently ignore
                end
            else
                vim.notify('Failed to parse RPC message: ' .. line, vim.log.levels.ERROR)
            end
        end)

        newline_pos = rpc_buffer:find('\n')
    end
end

--- Send an action to the browser via sidecar RPC
---@param action_msg table The ActionMessage to send (should have clientId and action fields)
function M.send_action_to_browser(action_msg)
    if not rpc_socket then
        -- Silently ignore
        return
    end

    -- action_msg should already be an ActionMessage from LSP
    -- Format: { clientId: ..., action: { kind: ..., ... } }
    local message = {
        method = 'diagram/action',
        params = action_msg  -- Don't wrap it again
    }

    local json = vim.fn.json_encode(message) .. '\n'
    rpc_socket:write(json)
end

--- Check if sidecar is running
---@return boolean
function M.is_running()
    return sidecar_job_id ~= nil
end

--- Get the HTTP port where the diagram viewer is served
---@return number
function M.get_http_port()
    return sidecar_port
end

return M
