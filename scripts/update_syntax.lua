#!/usr/bin/env lua
--[[
Update Lingua Franca Neovim syntax from VSCode extension grammar.

This script fetches the latest TextMate grammar from the VSCode extension
repository and generates an updated syntax/lf.vim file.

Usage:
    lua scripts/update_syntax.lua
    lua scripts/update_syntax.lua --dry-run    # Preview changes without writing
    lua scripts/update_syntax.lua --show-keywords  # Show extracted keywords
--]]

local GRAMMAR_URL = "https://raw.githubusercontent.com/lf-lang/vscode-lingua-franca/main/syntaxes/lflang.tmLanguage.json"

-- Determine the script directory and syntax file path
local script_dir = arg[0]:match("(.*/)")
local syntax_file = script_dir and script_dir .. "../syntax/lf.vim" or "syntax/lf.vim"

-- Check if running inside Neovim
local is_nvim = vim ~= nil

-- Parse command line arguments
local args = {
    dry_run = false,
    show_keywords = false,
}

for _, arg_val in ipairs(arg) do
    if arg_val == "--dry-run" then
        args.dry_run = true
    elseif arg_val == "--show-keywords" then
        args.show_keywords = true
    elseif arg_val == "--help" or arg_val == "-h" then
        print("Usage: lua update_syntax.lua [--dry-run] [--show-keywords]")
        os.exit(0)
    end
end

-- JSON decoder
local json = {}

function json.decode(str)
    -- Simple JSON decoder for basic structures
    -- This handles the grammar file structure we need
    local function decode_value(s, pos)
        local ws = "[ \t\n\r]*"

        -- Skip whitespace
        pos = s:match("^" .. ws .. "()", pos)

        local char = s:sub(pos, pos)

        -- null
        if s:sub(pos, pos + 3) == "null" then
            return nil, pos + 4
        end

        -- boolean
        if s:sub(pos, pos + 3) == "true" then
            return true, pos + 4
        end
        if s:sub(pos, pos + 4) == "false" then
            return false, pos + 5
        end

        -- number
        if char:match("[%-0-9]") then
            local num_str = s:match("^([%-]?%d+%.?%d*[eE]?[%+%-]?%d*)", pos)
            return tonumber(num_str), pos + #num_str
        end

        -- string
        if char == '"' then
            local str_end = pos + 1
            while true do
                str_end = s:find('"', str_end, true)
                if not str_end then
                    error("Unterminated string")
                end
                -- Check if escaped
                local backslashes = 0
                local check_pos = str_end - 1
                while s:sub(check_pos, check_pos) == "\\" do
                    backslashes = backslashes + 1
                    check_pos = check_pos - 1
                end
                if backslashes % 2 == 0 then
                    break
                end
                str_end = str_end + 1
            end
            local str_val = s:sub(pos + 1, str_end - 1)
            -- Unescape
            str_val = str_val:gsub("\\(.)", {
                ['"'] = '"',
                ["\\"] = "\\",
                ["/"] = "/",
                ["b"] = "\b",
                ["f"] = "\f",
                ["n"] = "\n",
                ["r"] = "\r",
                ["t"] = "\t",
            })
            return str_val, str_end + 1
        end

        -- array
        if char == "[" then
            local arr = {}
            pos = pos + 1
            pos = s:match("^" .. ws .. "()", pos)
            if s:sub(pos, pos) == "]" then
                return arr, pos + 1
            end
            while true do
                local val, new_pos = decode_value(s, pos)
                table.insert(arr, val)
                pos = new_pos
                pos = s:match("^" .. ws .. "()", pos)
                local next_char = s:sub(pos, pos)
                if next_char == "]" then
                    return arr, pos + 1
                elseif next_char == "," then
                    pos = pos + 1
                else
                    error("Expected ',' or ']' in array")
                end
            end
        end

        -- object
        if char == "{" then
            local obj = {}
            pos = pos + 1
            pos = s:match("^" .. ws .. "()", pos)
            if s:sub(pos, pos) == "}" then
                return obj, pos + 1
            end
            while true do
                pos = s:match("^" .. ws .. "()", pos)
                local key, new_pos = decode_value(s, pos)
                pos = new_pos
                pos = s:match("^" .. ws .. "()", pos)
                if s:sub(pos, pos) ~= ":" then
                    error("Expected ':' after object key")
                end
                pos = pos + 1
                local val
                val, pos = decode_value(s, pos)
                obj[key] = val
                pos = s:match("^" .. ws .. "()", pos)
                local next_char = s:sub(pos, pos)
                if next_char == "}" then
                    return obj, pos + 1
                elseif next_char == "," then
                    pos = pos + 1
                else
                    error("Expected ',' or '}' in object")
                end
            end
        end

        error("Invalid JSON at position " .. pos)
    end

    local value, pos = decode_value(str, 1)
    return value
end

