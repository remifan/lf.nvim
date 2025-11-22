# Installation Guide for lf.nvim

This guide will help you install and configure the Lingua Franca Neovim plugin.

## Prerequisites

Before installing the plugin, ensure you have:

1. **Neovim >= 0.10.0**
   ```bash
   nvim --version
   ```

2. **Java 17 or higher**
   ```bash
   java -version
   ```

3. **Git** (for cloning the repository)

## Step 1: Build the LSP Server

The LSP server must be built from the Lingua Franca repository before using the plugin.

```bash
# Navigate to the Lingua Franca repository
cd /home/remi/Workspace/lingua-franca

# Build the LSP server
./gradlew :lsp:shadowJar

# Verify the JAR was created
ls -lh lsp/build/libs/lsp-*-all.jar
```

The LSP server JAR will be located at:
```
/home/remi/Workspace/lingua-franca/lsp/build/libs/lsp-<version>-all.jar
```

Note the full path - you'll need it for configuration.

## Step 2: Choose Your Plugin Manager

### Option A: lazy.nvim (Recommended)

If you're using [lazy.nvim](https://github.com/folke/lazy.nvim):

1. Create a plugin file:
   ```bash
   mkdir -p ~/.config/nvim/lua/plugins
   nvim ~/.config/nvim/lua/plugins/lf.lua
   ```

2. Add this configuration:
   ```lua
   return {
     dir = "/home/remi/Workspace/lingua-franca/nvim-plugin",
     ft = "lf",
     dependencies = {
       "nvim-telescope/telescope.nvim", -- Optional but recommended
     },
     opts = {
       lsp = {
         jar_path = "/home/remi/Workspace/lingua-franca/lsp/build/libs/lsp-all.jar",
         java_cmd = "java",
         java_args = { "-Xmx2G" },
       },
     },
   }
   ```

3. Restart Neovim and run `:Lazy sync`

### Option B: packer.nvim

If you're using [packer.nvim](https://github.com/wbthomason/packer.nvim):

Add to your `plugins.lua`:

```lua
use {
  "/home/remi/Workspace/lingua-franca/nvim-plugin",
  ft = "lf",
  requires = {
    "nvim-telescope/telescope.nvim", -- Optional
  },
  config = function()
    require("lf").setup({
      lsp = {
        jar_path = "/home/remi/Workspace/lingua-franca/lsp/build/libs/lsp-all.jar",
      },
    })
  end,
}
```

Then run `:PackerSync`

### Option C: Manual Installation

For manual installation without a plugin manager:

1. Create the plugin directory:
   ```bash
   mkdir -p ~/.local/share/nvim/site/pack/plugins/start/
   ```

2. Symlink the plugin:
   ```bash
   ln -s /home/remi/Workspace/lingua-franca/nvim-plugin \
     ~/.local/share/nvim/site/pack/plugins/start/lf.nvim
   ```

3. Add to your `init.lua`:
   ```lua
   require("lf").setup({
     lsp = {
       jar_path = "/home/remi/Workspace/lingua-franca/lsp/build/libs/lsp-all.jar",
     },
   })
   ```

## Step 3: Verify Installation

1. Open Neovim with a Lingua Franca file:
   ```bash
   nvim test.lf
   ```

2. Check that the LSP server started:
   ```vim
   :LFInfo
   ```

3. You should see information about the running LSP server.

4. Test LSP features:
   - Hover over a symbol and press `K` (should show documentation)
   - Type and check for diagnostics (red squiggles for errors)
   - Try `:LFBuild` to build the file

## Step 4: Optional Dependencies

### Telescope (Highly Recommended)

For better UI/UX when browsing reactor libraries:

```bash
# Using lazy.nvim, add to your plugins:
{
  "nvim-telescope/telescope.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
}
```

### TreeSitter (Optional)

For advanced syntax highlighting:

```bash
# Using lazy.nvim:
{
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
}
```

Note: Lingua Franca TreeSitter parser may not be available yet. The plugin includes a fallback Vim syntax file.

### LF Diagram Tool (Optional)

For diagram viewing:

```bash
cd /home/remi/Workspace/lingua-franca
./gradlew :cli:installDist

# Add to PATH
export PATH="$PATH:/home/remi/Workspace/lingua-franca/cli/build/install/lf-cli/bin"
```

## Step 5: Customize Configuration

Create a custom configuration based on your needs. See `example-config.lua` for a full configuration template.

Common customizations:

### Increase JVM Memory

For large projects:

```lua
opts = {
  lsp = {
    jar_path = "...",
    java_args = { "-Xmx4G" },  -- Increase from 2G to 4G
  },
}
```

### Disable Auto-Validation

If validation on save is too slow:

```lua
opts = {
  build = {
    auto_validate = false,
  },
}
```

### Custom Keybindings

```lua
opts = {
  keymaps = {
    build = "<F5>",
    run = "<F6>",
    show_ast = "<leader>a",
    library = "<leader>l",
    diagram = "<leader>d",
  },
}
```

### Custom LSP on_attach

```lua
opts = {
  lsp = {
    jar_path = "...",
    on_attach = function(client, bufnr)
      -- Your custom keybindings
      local opts = { noremap = true, silent = true, buffer = bufnr }
      vim.keymap.set("n", "<leader>f", vim.lsp.buf.format, opts)
    end,
  },
}
```

## Troubleshooting

### LSP Server Not Starting

**Error:** "LSP JAR not found"

**Solution:** Verify the JAR path in your configuration:
```bash
ls -la /home/remi/Workspace/lingua-franca/lsp/build/libs/lsp-*-all.jar
```

If the file doesn't exist, rebuild:
```bash
cd /home/remi/Workspace/lingua-franca
./gradlew :lsp:clean :lsp:shadowJar
```

**Error:** "Java command not found"

**Solution:** Install Java 17+ or specify the full path:
```lua
opts = {
  lsp = {
    java_cmd = "/usr/lib/jvm/java-17-openjdk/bin/java",
    -- ...
  },
}
```

### LSP Server Crashes

Check the LSP logs:
```vim
:LspLog
```

Increase JVM memory if you see `OutOfMemoryError`:
```lua
java_args = { "-Xmx4G" }
```

### Build Failures

1. Check quickfix list:
   ```vim
   :copen
   ```

2. Manually test the build:
   ```bash
   cd /home/remi/Workspace/lingua-franca
   ./gradlew :lfc:build
   ```

3. Check LSP server logs for detailed errors

### No Syntax Highlighting

1. Verify filetype detection:
   ```vim
   :set filetype?
   ```
   Should show: `filetype=lf`

2. If not, manually set:
   ```vim
   :set filetype=lf
   ```

3. Check syntax file loaded:
   ```vim
   :syntax
   ```

## Next Steps

Once installed:

1. Read the documentation: `:help lf`
2. Check available commands: `:LF<Tab>`
3. Try building a file: `:LFBuild`
4. Browse reactor library: `:LFLibrary`
5. View AST: `:LFShowAST`

## Getting Help

- **Plugin Issues:** https://github.com/lf-lang/lingua-franca/issues
- **LF Documentation:** https://lf-lang.org
- **Neovim LSP:** `:help lsp`

## Uninstallation

### lazy.nvim
Remove the plugin file from `~/.config/nvim/lua/plugins/lf.lua` and run `:Lazy clean`

### packer.nvim
Remove the plugin configuration and run `:PackerClean`

### Manual
```bash
rm ~/.local/share/nvim/site/pack/plugins/start/lf.nvim
```
