# Maintenance Scripts

This directory contains scripts to help maintain and update the Lingua Franca Neovim plugin.

## Available Scripts

### update_syntax.lua (Recommended)

Native Lua script that works with Neovim's built-in Lua interpreter.

**From within Neovim:**
```vim
:LFUpdateSyntax              " Update syntax
:LFUpdateSyntaxDryRun        " Preview changes
:LFShowKeywords              " Show extracted keywords
```

**From command line:**
```bash
nvim -l scripts/update_syntax.lua --dry-run
nvim -l scripts/update_syntax.lua --show-keywords
nvim -l scripts/update_syntax.lua
```

### update_syntax.sh

Wrapper script that auto-detects available Lua interpreters (lua, lua5.3, lua5.4, luajit, nvim).

```bash
./scripts/update_syntax.sh --dry-run
./scripts/update_syntax.sh --show-keywords
./scripts/update_syntax.sh
```

### update_syntax.py

Python version for environments where Lua/Neovim is not available.

```bash
python3 scripts/update_syntax.py --dry-run
python3 scripts/update_syntax.py --show-keywords
python3 scripts/update_syntax.py
```

## What These Scripts Do

1. Fetch the latest `lflang.tmLanguage.json` from the VSCode extension repository
2. Extract all keywords, modifiers, booleans, and time units
3. Update `syntax/lf.vim` with the new keywords while preserving the rest of the file

## Requirements

**Lua script:**
- Neovim (recommended), or lua/lua5.3/lua5.4/luajit
- curl (for fetching the grammar file)
- Internet connection

**Python script:**
- Python 3.6+
- Internet connection

## When to Use

These scripts are run automatically by the [sync-syntax CI workflow](../.github/workflows/sync-syntax.yml) on a weekly schedule. A PR is opened if keywords have changed.

You can also run them manually:
- When you notice missing keyword highlighting
- To preview upcoming changes before the CI runs

## Manual Update Process

If you prefer to update manually or the script doesn't work:

1. Visit: https://github.com/lf-lang/vscode-lingua-franca/blob/main/syntaxes/lflang.tmLanguage.json

2. Look for keyword patterns in the `repository` section, such as:
   ```json
   "match": "\\b(reactor|input|output|action)\\b"
   ```

3. Add new keywords to the appropriate section in `syntax/lf.vim`:
   ```vim
   " Keywords - Core Language
   syn keyword lfKeyword reactor federated main realtime
   syn keyword lfKeyword input output action state timer
   " ... add new keywords here
   ```

4. Test by opening a `.lf` file and checking if the new keywords are highlighted

## Troubleshooting

**Script fails to fetch grammar:**
- Check your internet connection
- The VSCode extension repository may have moved - check the URL in the script

**Keywords not appearing:**
- The grammar structure may have changed - you may need to update the extraction logic
- Some keywords might be in different patterns - check the grammar JSON manually

**Syntax highlighting broken after update:**
- Restore the previous `syntax/lf.vim` from git
- Run with `--dry-run` first to preview changes
- Report the issue with the grammar structure