-- HTTP fetch function
local function fetch_url(url)
    if is_nvim then
        -- Use vim.fn.system in Neovim
        local result = vim.fn.system({"curl", "-s", url})
        if vim.v.shell_error ~= 0 then
            error("Failed to fetch URL: " .. url)
        end
        return result
    else
        -- Use curl command
        local handle = io.popen("curl -s " .. url)
        if not handle then
            error("Failed to fetch URL: " .. url)
        end
        local result = handle:read("*a")
        handle:close()
        return result
    end
end

-- Extract keywords from regex match pattern
local function extract_keywords_from_match(match_str)
    local keywords = {}
    local seen = {}

    -- Find all \b(word)\b patterns
    for capture in match_str:gmatch("\\b%(([^)]+)%)\\b") do
        -- Split on | if present
        if capture:find("|") then
            for word in capture:gmatch("[^|]+") do
                word = word:match("^%s*(.-)%s*$") -- trim
                if word ~= "" and not word:match("^%?") and word:match("^[%w_%-]+$") and not seen[word] then
                    table.insert(keywords, word)
                    seen[word] = true
                end
            end
        else
            local word = capture:match("^%s*(.-)%s*$") -- trim
            if word ~= "" and not word:match("^%?") and word:match("^[%w_%-]+$") and not seen[word] then
                table.insert(keywords, word)
                seen[word] = true
            end
        end
    end

    return keywords
end

-- Extract keywords from grammar
local function extract_keywords(grammar)
    local keywords = {
        core = {},
        modifiers = {},
        booleans = {},
        conditionals = {},
        ["repeat"] = {},
        time_units = {},
    }

    local repository = grammar.repository or {}

    -- Mapping of repository keys to categories
    local keyword_sections = {
        ["reactor-declaration"] = "core",
        ["preamble"] = "core",
        ["input-output"] = "modifiers",
        ["action"] = "modifiers",
        ["state"] = "modifiers",
        ["timer"] = "modifiers",
        ["reactor-member"] = "core",
        ["import-statement"] = "core",
        ["boolean"] = "booleans",
        ["time-unit"] = "time_units",
    }

    -- Extract from repository patterns
    for section_key, category in pairs(keyword_sections) do
        local section = repository[section_key]
        if section then
            -- Extract from direct match
            if section.match then
                local kws = extract_keywords_from_match(section.match)
                for _, kw in ipairs(kws) do
                    table.insert(keywords[category], kw)
                end
            end

            -- Extract from patterns
            if section.patterns then
                for _, pattern in ipairs(section.patterns) do
                    if pattern.match then
                        local kws = extract_keywords_from_match(pattern.match)
                        for _, kw in ipairs(kws) do
                            table.insert(keywords[category], kw)
                        end
                    end
                end
            end
        end
    end

    -- Add known keywords manually (fallback)
    local core_keywords = {
        "target", "reactor", "federated", "main", "realtime",
        "input", "output", "action", "state", "timer",
        "reaction", "method", "mode", "reset", "continue",
        "preamble", "extends", "new", "const",
        "import", "from", "as", "at",
        "after", "interleaved", "serializer",
        "physical", "logical", "startup", "shutdown",
        "initial"
    }
    for _, kw in ipairs(core_keywords) do
        table.insert(keywords.core, kw)
    end

    local modifier_keywords = {"public", "private", "widthof", "mutable"}
    for _, kw in ipairs(modifier_keywords) do
        table.insert(keywords.modifiers, kw)
    end

    local conditional_keywords = {"if", "else"}
    for _, kw in ipairs(conditional_keywords) do
        table.insert(keywords.conditionals, kw)
    end

    local repeat_keywords = {"for", "while"}
    for _, kw in ipairs(repeat_keywords) do
        table.insert(keywords["repeat"], kw)
    end

    local boolean_keywords = {"true", "false", "True", "False"}
    for _, kw in ipairs(boolean_keywords) do
        table.insert(keywords.booleans, kw)
    end

    -- Extract or set time units
    if repository["time-unit"] and repository["time-unit"].match then
        local time_kws = extract_keywords_from_match(repository["time-unit"].match)
        for _, kw in ipairs(time_kws) do
            table.insert(keywords.time_units, kw)
        end
    end

    if #keywords.time_units == 0 then
        local time_units = {
            "nsec", "nsecs", "usec", "usecs", "msec", "msecs",
            "sec", "secs", "second", "seconds",
            "min", "mins", "minute", "minutes",
            "hour", "hours", "day", "days", "week", "weeks"
        }
        for _, kw in ipairs(time_units) do
            table.insert(keywords.time_units, kw)
        end
    end

    -- Deduplicate and sort
    for category, kws in pairs(keywords) do
        local seen = {}
        local unique = {}
        for _, kw in ipairs(kws) do
            if not seen[kw] then
                table.insert(unique, kw)
                seen[kw] = true
            end
        end
        table.sort(unique)
        keywords[category] = unique
    end

    return keywords
end

