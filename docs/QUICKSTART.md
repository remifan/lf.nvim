# Quick Start Guide

Get up and running with lf.nvim in 5 minutes!

## TL;DR

```bash
# 1. Build the LSP server
cd /home/remi/Workspace/lingua-franca
./gradlew :lsp:shadowJar

# 2. Add to your Neovim config (lazy.nvim)
# File: ~/.config/nvim/lua/plugins/lf.lua
return {
  dir = "/home/remi/Workspace/lingua-franca/nvim-plugin",
  ft = "lf",
  opts = {
    lsp = {
      jar_path = "/home/remi/Workspace/lingua-franca/lsp/build/libs/lsp-all.jar",
    },
  },
}

# 3. Restart Neovim and open a .lf file
nvim test.lf
```

## Step-by-Step

### 1. Prerequisites

Check you have:
- Neovim 0.10+ (`nvim --version`)
- Java 17+ (`java -version`)

### 2. Build LSP Server

```bash
cd /home/remi/Workspace/lingua-franca
./gradlew :lsp:shadowJar
```

This creates: `lsp/build/libs/lsp-all.jar`

### 3. Install Plugin

**Using lazy.nvim:**

Create `~/.config/nvim/lua/plugins/lf.lua`:

```lua
return {
  dir = "/home/remi/Workspace/lingua-franca/nvim-plugin",
  ft = "lf",
  dependencies = {
    "nvim-telescope/telescope.nvim",  -- Optional but recommended
  },
  opts = {
    lsp = {
      jar_path = "/home/remi/Workspace/lingua-franca/lsp/build/libs/lsp-all.jar",
    },
  },
}
```

**Using packer.nvim:**

Add to your packer config:

```lua
use {
  "/home/remi/Workspace/lingua-franca/nvim-plugin",
  ft = "lf",
  config = function()
    require("lf").setup({
      lsp = {
        jar_path = "/home/remi/Workspace/lingua-franca/lsp/build/libs/lsp-all.jar",
      },
    })
  end,
}
```

### 4. Test Installation

```bash
# Open a Lingua Franca file
nvim examples/HelloWorld.lf

# In Neovim, check status
:LFInfo
```

You should see:
```
Lingua Franca Language Server
Status: Running
Client ID: 1
...
```

### 5. Try Features

**Build your file:**
```vim
:LFBuild
```

**Build and run:**
```vim
:LFRun
```

**View AST:**
```vim
:LFShowAST
```

**Browse reactor library:**
```vim
:LFLibrary
```

**Standard LSP features:**
- Hover: Move cursor over a symbol, press `K`
- Go to definition: Move cursor over a symbol, press `gd`
- Show references: Move cursor over a symbol, press `gr`
- Diagnostics: Errors show automatically with red squiggles

### 6. Configure Keybindings

The default keybindings are:

| Key | Command | Action |
|-----|---------|--------|
| `<leader>lb` | `:LFBuild` | Build current file |
| `<leader>lr` | `:LFRun` | Build and run |
| `<leader>la` | `:LFShowAST` | Show AST |
| `<leader>ll` | `:LFLibrary` | Browse library |
| `<leader>ld` | `:LFDiagram` | View diagram |
| `<F5>` | `:LFBuild` | Quick build |
| `<F6>` | `:LFRun` | Quick run |

**Note:** `<leader>` is typically `\` or space, depending on your config.

To change keybindings, add to your setup:

```lua
opts = {
  keymaps = {
    build = "<F5>",
    run = "<F6>",
    show_ast = "<leader>a",
    library = "<leader>l",
    diagram = false,  -- Disable this keybinding
  },
}
```

## Common Workflows

### Building and Running

```vim
" Full build with compilation
:LFBuild

" Check build output
:copen

" Build and run in terminal
:LFRun

" Just validate (no compilation)
:LFValidate
```

### Navigation

```vim
" Go to reactor definition
gd

" Find all references to reactor
gr

