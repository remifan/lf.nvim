#!/usr/bin/env python3
"""
Update Lingua Franca Neovim syntax from VSCode extension grammar.

This script fetches the latest TextMate grammar from the VSCode extension
repository and generates an updated syntax/lf.vim file.

Usage:
    python3 scripts/update_syntax.py
    python3 scripts/update_syntax.py --dry-run  # Preview changes without writing
"""

import argparse
import json
import re
import urllib.request
from pathlib import Path
from typing import Dict, List, Set


GRAMMAR_URL = "https://raw.githubusercontent.com/lf-lang/vscode-lingua-franca/main/syntaxes/lflang.tmLanguage.json"
SYNTAX_FILE = Path(__file__).parent.parent / "syntax" / "lf.vim"


def fetch_grammar() -> Dict:
    """Fetch the TextMate grammar JSON from GitHub."""
    print(f"Fetching grammar from {GRAMMAR_URL}...")
    with urllib.request.urlopen(GRAMMAR_URL) as response:
        return json.loads(response.read().decode())


def extract_keywords_from_match(match_str: str) -> List[str]:
    """Extract keywords from a regex match pattern like \\b(keyword1)\\b|\\b(keyword2)\\b"""
    # Find all \b(word)\b patterns
    keywords = re.findall(r'\\b\(([^)]+)\)\\b', match_str)

    # Process extracted patterns - split on | if present
    result = []
    for kw in keywords:
        if '|' in kw:
            result.extend(kw.split('|'))
        else:
            result.append(kw)

    # Clean up: strip whitespace, remove regex markers, filter invalid
    result = [k.strip() for k in result]
    result = [k for k in result if k and not k.startswith('?') and k.replace('_', '').replace('-', '').isalnum()]

    return result


def extract_keywords(grammar: Dict) -> Dict[str, Set[str]]:
    """Extract all keywords from the grammar."""
    keywords = {
        "core": set(),
        "modifiers": set(),
        "booleans": set(),
        "conditionals": set(),
        "repeat": set(),
        "time_units": set(),
    }

    repository = grammar.get("repository", {})

    # Mapping of repository keys to our categories
    keyword_sections = {
        "reactor-declaration": "core",  # reactor, federated, main, realtime, at, extends
        "preamble": "core",  # preamble, private, public
        "input-output": "modifiers",  # input, output, mutable
        "action": "modifiers",  # logical, physical, action
        "state": "modifiers",  # reset, state
        "timer": "modifiers",  # timer
        "reactor-member": "core",  # reaction, method, mode, etc.
        "import-statement": "core",  # import, from, as
        "boolean": "booleans",  # true, false
        "time-unit": "time_units",  # time units
    }

    for section_key, category in keyword_sections.items():
        if section_key not in repository:
            continue

        section = repository[section_key]

        # Extract from direct match
        if "match" in section:
            kws = extract_keywords_from_match(section["match"])
            keywords[category].update(kws)

        # Extract from patterns
        if "patterns" in section:
            for pattern in section["patterns"]:
                if "match" in pattern:
                    kws = extract_keywords_from_match(pattern["match"])
                    keywords[category].update(kws)

    # Manually add known keywords that might be in complex patterns
    keywords["core"].update([
        "target", "reactor", "federated", "main", "realtime",
        "input", "output", "action", "state", "timer",
        "reaction", "method", "mode", "reset", "continue",
        "preamble", "extends", "new", "const",
        "import", "from", "as", "at",
        "after", "interleaved", "serializer",
        "physical", "logical", "startup", "shutdown",
        "initial"
    ])

    keywords["modifiers"].update([
        "public", "private", "widthof", "mutable"
    ])

    keywords["conditionals"].update([
        "if", "else"
    ])

    keywords["repeat"].update([
        "for", "while"
    ])

    keywords["booleans"].update([
        "true", "false", "True", "False"
    ])

    # Extract time units from the pattern
    if "time-unit" in repository:
        match_pattern = repository["time-unit"].get("match", "")
        time_units = extract_keywords_from_match(match_pattern)
        if time_units:
            keywords["time_units"].update(time_units)
        else:
            # Fallback
            keywords["time_units"].update([
                "nsec", "nsecs", "usec", "usecs", "msec", "msecs",
                "sec", "secs", "second", "seconds",
                "min", "mins", "minute", "minutes",
                "hour", "hours", "day", "days", "week", "weeks"
            ])

    # Convert sets to sorted lists
    return {k: sorted(v) for k, v in keywords.items()}


def read_syntax_file() -> str:
    """Read the current syntax file."""
    return SYNTAX_FILE.read_text()


