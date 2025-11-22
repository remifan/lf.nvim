# Lingua Franca Diagram Viewer Architecture

**Status:** Architecture Design Document
**Target:** Interactive web-based diagram viewer for Neovim
**Estimated Implementation:** 4-6 hours over 1-2 sessions

## Executive Summary

This document describes the architecture for an interactive, web-based diagram viewer that integrates with the Neovim LF plugin. The viewer will provide VSCode-like diagram capabilities with bidirectional synchronization between code and diagrams.

## Goals

1. **Interactive Diagrams** - Zoom, pan, click elements
2. **Bidirectional Sync** - Click diagram → jump to code, cursor in code → highlight in diagram
3. **Live Updates** - Diagram updates as code changes
4. **Reuse Existing Infrastructure** - Use KLighD LSP server (already running)
5. **No Server Modifications** - Zero changes to Java LSP server

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Neovim (lf.nvim)                        │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  lua/lf/diagram_server.lua                                │  │
│  │  - Lightweight HTTP server (Lua socket or Python)        │  │
│  │  - Serves static HTML/JS/CSS                             │  │
│  │  - Provides RPC endpoint for browser → Neovim           │  │
│  │  - Monitors cursor position and sends to browser         │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  lua/lf/diagram.lua (enhanced)                            │  │
│  │  - Start/stop diagram server                              │  │
│  │  - Open browser with diagram URL                          │  │
│  │  - Handle click-to-navigate from browser                  │  │
│  │  - Send cursor updates to browser                         │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                            ↕ HTTP/WebSocket
┌─────────────────────────────────────────────────────────────────┐
│              Web Browser (http://localhost:8765)                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  html/diagram-viewer.html                                 │  │
│  │  - Main HTML page                                         │  │
│  │  - Loads Sprotty.js and KLighD diagram libraries         │  │
│  │  - Renders interactive diagram                            │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  js/lf-diagram-client.js                                  │  │
│  │  - Connects to LSP server via WebSocket                  │  │
│  │  - Requests diagram data from KLighD                      │  │
│  │  - Renders diagram using Sprotty                          │  │
│  │  - Handles click events → send to Neovim                 │  │
│  │  - Receives cursor updates from Neovim                    │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                            ↕ LSP/WebSocket
┌─────────────────────────────────────────────────────────────────┐
│       LF Language Server (KLighD Diagram Server)                │
│  - Already running as part of LSP                               │
│  - Provides KLighD diagram generation                           │
│  - Handles diagram layout and rendering                         │
│  - Provides element metadata (positions, types, etc.)           │
└─────────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. Neovim Diagram Server (`lua/lf/diagram_server.lua`)

**Responsibility:** Lightweight HTTP server to serve diagram viewer and handle RPC

**Implementation Options:**

#### Option A: Lua Socket (Preferred)
```lua
-- Use LuaSocket for HTTP server
local socket = require("socket")
local server = socket.bind("127.0.0.1", 8765)

-- Serve static files (HTML/JS/CSS)
-- Handle POST requests for RPC (jump to line, etc.)
```

**Pros:** Pure Lua, no external dependencies
**Cons:** Need to implement HTTP parsing

#### Option B: Python HTTP Server (Simpler)
```lua
-- Start Python HTTP server as subprocess
vim.fn.jobstart({
  "python3", "-m", "http.server", "8765",
  "--directory", vim.fn.expand("~/.config/nvim/lf-diagrams")
})
```

**Pros:** Built-in HTTP server, no parsing needed
**Cons:** Requires Python (but usually available)

#### Option C: Neovim RPC Server (Best for bidirectional sync)
```lua
-- Use Neovim's built-in RPC capabilities
-- Browser connects via msgpack-rpc over TCP
vim.fn.serverstart("127.0.0.1:8765")
```

**Pros:** Built-in Neovim feature, efficient binary protocol
**Cons:** Browser needs msgpack library

**Recommended:** Start with Option B (Python), migrate to Option C for better performance

**API Endpoints:**

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/` | GET | Serve diagram viewer HTML |
| `/js/*` | GET | Serve JavaScript files |
| `/css/*` | GET | Serve CSS files |
| `/api/jump` | POST | Jump to line in Neovim |
| `/api/cursor` | GET | Get current cursor position (SSE) |
| `/api/file` | GET | Get current file URI |

**Data Structures:**

```lua
-- Server state
M.server = {
  process = nil,           -- HTTP server process
  port = 8765,            -- Default port
  current_file = nil,     -- Current LF file URI
  cursor_position = {},   -- { line, col }
  browser_connected = false,
}

-- RPC message format (JSON)
{
  type = "jump_to_line",
  file = "file:///path/to/file.lf",
  line = 42,
  column = 10
}
```

---

### 2. Enhanced Diagram Module (`lua/lf/diagram.lua`)

**New Functions:**

```lua
-- Start diagram server and open browser
function M.open_interactive()
  -- 1. Start HTTP server
  local server = require("lf.diagram_server")
  server.start()

  -- 2. Get current file URI
  local uri = vim.uri_from_bufnr(0)

  -- 3. Open browser with diagram URL
  local url = string.format("http://localhost:8765/?file=%s", uri)
  vim.fn.jobstart({"xdg-open", url})  -- or "open" on macOS

  -- 4. Setup autocmds for live updates
  setup_live_updates()
end

-- Send cursor position to browser
function M.send_cursor_update()
  local pos = vim.api.nvim_win_get_cursor(0)
  local uri = vim.uri_from_bufnr(0)

  -- POST to server which forwards to browser
  server.broadcast({
    type = "cursor_update",
    file = uri,
    line = pos[1],
    column = pos[2]
  })
end

-- Handle click from browser
function M.handle_click(data)
  -- data = { file, line, column, element_id }

  -- Open file if different
  if vim.uri_to_fname(data.file) ~= vim.fn.expand("%:p") then
    vim.cmd("edit " .. vim.uri_to_fname(data.file))
  end

  -- Jump to line
  vim.api.nvim_win_set_cursor(0, {data.line, data.column})
end

-- Setup live updates on cursor move and buffer change
local function setup_live_updates()
  local augroup = vim.api.nvim_create_augroup("LFDiagram", {})

  -- Send cursor updates (throttled)
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    pattern = "*.lf",
    callback = function()
      M.send_cursor_update()
    end
  })

  -- Refresh diagram on save
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = augroup,
    pattern = "*.lf",
    callback = function()
      server.broadcast({ type = "refresh" })
    end
  })
end
```

**Commands:**

```vim
:LFDiagramOpen    " Open interactive diagram in browser
:LFDiagramClose   " Close diagram server
:LFDiagramReload  " Force diagram refresh
:LFDiagramToggle  " Toggle diagram server
```

---

### 3. Web Diagram Viewer (`html/diagram-viewer.html`)

**Dependencies:**

1. **Sprotty** - Diagram rendering framework (used by KLighD)
   - https://github.com/eclipse/sprotty
   - CDN: https://cdn.jsdelivr.net/npm/sprotty/

2. **KLighD Web Libraries** - Optional, if needed
   - From klighd-vscode packages
   - May need to bundle or use CDN

**HTML Structure:**

```html
<!DOCTYPE html>
<html>
<head>
  <title>Lingua Franca Diagram</title>
  <script src="https://cdn.jsdelivr.net/npm/sprotty@0.13.0/lib/pack.min.js"></script>
  <script src="js/lf-diagram-client.js"></script>
  <link rel="stylesheet" href="css/diagram.css">
</head>
<body>
  <div id="diagram-container"></div>
  <div id="status">Connecting to LSP server...</div>

  <script>
    // Get file from URL params
    const params = new URLSearchParams(window.location.search);
    const fileUri = params.get('file');

    // Initialize diagram client
    const client = new LFDiagramClient({
      container: 'diagram-container',
      fileUri: fileUri,
      lspServerUrl: 'ws://localhost:5007',  // LSP WebSocket
      neovimRpcUrl: 'http://localhost:8765/api'
    });

    client.connect();
  </script>
</body>
</html>
```

---

### 4. JavaScript Diagram Client (`js/lf-diagram-client.js`)

**Core Responsibilities:**

1. Connect to LSP server via WebSocket
2. Request diagram data using KLighD protocol
3. Render diagram using Sprotty
4. Handle user interactions (click, zoom, pan)
5. Communicate with Neovim for bidirectional sync

**Pseudocode:**

```javascript
class LFDiagramClient {
  constructor(options) {
    this.container = document.getElementById(options.container);
    this.fileUri = options.fileUri;
    this.lspWs = null;  // WebSocket to LSP server
    this.neovimUrl = options.neovimRpcUrl;
    this.sprotty = null;  // Sprotty diagram
  }

  async connect() {
    // 1. Connect to LSP server
    this.lspWs = new WebSocket('ws://localhost:5007');

    this.lspWs.onopen = () => {
      console.log('Connected to LSP server');
      this.requestDiagram();
    };

    this.lspWs.onmessage = (event) => {
      const msg = JSON.parse(event.data);
      this.handleLspMessage(msg);
    };

    // 2. Connect to Neovim for cursor updates (Server-Sent Events)
    this.neovimEventSource = new EventSource(this.neovimUrl + '/cursor');
    this.neovimEventSource.onmessage = (event) => {
      const cursor = JSON.parse(event.data);
      this.highlightElement(cursor);
    };
  }

  requestDiagram() {
    // Send LSP request for diagram
    // KLighD uses custom LSP protocol
    const request = {
      jsonrpc: '2.0',
      id: 1,
      method: 'keith/diagram',  // KLighD endpoint
      params: {
        uri: this.fileUri
      }
    };

    this.lspWs.send(JSON.stringify(request));
  }

  handleLspMessage(msg) {
    if (msg.id === 1) {
      // Diagram data received
      const diagramData = msg.result;
      this.renderDiagram(diagramData);
    }
  }

  renderDiagram(data) {
    // Initialize Sprotty with KLighD diagram data
    this.sprotty = new SprottyDiagram({
      container: this.container,
      model: data,
      onClick: (element) => this.handleClick(element)
    });
  }

  handleClick(element) {
    // User clicked diagram element
    // Send to Neovim to jump to code
    fetch(this.neovimUrl + '/jump', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        file: element.sourceUri,
        line: element.sourceLine,
        column: element.sourceColumn
      })
    });
  }

  highlightElement(cursor) {
    // Highlight diagram element based on cursor position
    const element = this.findElementAtPosition(cursor.line, cursor.column);
    if (element) {
      this.sprotty.highlight(element.id);
    }
  }

  refresh() {
    // Called when file is saved
    this.requestDiagram();
  }
}
```

---

## KLighD LSP Protocol

### Research Needed

The exact LSP protocol for KLighD diagrams needs to be discovered. Key endpoints:

1. **Diagram Request**
   ```json
   {
     "jsonrpc": "2.0",
     "method": "keith/diagram",
     "params": {
       "uri": "file:///path/to/file.lf",
       "clientId": "neovim-lf",
       "diagramType": "main"
     }
   }
   ```

2. **Diagram Update Notification**
   ```json
   {
     "jsonrpc": "2.0",
     "method": "diagram/update",
     "params": {
       "uri": "file:///path/to/file.lf",
       "model": { /* Sprotty model */ }
     }
   }
   ```

3. **Element Selection**
   ```json
   {
     "jsonrpc": "2.0",
     "method": "diagram/select",
     "params": {
       "elementId": "reactor.Hello",
       "position": { "line": 5, "character": 10 }
     }
   }
   ```

**To Discover Protocol:**

1. Run VSCode extension with `klighd-vscode`
2. Enable LSP logging
3. Observe WebSocket traffic between browser and LSP server
4. Document exact message formats

**Alternative:** Check KLighD source code:
- https://github.com/kieler/KLighD
- https://github.com/kieler/klighd-vscode

---

## Implementation Phases

### Phase 1: Basic Diagram Viewing (2-3 hours)

**Goal:** Display static diagram in browser

**Tasks:**
1. ✅ Create `lua/lf/diagram_server.lua` with Python HTTP server
2. ✅ Create `html/diagram-viewer.html` with basic layout
3. ✅ Add `:LFDiagramOpen` command
4. ✅ Test: Open browser and see "Loading diagram..."
5. ✅ Connect to LSP server WebSocket
6. ✅ Request diagram data (discover correct protocol)
7. ✅ Display diagram using Sprotty

**Success Criteria:** Browser shows LF diagram for current file

---

### Phase 2: Click-to-Navigate (1 hour)

**Goal:** Click diagram element → jump to code in Neovim

**Tasks:**
1. ✅ Add click handlers in JavaScript
2. ✅ Implement `/api/jump` endpoint in Neovim
3. ✅ Handle POST request and jump to line
4. ✅ Test: Click reactor → Neovim jumps to definition

**Success Criteria:** Clicking any diagram element jumps to corresponding code

---

### Phase 3: Cursor Sync (1-2 hours)

**Goal:** Cursor in code → highlight in diagram

**Tasks:**
1. ✅ Add `CursorMoved` autocmd in Neovim
2. ✅ Implement Server-Sent Events endpoint `/api/cursor`
3. ✅ Send cursor position updates (throttled)
4. ✅ Receive in JavaScript via EventSource
5. ✅ Find diagram element at cursor position
6. ✅ Highlight element in diagram

**Success Criteria:** Moving cursor in code highlights diagram element

---

### Phase 4: Live Updates (30 mins)

**Goal:** Save file → diagram refreshes

**Tasks:**
1. ✅ Add `BufWritePost` autocmd
2. ✅ Send refresh notification to browser
3. ✅ Browser requests new diagram
4. ✅ Update Sprotty model

**Success Criteria:** Saving file shows updated diagram

---

### Phase 5: Polish & Features (1 hour)

**Optional enhancements:**
- Zoom controls
- Layout options (horizontal/vertical)
- Filter views (show only reactors, hide internals)
- Export diagram as SVG/PNG
- Multiple file support (tabs in browser)
- Dark mode sync with Neovim

---

## File Structure

```
nvim-plugin/
├── lua/lf/
│   ├── diagram_server.lua      # HTTP server for browser
│   └── diagram.lua             # Enhanced diagram module
├── html/
│   ├── diagram-viewer.html     # Main viewer page
│   ├── js/
│   │   ├── lf-diagram-client.js  # Diagram client
│   │   └── sprotty-adapter.js    # Sprotty helpers
│   └── css/
│       └── diagram.css         # Diagram styling
└── DIAGRAM_ARCHITECTURE.md     # This document
```

---

## Testing Plan

### Unit Tests

1. **Neovim Server**
   - Start/stop server
   - Handle RPC requests
   - Cursor position tracking

2. **JavaScript Client**
   - WebSocket connection
   - Diagram rendering
   - Click handling

### Integration Tests

1. **End-to-End**
   - Open diagram → browser opens
   - Click element → Neovim jumps
   - Move cursor → diagram highlights
   - Save file → diagram updates

### Test Files

Use existing LF examples:
- `test.lf` (simple Hello World)
- Complex examples from `test/` directory
- Multi-file projects

---

## Known Challenges & Solutions

### Challenge 1: KLighD Protocol Discovery

**Problem:** Exact LSP protocol for diagrams is undocumented

**Solutions:**
1. Study klighd-vscode source code
2. Run VSCode with logging enabled
3. Contact KIELER/KLighD team
4. Reverse-engineer from network traffic

**Fallback:** Use simpler SVG generation if WebSocket protocol is too complex

---

### Challenge 2: WebSocket Port Conflict

**Problem:** LSP server may not expose WebSocket on expected port

**Solutions:**
1. Configure LSP server to use specific port (check launch args)
2. Use stdio + proxy (convert stdio LSP to WebSocket)
3. Modify server startup in `lsp.lua` to add WebSocket support

**Current LSP Server Launch:**
```lua
cmd = { "java", "-Xmx2G", "-jar", "/path/to/lsp-all.jar" }
```

**May Need:**
```lua
cmd = { "java", "-Xmx2G", "-jar", "/path/to/lsp-all.jar",
        "--socket", "5007" }  -- Enable WebSocket
