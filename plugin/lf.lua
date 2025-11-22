-- Plugin initialization for lf.nvim
-- This file is automatically loaded by Neovim

-- Prevent loading the plugin twice
if vim.g.loaded_lf_nvim then
  return
end
vim.g.loaded_lf_nvim = 1

-- Ensure minimum Neovim version
if vim.fn.has("nvim-0.10.0") == 0 then
  vim.notify("lf.nvim requires Neovim >= 0.10.0", vim.log.levels.ERROR)
  return
end

-- Register syntax highlighting commands (always available)
vim.api.nvim_create_user_command("LFInfo", function()
  require("lf_nvim").show_info()
end, { desc = "Show lf.nvim configuration and target language" })

vim.api.nvim_create_user_command("LFDetectTarget", function()
  require("lf_nvim").detect_target_language()
end, { desc = "Manually detect target language from current buffer" })

vim.api.nvim_create_user_command("LFUpdateSyntax", function()
  require("lf_nvim").update_syntax()
end, { desc = "Update syntax from VSCode extension" })

vim.api.nvim_create_user_command("LFUpdateSyntaxDryRun", function()
  require("lf_nvim").update_syntax({ dry_run = true })
end, { desc = "Preview available syntax updates" })

vim.api.nvim_create_user_command("LFShowKeywords", function()
  require("lf_nvim").update_syntax({ show_keywords = true })
end, { desc = "Display all LF keywords from VSCode grammar" })

-- The plugin will be set up by the user calling require("lf").setup()
-- LSP commands are registered in lua/lf/commands.lua when LSP is enabled
