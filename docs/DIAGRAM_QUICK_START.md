# Diagram Viewer - Quick Start Guide

## Try It Now! 🚀

### 1. Open your LF file
```bash
cd /home/remi/Workspace/lingua-franca
nvim test.lf
```

### 2. Open the diagram viewer
```vim
:LFDiagramOpen
```

Your browser should open automatically with the diagram viewer!

### 3. Interact with the diagram
- **Click** on diagram elements to jump to code in Neovim
- **Hover** over elements to see them highlight
- **Use controls** to zoom, fit to view, or refresh

### 4. Close when done
```vim
:LFDiagramClose
```

## Quick Command Reference

```vim
:LFDiagramOpen     " Open interactive diagram in browser
:LFDiagramClose    " Stop the diagram server
:LFDiagramToggle   " Toggle server on/off
:LFDiagramInfo     " Show diagram information
```

## What You'll See

Currently, the viewer shows a **placeholder diagram** because the full KLighD
integration is still in progress. The placeholder demonstrates:
- ✅ Browser-based viewing
- ✅ Interactive elements
- ✅ Click-to-navigate
- ✅ Professional UI

## Troubleshooting

### Browser doesn't open?
- Check the Neovim message for the URL
- Manually open: `http://localhost:8765/?file=<file-uri>`

### Port already in use?
```lua
-- In Neovim
:lua require('lf.diagram').config.port = 8766
:LFDiagramOpen
```

### Server won't stop?
```vim
:LFDiagramClose
" If that doesn't work:
:!pkill -f lf_server.py
```

## What's Next?

Phase 2 will add:
- Real diagram generation from your LF code
- Actual reactor structure visualization
- More advanced interactions

For now, enjoy exploring the interface and testing the navigation features!

## More Information

- **Full Guide**: See `DIAGRAM_USAGE.md`
- **Technical Details**: See `DIAGRAM_ARCHITECTURE.md`
- **Testing**: See `TEST_CHECKLIST.md`
- **Summary**: See `DIAGRAM_IMPLEMENTATION_SUMMARY.md`

---

Happy diagramming! 📊
