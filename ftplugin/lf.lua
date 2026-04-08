-- Filetype plugin for Lingua Franca
-- Sets buffer-local options and configurations

-- Start tree-sitter highlighting if parser is available
if pcall(vim.treesitter.language.inspect, "lf") then
  vim.treesitter.start(vim.api.nvim_get_current_buf(), "lf")
end

-- Set comment string for commentary.vim and similar plugins
vim.bo.commentstring = "// %s"

-- Set formatting options
vim.bo.formatoptions = "croql"

-- Enable smart indentation
vim.bo.smartindent = true

-- Set tab settings (using spaces, 4 spaces per indent)
vim.bo.expandtab = true
vim.bo.shiftwidth = 4
vim.bo.softtabstop = 4
vim.bo.tabstop = 4

-- Enable line numbers
vim.wo.number = true
vim.wo.relativenumber = true

-- Buffer-local keybindings
local keymap_opts = { noremap = true, silent = true, buffer = true }

-- Quick build command
vim.keymap.set("n", "<F5>", "<cmd>LFBuild<CR>", keymap_opts)
vim.keymap.set("n", "<F6>", "<cmd>LFRun<CR>", keymap_opts)
