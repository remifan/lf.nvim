# Testing KLighD Pro Mode

## Quick Test Steps

1. **Open a test file in Neovim:**
   ```bash
   cd /home/remi/Workspace/lingua-franca
   nvim test.lf
   ```

2. **Run the Pro mode command:**
   ```vim
   :LFDiagramOpenPro
   ```

3. **Check the logs:**

   **In Neovim** (`:messages`):
   - Should see: "Starting WebSocket bridge..."
   - Should see: "WebSocket bridge started on port 5007"
   - Should see: "Starting HTTP server..."
   - Should see: "Opening KLighD diagram viewer..."

   **In Browser Console** (F12):
   - Should see: "WebSocket connected"
   - Should see: "LSP connection established"
   - Should see: "Sending request: initialize {..."
   - Should see: "Received message from LSP: {..."
   - Should see: "Request response: {..."
   - Should see: "Sending notification: initialized {}"
   - Should see: "Sending notification: textDocument/didOpen {..."
   - Should see: "Sending notification: diagram/dispatch {..."

## What Each Log Means

### Browser Logs
- **"WebSocket connected"** → Browser connected to Python bridge on port 5007
- **"Sending request: initialize"** → Browser sent LSP initialize to server
- **"Received message from LSP"** → Python bridge forwarded LSP response
- **"Request response"** → LSP responded with capabilities
- **"Sending notification: textDocument/didOpen"** → Opened the LF file in LSP
- **"Sending notification: diagram/dispatch"** → Requested diagram model
- **"Received diagram action"** → LSP sent diagram data back!

### Python Bridge Logs (in Neovim `:messages`)
- **"Client → LSP:"** → Message sent from browser to LSP stdin
- **"LSP → Client:"** → Message received from LSP stdout

## Expected Flow

```
Browser                  Python Bridge           LSP Server
   |                           |                      |
   |--WebSocket connect------->|                      |
   |<------connected-----------|                      |
   |                           |                      |
   |--initialize request------>|--stdio-------------->|
   |                           |                      |
   |                           |<-----response--------|
   |<------response------------|                      |
   |                           |                      |
   |--initialized notif------->|--stdio-------------->|
   |                           |                      |
   |--didOpen notif----------->|--stdio-------------->|
   |                           |                      |
   |--diagram/dispatch-------->|--stdio-------------->|
   |                           |                      |
   |                           |<---diagram/accept----|
   |<--diagram model-----------|                      |
   |                           |                      |
   [Diagram renders!]
```

## Troubleshooting

### "Connecting to Language Server..." stuck
- Check browser console for errors
- Check if WebSocket connected (should see "WebSocket connected")
- Check if any requests were sent (should see "Sending request: initialize")
- If no requests sent: JavaScript error, check console
- If requests sent but no response: Python bridge or LSP issue

### WebSocket connection fails
- Verify port 5007 is not in use: `lsof -i :5007`
- Check if Python bridge started: look for "WebSocket bridge started" in `:messages`
- Check if websockets module installed: `python3 -c "import websockets"`

### LSP not responding
- Check `:messages` for LSP errors
- Look for "LSP:" prefixed messages showing LSP stderr output
- Verify LSP jar path is correct in config
- Try running LSP manually: `java -jar /path/to/lsp.jar`

### Diagram doesn't render
- Check if "Received diagram action" appears in console
- Check if Sprotty container initialized (look for Sprotty logs)
- Verify @kieler/klighd-core is properly loaded

## Debugging Commands

**Check processes:**
```bash
ps aux | grep -E 'python.*websocket|python.*http.server'
```

**Check ports:**
```bash
lsof -i :5007  # WebSocket bridge
lsof -i :8765  # HTTP server
```

**Stop all services:**
```vim
:LFDiagramClosePro
```

**Restart with fresh logs:**
```vim
:LFDiagramClosePro
:messages clear
:LFDiagramOpenPro
```

## Success Indicators

✅ Browser opens with "Lingua Franca Diagram Viewer" header
✅ Status indicator turns green (connected)
✅ Interactive diagram canvas appears
✅ Can zoom with mouse wheel
✅ Can pan by dragging
✅ Elements are clickable/hoverable

## Next Steps After Success

Once it works, you can:
- Compare with simple mode: `:LFDiagramClose` then `:LFDiagramOpen`
- Try different LF files
- Test diagram updates when editing files
- Explore KLighD features (expand/collapse, layout options)