def format_keywords(keywords: List[str], group: str) -> str:
    """Format keywords into vim syntax lines."""
    if not keywords:
        return f"syn keyword {group}\n"

    lines = []
    current_line = []

    for kw in keywords:
        current_line.append(kw)
        # Keep lines reasonable length (around 50 chars)
        if len(' '.join(current_line)) > 50:
            lines.append(f"syn keyword {group} {' '.join(current_line)}\n")
            current_line = []

    # Add remaining keywords
    if current_line:
        lines.append(f"syn keyword {group} {' '.join(current_line)}\n")

    return ''.join(lines)


def update_syntax_file(content: str, keywords: Dict[str, List[str]]) -> str:
    """Update the syntax file with new keywords."""

    # Update core keywords
    if keywords["core"]:
        core_lines = format_keywords(keywords["core"], "lfKeyword")
        content = re.sub(
            r'" Keywords - Core Language\n(?:syn keyword lfKeyword[^\n]*\n)+',
            '" Keywords - Core Language\n' + core_lines,
            content
        )

    # Update modifiers
    if keywords["modifiers"]:
        mod_lines = format_keywords(keywords["modifiers"], "lfModifier")
        content = re.sub(
            r'" Modifiers\n(?:syn keyword lfModifier[^\n]*\n)+',
            '" Modifiers\n' + mod_lines,
            content
        )

    # Update booleans
    if keywords["booleans"]:
        bool_lines = format_keywords(keywords["booleans"], "lfBoolean")
        content = re.sub(
            r'" Boolean\n(?:syn keyword lfBoolean[^\n]*\n)+',
            '" Boolean\n' + bool_lines,
            content
        )

    # Update conditionals
    if keywords["conditionals"]:
        cond_lines = format_keywords(keywords["conditionals"], "lfConditional")
        content = re.sub(
            r'" Control flow\n(?:syn keyword lfConditional[^\n]*\n)+',
            '" Control flow\n' + cond_lines,
            content
        )

    # Update repeat
    if keywords["repeat"]:
        repeat_lines = format_keywords(keywords["repeat"], "lfRepeat")
        # Find the line after conditionals and update repeat
        content = re.sub(
            r'(syn keyword lfConditional[^\n]*\n)(?:syn keyword lfRepeat[^\n]*\n)+',
            r'\1' + format_keywords(keywords["repeat"], "lfRepeat"),
            content
        )

    # Update time units
    if keywords["time_units"]:
        time_lines = format_keywords(keywords["time_units"], "lfTimeUnit")
        content = re.sub(
            r'" Time units\n(?:syn keyword lfTimeUnit[^\n]*\n)+',
            '" Time units\n' + time_lines,
            content
        )

    return content


def main():
    parser = argparse.ArgumentParser(description="Update LF Neovim syntax from VSCode extension")
    parser.add_argument("--dry-run", action="store_true", help="Preview changes without writing")
    parser.add_argument("--show-keywords", action="store_true", help="Show extracted keywords")
    args = parser.parse_args()

    try:
        # Fetch grammar
        grammar = fetch_grammar()
        print("✓ Grammar fetched successfully")

        # Extract keywords
        keywords = extract_keywords(grammar)

        if args.show_keywords:
            print("\n=== Extracted Keywords ===")
            for category, kws in keywords.items():
                if kws:
                    print(f"\n{category.upper()}:")
                    print(f"  {', '.join(kws)}")
            return 0

        # Read current syntax file
        current_content = read_syntax_file()
        print("✓ Current syntax file read")

        # Update syntax file
        new_content = update_syntax_file(current_content, keywords)

        # Check if there were changes
        if new_content == current_content:
            print("⚠ No changes detected - syntax file is already up to date")
            return 0

        if args.dry_run:
            print("\n=== DRY RUN - Changes Preview ===")
            print("Syntax file would be updated with the following keywords:")
            for category, kws in keywords.items():
                if kws:
                    print(f"  {category}: {len(kws)} keywords")
            print("\nTo apply changes, run without --dry-run flag")
        else:
            SYNTAX_FILE.write_text(new_content)
            print(f"✓ Syntax file updated: {SYNTAX_FILE}")
            print("\n=== Update Complete ===")
            print("Reload your .lf files in Neovim to see the changes:")
            print("  :e")
            print("  :syntax sync fromstart")

    except Exception as e:
        print(f"✗ Error: {e}")
        import traceback
        traceback.print_exc()
        return 1

    return 0


if __name__ == "__main__":
    exit(main())