```

---

### Challenge 3: Browser Security (CORS)

**Problem:** Browser may block WebSocket connections due to CORS

**Solutions:**
1. Serve diagram viewer from same origin as WebSocket (same port)
2. Configure LSP server to allow CORS
3. Use browser extension to disable CORS for localhost

---

### Challenge 4: Performance with Large Diagrams

**Problem:** Complex LF programs may have huge diagrams

**Solutions:**
1. Enable diagram filtering (show only top-level)
2. Lazy loading for nested reactors
3. Virtual scrolling for large diagrams
4. Limit diagram depth

---

## Alternative: Simpler SVG-Based Approach

If KLighD WebSocket protocol is too complex, use simpler approach:

### Architecture (Simplified)

```
Neovim → LSP (export SVG) → HTTP server serves SVG → Browser displays
       ↓                                              ↑
       Click map embedded in SVG ──────────────────────┘
```

**Benefits:**
- Much simpler (no WebSocket, no Sprotty)
- Works with any browser
- Easy to implement

**Limitations:**
- Less interactive
- No live updates (need to regenerate SVG)
- Harder to implement advanced features

**Implementation:**
1. Add LSP endpoint to export diagram as SVG with click map
2. Serve SVG via Python HTTP server
3. Embed click handlers in SVG
4. Use `window.opener` to communicate with Neovim

---

## Dependencies Summary

### Neovim Side
- **LuaSocket** (optional, for Lua HTTP server)
- **Python 3** (for simple HTTP server)
- No external Lua dependencies

### Browser Side
- **Sprotty.js** - Diagram rendering (CDN available)
- **Standard Web APIs** - WebSocket, EventSource, Fetch

### LSP Server Side
- **No modifications needed** - Use existing KLighD integration

---

## Configuration

Users should be able to customize:

```lua
require("lf").setup({
  diagram = {
    enabled = true,
    port = 8765,              -- Diagram viewer port
    lsp_port = 5007,          -- LSP WebSocket port (if needed)
    auto_open = false,        -- Auto-open on :LFDiagramOpen
    browser_cmd = "firefox",  -- Browser command
    live_update = true,       -- Update on cursor move
    throttle_ms = 100,        -- Cursor update throttle
  }
})
```

---

## Documentation for Users

Add to `doc/lf.txt`:

```
DIAGRAM VIEWER                                              *lf-diagrams*

