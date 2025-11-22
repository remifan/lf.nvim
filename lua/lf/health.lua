-- Health check for Lingua Franca plugin

local M = {}

function M.check()
  vim.health.start("Lingua Franca Plugin")

  -- Check Java
  if vim.fn.executable("java") == 1 then
    local version = vim.fn.system("java --version 2>&1 | head -n1")
    vim.health.ok("Java found: " .. vim.trim(version))
  else
    vim.health.error("Java not found", {
      "Install Java 17+",
      "https://adoptium.net/",
    })
  end

  -- Check LSP JAR
  local config = require("lf").get_config()

  if config.lsp.jar_path and vim.fn.filereadable(config.lsp.jar_path) == 1 then
    vim.health.ok("LSP JAR found: " .. config.lsp.jar_path)
  else
    vim.health.error("LSP JAR not found", {
      "Build the LSP server:",
      "  cd /path/to/lingua-franca",
      "  ./gradlew buildLsp",
      "Then configure jar_path in your setup():",
      "  jar_path = vim.fn.expand('~/path/to/lingua-franca/lsp/build/libs/lsp-*-all.jar')",
    })
  end

  -- Check Node.js (optional)
  if vim.fn.executable("node") == 1 then
    local version = vim.fn.system("node --version")
    vim.health.ok("Node.js found: " .. vim.trim(version))
  else
    vim.health.warn("Node.js not found", {
      "Required for diagram features",
      "Install: https://nodejs.org/",
    })
  end

  -- Check diagram server
  local plugin_path = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h")
  if vim.fn.filereadable(plugin_path .. "/diagram-server/dist/server.js") == 1 then
    vim.health.ok("Diagram server built")
  else
    vim.health.warn("Diagram server not built", {
      "Run: cd diagram-server && npm install && npm run build",
      "Or run the install script: ./scripts/install.sh",
    })
  end
end

return M
