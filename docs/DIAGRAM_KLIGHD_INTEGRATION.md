# KLighD/Sprotty Integration Plan

## Current State vs. Target State

### Current Implementation ✅
- Uses `lfd` to generate static SVG
- Manual JavaScript for hover effects
- Basic click-to-navigate works
- **Limited**: No zoom, pan, expand/collapse, live updates

### VSCode Implementation (Target) 🎯
- Uses `@kieler/klighd-core` (Sprotty-based)
- WebSocket connection to Language Server
- Full interactive canvas with:
  - Zoom, pan (mouse wheel, drag)
  - Expand/collapse reactors
  - Layout options
  - Live diagram synthesis
  - Bidirectional sync

## Architecture Comparison

### Current (Static SVG)
```
Neovim → lfd → SVG file → HTTP server → Browser
                                           ↓
                                    Manual JS handlers
```

### VSCode (KLighD)
```
Browser (klighd-core) ←─ WebSocket ─→ Language Server (LanguageDiagramServer)
         ↓                                        ↓
    Sprotty Canvas                          KLighD Synthesis
    (Interactive)                           (Live Diagrams)
```

## Implementation Options

### Option 1: Full KLighD Integration (Best, Most Complex)

**Use the official KLighD stack exactly like VSCode**

#### Steps:

1. **Package the Frontend**
   ```bash
   # In nvim-plugin/html/
   npm init -y
   npm install @kieler/klighd-core@^0.7.0
   npm install sprotty-protocol@^1.3.0
   npm install vscode-ws-jsonrpc@^0.2.0
   npm install ws@^8.16.0
   ```

2. **Create WebSocket Proxy**
   - The Language Server runs with stdio (not WebSocket by default)
   - Need to create a WebSocket bridge in Lua or Python
   - Forward LSP messages between browser WebSocket and stdio

3. **Replace diagram-viewer.html**
   - Use klighd-core instead of custom JavaScript
   - Initialize Sprotty diagram container
   - Connect to WebSocket endpoint

4. **Start Language Diagram Server**
   ```lua
   -- Instead of regular LSP, start LanguageDiagramServer
   cmd = { "java", "-jar", "lsp-all.jar", "--socket", "5007" }
   ```

5. **Create WebSocket Bridge Server**
   ```python
   # Bridge between browser WebSocket and LSP stdio
   import asyncio
   import websockets
   import subprocess

   async def bridge(websocket, path):
       # Start LSP process
       lsp = subprocess.Popen(["java", "-jar", "lsp-all.jar"],
                              stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE)
       # Forward messages bidirectionally
       # ...
   ```

#### Benefits:
- ✅ Full feature parity with VSCode
- ✅ Uses official KLighD stack
- ✅ Future-proof (stays updated)
- ✅ All interactive features work

#### Challenges:
- ⚠️ Requires Node.js/npm setup
- ⚠️ Need to build/bundle JavaScript
- ⚠️ WebSocket bridge complexity
- ⚠️ More dependencies

---

### Option 2: Use klighd-cli (Easier Alternative)

**Leverage the existing klighd-cli tool**

The `klighd-cli` is a standalone web viewer that's already built!

#### Steps:

1. **Check if klighd-cli is available**
   ```bash
   # It might be in the LF Language Server distribution
   find /home/remi/Workspace/lingua-franca -name "*klighd*cli*"
   ```

2. **Or download/build it**
   ```bash
   git clone https://github.com/kieler/klighd-vscode.git
   cd klighd-vscode/applications/klighd-cli
   yarn install
   yarn build
   ```

3. **Start klighd-cli instead of our custom server**
   ```lua
   -- In diagram.lua
   vim.fn.jobstart({
     "klighd-cli",
     "--languageServer", lsp_jar_path,
     "--file", current_file,
     "--port", "8765"
   })
   ```

4. **Open browser to klighd-cli**
   ```lua
   vim.fn.jobstart({"xdg-open", "http://localhost:8765"})
   ```

#### Benefits:
- ✅ Uses official KLighD stack
- ✅ No custom JavaScript needed
- ✅ All features work out-of-box
- ✅ Simpler than Option 1

#### Challenges:
- ⚠️ Requires klighd-cli to be installed
- ⚠️ Need to bundle with plugin or document installation
- ⚠️ Less customization

---

### Option 3: Hybrid - Keep Current + Add Advanced Mode

**Keep current simple SVG approach, add KLighD as advanced feature**

```vim
:LFDiagramOpen       " Current static SVG (works now)
:LFDiagramOpenPro    " Full KLighD integration (requires setup)
```

#### Benefits:
- ✅ Current users not affected
- ✅ Simple mode always works
- ✅ Advanced users get full features

#### Implementation:
```lua
M.config = {
  diagram_mode = "simple", -- or "klighd"
  klighd_cli_path = nil,   -- Auto-detect or manual
}
```

---

## Recommended Approach

### Phase 1: Document What We Have ✅ (Done)
Current simple implementation with lfd works for basic needs.

### Phase 2: Try klighd-cli (Next Step)
1. Check if klighd-cli exists in LF distribution
2. If not, document how users can install it
3. Add `open_interactive_pro()` function
4. Test with klighd-cli

### Phase 3: Full Integration (Future)
If klighd-cli doesn't work well, implement Option 1 with npm packages.

---

## Testing klighd-cli Now

Let me check if we can use klighd-cli:

```bash
# Search for klighd-cli in LF repo
find /home/remi/Workspace/lingua-franca -name "*klighd*" -type f

# Or check if it can be downloaded
# The klighd-cli is distributed as a standalone tool
```

If found, we can integrate it immediately!

---

## Key Insight

The **VSCode extension doesn't implement diagram rendering itself** - it uses:
1. `@kieler/klighd-core` (the heavy lifting)
2. WebSocket connection to Language Server
3. Sprotty for the canvas

We should do the same instead of reinventing the wheel.

---

## Next Steps

1. **Investigate klighd-cli availability**
   - Check LF Language Server JAR for klighd-cli
   - Or build it from source
   - Or find pre-built distribution

2. **Prototype with klighd-cli**
   - Add `diagram_mode` config option
   - Implement `open_klighd()` function
   - Test with real LF Language Server

3. **Document Installation**
   - If klighd-cli required, add to plugin README
   - Provide installation instructions
   - Fall back to static SVG if not available

---

## Conclusion

Current implementation is **good for basic needs** but **limited for advanced features**.

For full VSCode-like experience, we need to use the official KLighD stack.

**Best path forward**: Try klighd-cli integration next!
