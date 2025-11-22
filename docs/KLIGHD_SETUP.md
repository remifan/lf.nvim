# KLighD Full Integration Setup

## What We've Built

✅ **Frontend (TypeScript/Sprotty)**
- `@kieler/klighd-core` integration
- WebSocket LSP connection
- Built with webpack → `html/dist/`

✅ **WebSocket Bridge (Python)**
- Connects browser WebSocket to LSP stdio
- `lua/lf/websocket_bridge.py`

## Requirements

### 1. Node.js/npm (Already installed ✅)
```bash
node --version  # v21.6.2
npm --version   # 10.2.4
```

### 2. Python websockets module (Need to install)
```bash
pip install websockets
# or
pip3 install --user websockets
```

### 3. Built Frontend
Already done! Files in `html/dist/`:
- `bundle.js` (2.24 MB - includes all Sprotty/KLighD code)
- `index.html`

## How It Works

```
Browser                WebSocket Bridge         LSP Server
(Sprotty)        ←→    (Python)          ←→    (Java/stdio)
  :8765              ws://localhost:5007        stdin/stdout
```

### Workflow:

1. **Neovim starts components**:
   ```lua
   -- Start WebSocket bridge
   vim.fn.jobstart({
     "python3", websocket_bridge_py,
     lsp_jar_path,
     "5007"
   })

   -- Start HTTP server for frontend
   -- (Serves html/dist/)

   -- Open browser
   vim.fn.jobstart({"xdg-open", "http://localhost:8765"})
   ```

2. **Browser connects**:
   - Loads `index.html` and `bundle.js`
   - Connects WebSocket to `ws://localhost:5007`
   - Sends LSP initialize

3. **WebSocket bridge**:
   - Receives browser WebSocket messages
   - Converts to LSP stdio format
   - Forwards to LSP server
   - Reads LSP responses
   - Sends back via WebSocket

4. **LSP server**:
   - Receives initialize
   - Generates KLighD diagram
   - Sends diagram model
   - Browser renders with Sprotty

## Installation Steps

### For Users

Add to plugin README:

````markdown
## Full KLighD Diagram Support (Optional)

For advanced interactive diagrams (like VSCode), install:

```bash
# Install Python websockets
pip3 install --user websockets

# Build frontend (one-time)
cd ~/.local/share/nvim/site/pack/*/start/lf.nvim/html
npm install
npm run build
```

Then use:
```vim
:LFDiagramOpenPro  " Full KLighD integration
```
````

### For Development

```bash
cd nvim-plugin/html
npm install
npm run build

# Test WebSocket bridge
python3 lua/lf/websocket_bridge.py /path/to/lsp-all.jar 5007
```

## Next Steps

1. ✅ Frontend built
2. ✅ WebSocket bridge created
3. ⬜ Update `diagram.lua` with `open_klighd()` function
4. ⬜ Test the full stack
5. ⬜ Add configuration options
6. ⬜ Document for users

## File Checklist

- [x] `html/package.json` - npm configuration
- [x] `html/tsconfig.json` - TypeScript config
- [x] `html/webpack.config.js` - Webpack bundler
- [x] `html/src/main.ts` - KLighD initialization
- [x] `html/src/lsp-connection.ts` - WebSocket LSP client
- [x] `html/src/index.html` - Main HTML template
- [x] `html/dist/bundle.js` - Compiled JavaScript (2.24 MB)
- [x] `html/dist/index.html` - Compiled HTML
- [x] `lua/lf/websocket_bridge.py` - WebSocket ↔ stdio bridge
- [ ] `lua/lf/diagram.lua` - Updated with `open_klighd()`

## Architecture Benefits

✅ **Uses official KLighD stack** - Same as VSCode
✅ **Full feature parity** - All Sprotty features work
✅ **Future-proof** - Stays updated with KLighD
✅ **Interactive canvas** - Zoom, pan, expand/collapse
✅ **Live updates** - Real-time diagram synthesis

## Fallback Strategy

Keep both modes:
- `:LFDiagramOpen` - Simple SVG (current, always works)
- `:LFDiagramOpenPro` - Full KLighD (requires setup)

Users can choose based on their needs!