-- Format keywords into vim syntax lines
local function format_keywords(keywords, group)
    if #keywords == 0 then
        return "syn keyword " .. group .. "\n"
    end

    local lines = {}
    local current_line = {}

    for _, kw in ipairs(keywords) do
        table.insert(current_line, kw)
        local line_str = table.concat(current_line, " ")
        if #line_str > 50 then
            table.insert(lines, "syn keyword " .. group .. " " .. line_str .. "\n")
            current_line = {}
        end
    end

    if #current_line > 0 then
        table.insert(lines, "syn keyword " .. group .. " " .. table.concat(current_line, " ") .. "\n")
    end

    return table.concat(lines)
end

-- Read file
local function read_file(path)
    local file = io.open(path, "r")
    if not file then
        error("Cannot open file: " .. path)
    end
    local content = file:read("*a")
    file:close()
    return content
end

-- Write file
local function write_file(path, content)
    local file = io.open(path, "w")
    if not file then
        error("Cannot write file: " .. path)
    end
    file:write(content)
    file:close()
end

-- Update syntax file
local function update_syntax_file(content, keywords)
    -- Update core keywords
    if #keywords.core > 0 then
        local core_lines = format_keywords(keywords.core, "lfKeyword")
        content = content:gsub(
            '" Keywords %- Core Language\n(syn keyword lfKeyword[^\n]*\n)+',
            '" Keywords - Core Language\n' .. core_lines
        )
    end

    -- Update modifiers
    if #keywords.modifiers > 0 then
        local mod_lines = format_keywords(keywords.modifiers, "lfModifier")
        content = content:gsub(
            '" Modifiers\n(syn keyword lfModifier[^\n]*\n)+',
            '" Modifiers\n' .. mod_lines
        )
    end

    -- Update booleans
    if #keywords.booleans > 0 then
        local bool_lines = format_keywords(keywords.booleans, "lfBoolean")
        content = content:gsub(
            '" Boolean\n(syn keyword lfBoolean[^\n]*\n)+',
            '" Boolean\n' .. bool_lines
        )
    end

    -- Update conditionals
    if #keywords.conditionals > 0 then
        local cond_lines = format_keywords(keywords.conditionals, "lfConditional")
        content = content:gsub(
            '" Control flow\n(syn keyword lfConditional[^\n]*\n)+',
            '" Control flow\n' .. cond_lines
        )
    end

    -- Update repeat
    if #keywords["repeat"] > 0 then
        local repeat_lines = format_keywords(keywords["repeat"], "lfRepeat")
        content = content:gsub(
            '(syn keyword lfConditional[^\n]*\n)(syn keyword lfRepeat[^\n]*\n)+',
            '%1' .. repeat_lines
        )
    end

    -- Update time units
    if #keywords.time_units > 0 then
        local time_lines = format_keywords(keywords.time_units, "lfTimeUnit")
        content = content:gsub(
            '" Time units\n(syn keyword lfTimeUnit[^\n]*\n)+',
            '" Time units\n' .. time_lines
        )
    end

    return content
end

-- Main function
local function main()
    local status, err = pcall(function()
        -- Fetch grammar
        print("Fetching grammar from " .. GRAMMAR_URL .. "...")
        local grammar_json = fetch_url(GRAMMAR_URL)
        print("✓ Grammar fetched successfully")

        -- Parse JSON
        local grammar = json.decode(grammar_json)

        -- Extract keywords
        local keywords = extract_keywords(grammar)

        -- Show keywords if requested
        if args.show_keywords then
            print("\n=== Extracted Keywords ===")
            for _, category in ipairs({"core", "modifiers", "booleans", "conditionals", "repeat", "time_units"}) do
                if #keywords[category] > 0 then
                    print("\n" .. category:upper() .. ":")
                    print("  " .. table.concat(keywords[category], ", "))
                end
            end
            return
        end

        -- Read current syntax file
        local current_content = read_file(syntax_file)
        print("✓ Current syntax file read")

        -- Update syntax file
        local new_content = update_syntax_file(current_content, keywords)

        -- Check if there were changes
        if new_content == current_content then
            print("⚠ No changes detected - syntax file is already up to date")
            return
        end

        if args.dry_run then
            print("\n=== DRY RUN - Changes Preview ===")
            print("Syntax file would be updated with the following keywords:")
            for _, category in ipairs({"core", "modifiers", "booleans", "conditionals", "repeat", "time_units"}) do
                if #keywords[category] > 0 then
                    print(string.format("  %s: %d keywords", category, #keywords[category]))
                end
            end
            print("\nTo apply changes, run without --dry-run flag")
        else
            write_file(syntax_file, new_content)
            print("✓ Syntax file updated: " .. syntax_file)
            print("\n=== Update Complete ===")
            print("Reload your .lf files in Neovim to see the changes:")
            print("  :e")
            print("  :syntax sync fromstart")
        end
    end)

    if not status then
        print("✗ Error: " .. tostring(err))
        os.exit(1)
    end
end

-- Run main
main()
