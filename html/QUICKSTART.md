# KLighD Pro Mode - Quick Start

## 🚀 One-Time Setup

```bash
pip3 install --user websockets
```

That's it! The frontend is already built.

## 🎯 Usage

```vim
" Open an LF file
:e test.lf

" Launch Pro mode
:LFDiagramOpenPro

" Press F12 in browser to see logs
" Check :messages in Neovim for backend logs

" When done:
:LFDiagramClosePro
```

## 📊 What to Expect

1. Neovim will show:
   - "Starting WebSocket bridge..."
   - "WebSocket bridge started on port 5007"
   - "Starting HTTP server..."
   - "Opening KLighD diagram viewer..."

2. Browser will open showing:
   - Header: "Lingua Franca Diagram Viewer"
   - Status: "Connecting to Language Server..."
   - Then: Status indicator turns green
   - Finally: Interactive diagram appears!

3. Browser Console (F12) will show:
   ```
   WebSocket connected
   Sending request: initialize
   Received message from LSP
   Request response: {capabilities: ...}
   Sending notification: textDocument/didOpen
   Sending notification: diagram/dispatch
   Received diagram action: {action: ...}
   ```

## 🐛 Troubleshooting

**Stuck on "Connecting..."?**
- Open browser console (F12) - look for errors
- Check Neovim `:messages` - look for LSP errors
- Verify: `python3 -c "import websockets"`

**Port already in use?**
```vim
:LFDiagramClosePro
```

**Need to rebuild?**
```bash
cd /home/remi/Workspace/lingua-franca/nvim-plugin/html
npm run build
```

## 📚 More Info

- **Testing Guide:** `TEST_KLIGHD.md`
- **Full Status:** `STATUS.md`
- **Setup Details:** `../KLIGHD_SETUP.md`
- **Architecture:** `../KLIGHD_COMPLETE.md`