" Browse all available reactors
:LFLibrary

" Jump to target declaration
:LFTargetPosition
```

### Debugging

```vim
" View abstract syntax tree
:LFShowAST

" Check LSP server status
:LFInfo

" View LSP logs
:LspLog

" Restart LSP server if issues
:LFRestart
```

## Recommended Additional Plugins

Install these for the best experience:

### 1. Telescope (File/Symbol Picker)

```lua
{
  "nvim-telescope/telescope.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
}
```

### 2. nvim-cmp (Autocompletion)

```lua
{
  "hrsh7th/nvim-cmp",
  dependencies = {
    "hrsh7th/cmp-nvim-lsp",  -- LSP completion source
    "hrsh7th/cmp-buffer",     -- Buffer completion
    "hrsh7th/cmp-path",       -- Path completion
  },
  config = function()
    local cmp = require("cmp")
    cmp.setup({
      sources = {
        { name = "nvim_lsp" },
        { name = "buffer" },
        { name = "path" },
      },
    })
  end,
}
```

Then update lf.nvim config:

```lua
opts = {
  lsp = {
    jar_path = "...",
    capabilities = require("cmp_nvim_lsp").default_capabilities(),
  },
}
```

### 3. LuaSnip (Snippets)

```lua
{
  "L3MON4D3/LuaSnip",
  config = function()
    -- Add LF-specific snippets here
  end,
}
```

## Troubleshooting

### LSP Not Starting

**Check 1:** Is Java installed?
```bash
java -version
```

**Check 2:** Does the JAR exist?
```bash
ls -la /home/remi/Workspace/lingua-franca/lsp/build/libs/lsp-all.jar
```

**Check 3:** Check Neovim logs
```vim
:LspLog
:messages
```

### Build Fails

**Check 1:** Are you in an LF project?
```bash
ls *.lf
```

**Check 2:** Check quickfix list
```vim
:copen
```

**Check 3:** Try building manually
```bash
cd /home/remi/Workspace/lingua-franca
./gradlew :lfc:build
```

### No Syntax Highlighting

**Check 1:** Is filetype detected?
```vim
:set filetype?
```
Should show: `filetype=lf`

**Fix:** Manually set filetype
```vim
:set filetype=lf
```

**Permanent fix:** Add to `~/.config/nvim/init.lua`:
```lua
vim.filetype.add({
  extension = {
    lf = "lf",
  },
})
```

## Next Steps

Once you're comfortable with the basics:

1. **Read the full documentation:** `:help lf`
2. **Explore all commands:** `:LF<Tab>` to see all available commands
3. **Customize your config:** See `example-config.lua` for advanced options
4. **Learn LSP features:** `:help lsp` for all LSP capabilities
5. **Build a real project:** Try building one of the LF examples

## Example LF File

Create `test.lf` to test the plugin:

```lf
target C

reactor Hello {
  output out: string
  reaction(startup) -> out {=
    lf_set(out, "Hello, Lingua Franca!");
  =}
}

reactor World {
  input in: string
  reaction(in) {=
    printf("%s\n", in->value);
  =}
}

main reactor {
  h = new Hello()
  w = new World()
  h.out -> w.in
}
```

Now try:
- `:LFBuild` - Should build successfully
- `:LFRun` - Should print "Hello, Lingua Franca!"
- Hover over `Hello` and press `K` - Should show reactor info
- `:LFShowAST` - View the syntax tree

## Getting Help

- **Plugin Issues:** https://github.com/lf-lang/lingua-franca/issues
- **LF Documentation:** https://lf-lang.org
- **Neovim Help:** `:help lsp`, `:help lua`
- **Example Config:** See `example-config.lua` in plugin directory

## Full Documentation

For complete documentation, see:
- `README.md` - Feature overview
- `INSTALL.md` - Detailed installation
- `ARCHITECTURE.md` - Technical details
- `:help lf` - Vim help documentation

Happy coding with Lingua Franca!
