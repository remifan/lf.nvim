#!/usr/bin/env -S nvim -l

-- Simple test script to verify the diagram viewer
-- Run with: nvim -l test_diagram.lua

print("Testing Lingua Franca Diagram Viewer")
print("=====================================\n")

-- Test 1: Check if modules can be loaded
print("1. Loading modules...")
local ok_server, diagram_server = pcall(require, "lf.diagram_server")
local ok_diagram, diagram = pcall(require, "lf.diagram")

if not ok_server then
  print("   ✗ Failed to load diagram_server: " .. tostring(diagram_server))
  os.exit(1)
else
  print("   ✓ diagram_server loaded")
end

if not ok_diagram then
  print("   ✗ Failed to load diagram: " .. tostring(diagram))
  os.exit(1)
else
  print("   ✓ diagram loaded")
end

-- Test 2: Check configuration
print("\n2. Checking configuration...")
print("   Port: " .. diagram.config.port)
print("   Auto-open: " .. tostring(diagram.config.auto_open))
print("   Live update: " .. tostring(diagram.config.live_update))

-- Test 3: Check HTML files
print("\n3. Checking HTML files...")
local plugin_path = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h")
local html_dir = plugin_path .. "/html"

local files_to_check = {
  html_dir .. "/diagram-viewer.html",
  html_dir .. "/css/diagram.css",
  html_dir .. "/js/lf-diagram-client.js",
}

for _, file in ipairs(files_to_check) do
  if vim.fn.filereadable(file) == 1 then
    print("   ✓ " .. vim.fn.fnamemodify(file, ":t"))
  else
    print("   ✗ Missing: " .. vim.fn.fnamemodify(file, ":t"))
  end
end

-- Test 4: Check Python availability
print("\n4. Checking Python...")
if vim.fn.executable("python3") == 1 then
  local version = vim.fn.system("python3 --version"):gsub("\n", "")
  print("   ✓ " .. version)
else
  print("   ✗ python3 not found")
end

-- Test 5: Test server start/stop (non-interactive)
print("\n5. Testing server start/stop...")
-- We can't actually start the server in this test because we need a running Neovim instance
print("   (Skipped - requires running Neovim instance)")

print("\n=====================================")
print("Setup verification complete!")
print("\nTo test the diagram viewer:")
print("1. Open Neovim with an LF file: nvim test.lf")
print("2. Run the command: :LFDiagramOpen")
print("3. The diagram viewer should open in your browser")
print("4. Use :LFDiagramClose to stop the server")
