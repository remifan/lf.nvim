-- HTTP server for serving the diagram viewer
-- Handles bidirectional communication between browser and Neovim

local M = {}

-- Server state
M.server = {
  process = nil, -- HTTP server process
  port = 8765, -- Default port
  current_file = nil, -- Current LF file URI
  cursor_position = {}, -- { line, col }
  browser_connected = false,
  python_script = nil, -- Path to Python server script
}

-- Get the plugin's html directory
local function get_html_dir()
  local plugin_path = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h")
  return plugin_path .. "/html"
end

-- Generate diagram SVG for a file
local function generate_diagram_svg(filepath)
  local parser = require("lf.diagram_parser")
  local svg, structure = parser.generate_diagram_from_file(filepath)
  return svg or "<svg><text x='50' y='50'>Error generating diagram</text></svg>"
end

-- Create Python HTTP server script with RPC support
local function create_server_script()
  local html_dir = get_html_dir()
  local script_path = vim.fn.tempname() .. "_lf_server.py"

  local script_content = [[
#!/usr/bin/env python3
import http.server
import socketserver
import json
import threading
import sys
from urllib.parse import urlparse, parse_qs
from pathlib import Path

PORT = ]] .. M.server.port .. [[

HTML_DIR = r"]] .. html_dir .. [["

class LFDiagramHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=HTML_DIR, **kwargs)

    def do_GET(self):
        parsed = urlparse(self.path)

        # Serve the main diagram viewer
        if parsed.path == '/' or parsed.path == '/index.html':
            self.path = '/diagram-viewer.html'
        # Serve generated diagram SVG
        elif parsed.path == '/api/diagram':
            query = parse_qs(parsed.query)
            file_path = query.get('file', [None])[0]

            if file_path:
                # Request diagram generation from Neovim
                print(f"DIAGRAM_REQUEST:{file_path}", flush=True)

                # For now, return a placeholder response
                # The actual SVG will be served via the diagram endpoint
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(json.dumps({"status": "pending"}).encode())
                return

        # Serve static files
        return super().do_GET()

    def do_POST(self):
        parsed = urlparse(self.path)

        # Handle RPC requests from browser
        if parsed.path == '/api/jump':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)

            try:
                data = json.loads(post_data)
                # Write jump request to stdout for Neovim to read
                print(f"JUMP:{json.dumps(data)}", flush=True)

                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(json.dumps({"status": "ok"}).encode())
            except Exception as e:
                self.send_response(500)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        # Suppress HTTP logs to avoid cluttering Neovim output
        pass

# Create server
with socketserver.TCPServer(("127.0.0.1", PORT), LFDiagramHandler) as httpd:
    print(f"SERVER_STARTED:http://127.0.0.1:{PORT}", flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("SERVER_STOPPED", flush=True)
        sys.exit(0)
]]

  -- Write script to temp file
  local file = io.open(script_path, "w")
  if file then
    file:write(script_content)
    file:close()
    -- Make executable
    vim.fn.system({ "chmod", "+x", script_path })
    M.server.python_script = script_path
    return script_path
  end

  return nil
end

-- Start the HTTP server
function M.start()
  if M.is_running() then
    vim.notify("Diagram server already running on port " .. M.server.port, vim.log.levels.INFO)
    return true
  end

  -- Create HTML directory if it doesn't exist
  local html_dir = get_html_dir()
  if vim.fn.isdirectory(html_dir) == 0 then
    vim.fn.mkdir(html_dir, "p")
  end

  -- Create Python server script
  local script_path = create_server_script()
  if not script_path then
    vim.notify("Failed to create server script", vim.log.levels.ERROR)
    return false
  end

  -- Start Python HTTP server
  M.server.process = vim.fn.jobstart({ "python3", script_path }, {
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line:match("^SERVER_STARTED:") then
            local url = line:match("SERVER_STARTED:(.*)")
            vim.notify("Diagram server started at " .. url, vim.log.levels.INFO)
            M.server.browser_connected = true
          elseif line:match("^JUMP:") then
            local json_data = line:match("JUMP:(.*)")
            M.handle_jump_request(json_data)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data and #data > 0 then
        for _, line in ipairs(data) do
          if line ~= "" then
            vim.notify("Server error: " .. line, vim.log.levels.WARN)
          end
        end
      end
    end,
    on_exit = function(_, exit_code)
      M.server.process = nil
      M.server.browser_connected = false
      if exit_code ~= 0 then
        vim.notify("Diagram server stopped with code " .. exit_code, vim.log.levels.WARN)
      end
    end,
  })

  if M.server.process <= 0 then
    vim.notify("Failed to start diagram server", vim.log.levels.ERROR)
    return false
  end

  return true
end

-- Stop the HTTP server
function M.stop()
  if not M.is_running() then
    vim.notify("Diagram server not running", vim.log.levels.WARN)
    return
  end

  vim.fn.jobstop(M.server.process)
  M.server.process = nil
  M.server.browser_connected = false

  -- Clean up temp script
  if M.server.python_script then
    vim.fn.delete(M.server.python_script)
    M.server.python_script = nil
  end

  vim.notify("Diagram server stopped", vim.log.levels.INFO)
end

-- Check if server is running
function M.is_running()
  return M.server.process ~= nil and M.server.process > 0
end

-- Handle jump request from browser
function M.handle_jump_request(json_data)
  local ok, data = pcall(vim.fn.json_decode, json_data)
  if not ok then
    vim.notify("Invalid jump request: " .. json_data, vim.log.levels.ERROR)
    return
  end

  -- data should contain: { file, line, column }
  if data.file and data.line then
    -- Convert URI to filename if needed
    local filename = data.file
    if filename:match("^file://") then
      filename = vim.uri_to_fname(filename)
    end

    -- Open file if different
    if filename ~= vim.fn.expand("%:p") then
      vim.cmd("edit " .. vim.fn.fnameescape(filename))
    end

    -- Jump to line and column
    local line = tonumber(data.line) or 1
    local col = tonumber(data.column) or 0
    vim.api.nvim_win_set_cursor(0, { line, col })

    vim.notify(string.format("Jumped to %s:%d:%d", vim.fn.fnamemodify(filename, ":t"), line, col), vim.log.levels.INFO)
  end
end

-- Broadcast message to all connected browsers
-- (For now, we'll implement this using a simple file-based approach)
function M.broadcast(message)
  -- TODO: Implement WebSocket or SSE for real-time updates
  -- For Phase 1, we'll skip this and implement in Phase 3
end

-- Get current file URI
function M.get_current_file_uri()
  local filename = vim.fn.expand("%:p")
  if filename and filename ~= "" then
    return vim.uri_from_fname(filename)
  end
  return nil
end

-- Get current cursor position
function M.get_cursor_position()
  local pos = vim.api.nvim_win_get_cursor(0)
  return {
    line = pos[1],
    column = pos[2],
    file = M.get_current_file_uri(),
  }
end

return M
