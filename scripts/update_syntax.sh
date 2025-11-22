#!/bin/bash
# Wrapper script to run the Lua update script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUA_SCRIPT="$SCRIPT_DIR/update_syntax.lua"

# Try to find a Lua interpreter
if command -v lua &> /dev/null; then
    lua "$LUA_SCRIPT" "$@"
elif command -v lua5.4 &> /dev/null; then
    lua5.4 "$LUA_SCRIPT" "$@"
elif command -v lua5.3 &> /dev/null; then
    lua5.3 "$LUA_SCRIPT" "$@"
elif command -v luajit &> /dev/null; then
    luajit "$LUA_SCRIPT" "$@"
elif command -v nvim &> /dev/null; then
    # Use Neovim's Lua interpreter
    nvim -l "$LUA_SCRIPT" "$@"
else
    echo "Error: No Lua interpreter found."
    echo "Please install lua, lua5.3, lua5.4, luajit, or neovim"
    exit 1
fi
