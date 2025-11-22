# Lingua Franca Diagram Viewer - Usage Guide

## Overview

The LF Neovim plugin now includes an interactive web-based diagram viewer that displays your Lingua Franca program structure in a browser with bidirectional code navigation.

## Features

- **Interactive Diagrams** - View reactor hierarchies, ports, and connections
- **Click to Navigate** - Click diagram elements to jump to code in Neovim
- **Web-Based** - Runs in your default browser with a clean interface
- **Live Updates** - Notification when file changes (manual refresh for now)
- **Placeholder Support** - Works without KLighD WebSocket (shows placeholder diagram)

## Requirements

- Python 3 (for HTTP server)
- Web browser (Chrome, Firefox, Safari, etc.)
- Neovim with lf.nvim plugin configured

## Commands

### `:LFDiagramOpen`
Opens the interactive diagram viewer in your browser. This will:
1. Start a local HTTP server on port 8765
2. Open your default browser with the diagram viewer
3. Display the current LF file's diagram

### `:LFDiagramClose`
Stops the diagram server and closes the connection.

### `:LFDiagramToggle`
Toggles the diagram viewer (open if closed, close if open).

### `:LFDiagram`
Opens the diagram using an external viewer (requires `lfd` tool).

### `:LFDiagramInfo`
Shows information about diagram support.

## Quick Start

1. Open an LF file in Neovim:
   ```bash
   nvim test.lf
   ```

2. Run the diagram viewer command:
   ```vim
   :LFDiagramOpen
   ```

3. Your browser should open with the diagram viewer showing your program structure.

4. Click on diagram elements to navigate back to the code in Neovim.

5. When done, close the server:
   ```vim
   :LFDiagramClose
   ```

## Keybindings

If you have keybindings configured (default: `<leader>ld`), you can use:

```vim
<leader>ld  " Same as :LFDiagram
```

You can add a custom keymap for the interactive viewer in your config:

```lua
require("lf").setup({
  -- ... other config ...
  keymaps = {
    diagram = "<leader>ld",
    -- You can add more custom keymaps in your own config
  }
})

-- Add custom keymap for interactive diagram
vim.keymap.set("n", "<leader>ldi", "<cmd>LFDiagramOpen<CR>", { desc = "Open interactive diagram" })
```

## Configuration

You can configure the diagram viewer in your `setup()` call:

```lua
require("lf").setup({
  -- ... other config ...
})

-- Access diagram config
local diagram = require("lf.diagram")
diagram.config.port = 8765           -- Server port (default: 8765)
diagram.config.auto_open = true      -- Auto-open browser (default: true)
diagram.config.browser_cmd = "firefox"  -- Browser command (default: auto-detect)
diagram.config.live_update = true    -- Enable live updates (default: true)
```

## How It Works

### Architecture

```
┌─────────────┐         HTTP          ┌─────────────┐
│   Neovim    │ ◄──────────────────► │   Browser   │
│  (Server)   │                        │  (Client)   │
└─────────────┘                        └─────────────┘
      │                                       │
      │ Click to Navigate                    │ Display SVG
      │ (POST /api/jump)                     │ Diagram
      │                                       │
      └───────────────────────────────────────┘
```

### Components

1. **diagram_server.lua** - Python-based HTTP server that serves the viewer
2. **diagram-viewer.html** - Web interface with controls and diagram display
3. **lf-diagram-client.js** - JavaScript client that handles interactivity
4. **diagram.css** - Styling for the web interface

### Current Status

**Phase 1: Basic Viewing** ✓ Implemented
- HTTP server serving diagram viewer
- Browser opens with interface
- Placeholder diagram display
- Click-to-navigate functionality

**Phase 2: KLighD Integration** 🚧 In Progress
- Currently shows placeholder diagram
- KLighD WebSocket connection needs LSP configuration
- Falls back gracefully with helpful error messages

**Phase 3: Live Sync** 📋 Planned
- Cursor position highlighting in diagram
- Real-time updates via WebSocket/SSE

**Phase 4: Advanced Features** 📋 Planned
- Zoom/pan controls (UI ready, backend pending)
- Export to SVG/PNG
- Multiple file support

## Troubleshooting

### Port Already in Use

If you get a port conflict error, change the port:

```lua
local diagram = require("lf.diagram")
diagram.config.port = 8766  -- Use a different port
```

### Browser Doesn't Open

If your browser doesn't open automatically:
1. Check the Neovim message for the URL
2. Manually open: `http://localhost:8765/?file=<your-file-uri>`
3. Set `browser_cmd` explicitly in config

### Python Not Found

The diagram viewer requires Python 3:

```bash
python3 --version  # Check if installed
```

If not installed, install Python 3 for your OS.

### Diagram Not Showing

Currently, the viewer shows a placeholder diagram because:
- The LSP server needs WebSocket configuration
- KLighD protocol needs to be fully discovered

The placeholder demonstrates the functionality and will be replaced with real
diagram data once the KLighD integration is complete.

## Development Notes

See `DIAGRAM_ARCHITECTURE.md` for technical details about:
- Implementation phases
- Protocol specifications
- WebSocket communication
- Sprotty integration

## Examples

### Basic Usage

```vim
" Open test.lf
:e test.lf

" Start diagram viewer
:LFDiagramOpen

" Make changes to the file
" Save the file
:w

" Browser will notify to refresh
" Click refresh button in browser

" Close when done
:LFDiagramClose
```

### Advanced Usage

```lua
-- Custom configuration
local diagram = require("lf.diagram")

-- Change port
diagram.config.port = 9000

-- Use specific browser
diagram.config.browser_cmd = "google-chrome"

-- Open diagram
diagram.open_interactive()

-- Later, close it
diagram.close()
```

## Next Steps

1. **Configure KLighD WebSocket** - Enable diagram generation from LSP server
2. **Implement Real Diagrams** - Replace placeholder with actual program diagrams
3. **Add Live Sync** - Cursor position highlighting
4. **Enhance Interactivity** - Zoom, pan, filter controls

## Feedback

If you encounter issues or have suggestions:
- Check the console output in the browser (F12 → Console)
- Check Neovim messages (`:messages`)
- Report issues with logs from both

## See Also

- `DIAGRAM_ARCHITECTURE.md` - Technical architecture document
- `doc/lf.txt` - Full plugin documentation
- [KLighD Project](https://github.com/kieler/KLighD)
- [Sprotty Framework](https://github.com/eclipse/sprotty)