The LF plugin provides an interactive diagram viewer that displays your
Lingua Franca program structure in a web browser.

:LFDiagramOpen                                           *:LFDiagramOpen*
  Opens the interactive diagram viewer in your default browser.
  The diagram shows reactors, ports, connections, and can be:
  - Zoomed and panned
  - Clicked to jump to code
  - Live-updated as you edit

:LFDiagramClose                                         *:LFDiagramClose*
  Closes the diagram server and browser.

BIDIRECTIONAL SYNC~

When the diagram viewer is open:
- Click elements in diagram → jumps to code in Neovim
- Move cursor in code → highlights element in diagram
- Save file → diagram updates automatically

REQUIREMENTS~

- Web browser (Chrome, Firefox, Safari, etc.)
- Python 3 (for diagram server)
- Internet connection (for Sprotty CDN)
```

---

## Next Steps for Implementation

1. **Study klighd-vscode** - Understand exact WebSocket protocol
2. **Prototype basic server** - Get HTTP server working
3. **Test LSP connection** - Verify can connect to KLighD
4. **Implement Phase 1** - Basic diagram viewing
5. **Iterate on features** - Add interactivity incrementally

---

## References

- KLighD: https://github.com/kieler/KLighD
- klighd-vscode: https://github.com/kieler/klighd-vscode
- Sprotty: https://github.com/eclipse/sprotty
- LSP Specification: https://microsoft.github.io/language-server-protocol/
- LF VSCode Extension: https://github.com/lf-lang/vscode-lingua-franca

---

## Questions to Resolve

1. What is the exact WebSocket endpoint for KLighD diagrams?
2. Does the LSP server need special launch args for WebSocket?
3. What is the Sprotty model format returned by KLighD?
4. How to map diagram elements back to source locations?
5. Can we reuse klighd-cli instead of building from scratch?

---

**Document Status:** Complete Architecture Design
**Ready for Implementation:** Yes
**Estimated Total Time:** 4-6 hours
**Priority:** Medium (enhance existing plugin first, then add diagrams)
