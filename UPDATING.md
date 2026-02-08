# Updating for New LF Releases

This guide explains how to keep lf.nvim up-to-date with new Lingua Franca releases.

## LSP Server

The LSP server jar is built from the Lingua Franca compiler. When a new version is released:

### Automatic (CI)

A [weekly CI workflow](.github/workflows/build-lsp.yml) checks for new lf-lang releases and builds the LSP jar automatically. No action needed — new jars appear as [GitHub releases](https://github.com/remifan/lf.nvim/releases).

To trigger manually (e.g., for a fresh release):

```bash
# Auto-detect latest release
gh workflow run build-lsp.yml -R remifan/lf.nvim

# Or specify a version
gh workflow run build-lsp.yml -R remifan/lf.nvim -f lf_version=v0.11.0
```

### For Users

```vim
:LFLspInstall
```

This downloads the latest pre-built jar. Run it again when a new version is available.

## Syntax Highlighting

The fallback regex syntax (`syntax/lf.vim`) is derived from the VSCode extension's TextMate grammar. When a new version is released with new keywords:

### Option A: From within Neovim (Easiest)

```vim
" 1. Preview the updates
:LFUpdateSyntaxDryRun

" 2. Show extracted keywords
:LFShowKeywords

" 3. Apply the updates (auto-reloads syntax)
:LFUpdateSyntax
```

### Option B: Command Line

```bash
# Using Lua (works with Neovim's built-in Lua)
nvim -l scripts/update_syntax.lua --show-keywords
nvim -l scripts/update_syntax.lua --dry-run
nvim -l scripts/update_syntax.lua

# Or using Python
python3 scripts/update_syntax.py --show-keywords
python3 scripts/update_syntax.py --dry-run
python3 scripts/update_syntax.py

# Then reload in Neovim
nvim examples/hello.lf
# In Neovim: :e | :syntax sync fromstart
```

## How It Works

The update script:
1. Fetches `lflang.tmLanguage.json` from the VSCode extension repository
2. Extracts keywords from the TextMate grammar patterns
3. Updates `syntax/lf.vim` with new keywords while preserving structure
4. Keeps all embedded language support and custom highlighting intact

## What Gets Updated

The script automatically updates:
- **Core keywords**: `reactor`, `input`, `output`, `reaction`, etc.
- **Modifiers**: `public`, `private`, `widthof`, etc.
- **Booleans**: `true`, `false`, etc.
- **Control flow**: `if`, `else`, `for`, `while`
- **Time units**: `nsec`, `msec`, `sec`, etc.

## What Stays the Same

These are NOT modified by the update script:
- Embedded language support (C/C++, Python, Rust, TypeScript)
- Comment patterns
- String and number patterns
- Operator definitions
- Delimiter definitions
- Highlight group links

## Checking for Updates

### Automatic (CI)

A [weekly CI workflow](.github/workflows/sync-syntax.yml) checks the upstream VSCode extension grammar and opens a PR if keywords have changed. No action needed.

### Manual

```bash
# Compare with upstream
python3 scripts/update_syntax.py --dry-run
```

## Troubleshooting

### Script Fails to Connect

**Problem**: Cannot fetch grammar file from GitHub.

**Solutions**:
- Check your internet connection
- Verify the URL is still valid: https://github.com/lf-lang/vscode-lingua-franca
- Try downloading the file manually and modifying the script to read from local file

### No Changes Detected

**Problem**: Script says "No changes detected" but you expect updates.

**Reasons**:
- Your syntax file is already up-to-date
- New keywords might be in patterns not yet parsed by the script
- Grammar file structure may have changed

**Next Steps**:
1. Run `--show-keywords` to see what the script extracted
2. Manually check the grammar file for new patterns
3. Update the script's keyword extraction logic if needed

### Syntax Highlighting Breaks

**Problem**: After updating, highlighting doesn't work properly.

**Solutions**:
1. Restore previous version: `git checkout syntax/lf.vim`
2. Check for syntax errors: `:messages` in Neovim
3. Verify the file structure wasn't corrupted
4. Report the issue with details about what broke

## Manual Update Process

If the script doesn't work or you prefer manual updates:

1. **Download the grammar file**:
   ```bash
   curl -O https://raw.githubusercontent.com/lf-lang/vscode-lingua-franca/main/syntaxes/lflang.tmLanguage.json
   ```

2. **Search for keyword patterns**:
   ```bash
   # Look for patterns like: "match": "\\b(keyword1|keyword2)\\b"
   cat lflang.tmLanguage.json | grep -E '"match".*\\b\(' | less
   ```

3. **Edit `syntax/lf.vim`**:
   - Find the appropriate keyword section (search for `" Keywords - Core Language`)
   - Add new keywords to the `syn keyword` lines
   - Keep lines under 80 characters for readability

4. **Test the changes**:
   ```vim
   :e examples/hello.lf
   :syntax sync fromstart
   ```

## Advanced: Modifying the Update Script

If you need to customize the keyword extraction:

Edit `scripts/update_syntax.py`:
- `extract_keywords()`: Modify which grammar sections map to which categories
- `extract_keywords_from_match()`: Change how keywords are parsed from regex patterns
- `format_keywords()`: Adjust how keywords are formatted in the output

Example - adding a new keyword manually:
```python
keywords["core"].update([
    "your_new_keyword_here"
])
```

## Contributing Updates

If you update the syntax or improve the update script:

1. Test thoroughly with various `.lf` files
2. Run `:checkhealth` in Neovim to verify no issues
3. Create a pull request with:
   - Description of what changed
   - Example of new keyword highlighting
   - LF version that introduced the change

## Resources

- [Lingua Franca Documentation](https://www.lf-lang.org/)
- [VSCode Extension Repository](https://github.com/lf-lang/vscode-lingua-franca)
- [TextMate Grammar Guide](https://macromates.com/manual/en/language_grammars)
- [Vim Syntax Highlighting](https://vimhelp.org/syntax.txt.html)
