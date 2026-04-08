"""Tokenizer for Xtext grammar files."""

from dataclasses import dataclass
from typing import Optional


@dataclass
class Token:
    type: str
    value: str
    line: int
    col: int

    def __repr__(self):
        return f"Token({self.type}, {self.value!r})"


# Symbols sorted longest-first for correct matching
SYMBOLS = [
    "+=", "?=", "=>", "->", "..", "::",
    "(", ")", "{", "}", "[", "]", "<", ">",
    ":", ";", "|", "*", "+", "?", "=", "&", ",", ".",
]


def tokenize(source: str) -> list[Token]:
    """Tokenize an Xtext grammar file."""
    tokens = []
    i = 0
    line = 1
    col = 1

    while i < len(source):
        c = source[i]

        # Whitespace
        if c in " \t\r\n":
            if c == "\n":
                line += 1
                col = 1
            else:
                col += 1
            i += 1
            continue

        # Doc comment /** ... */
        if source[i:i+3] == "/**" and (i + 3 < len(source) and source[i+3] != "/"):
            end = source.find("*/", i + 3)
            if end == -1:
                end = len(source)
            else:
                end += 2
            comment = source[i:end]
            tokens.append(Token("DOC_COMMENT", comment, line, col))
            newlines = comment.count("\n")
            line += newlines
            if newlines:
                col = len(comment) - comment.rfind("\n")
            else:
                col += len(comment)
            i = end
            continue

        # Block comment /* ... */
        if source[i:i+2] == "/*":
            end = source.find("*/", i + 2)
            if end == -1:
                end = len(source)
            else:
                end += 2
            comment = source[i:end]
            newlines = comment.count("\n")
            line += newlines
            if newlines:
                col = len(comment) - comment.rfind("\n")
            else:
                col += len(comment)
            i = end
            continue

        # Line comment //
        if source[i:i+2] == "//":
            end = source.find("\n", i)
            if end == -1:
                end = len(source)
            i = end
            continue

        # Single-quoted string (keyword)
        if c == "'":
            j = i + 1
            while j < len(source) and source[j] != "'":
                if source[j] == "\\":
                    j += 1
                j += 1
            if j < len(source):
                j += 1  # consume closing quote
            value = source[i+1:j-1]
            tokens.append(Token("STRING", value, line, col))
            col += j - i
            i = j
            continue

        # Double-quoted string (URI)
        if c == '"':
            j = i + 1
            while j < len(source) and source[j] != '"':
                if source[j] == "\\":
                    j += 1
                j += 1
            if j < len(source):
                j += 1
            value = source[i+1:j-1]
            tokens.append(Token("DSTRING", value, line, col))
            col += j - i
            i = j
            continue

        # Symbols (check longest first)
        matched = False
        for sym in SYMBOLS:
            if source[i:i+len(sym)] == sym:
                tokens.append(Token("SYM", sym, line, col))
                col += len(sym)
                i += len(sym)
                matched = True
                break
        if matched:
            continue

        # Identifier / keyword
        if c.isalpha() or c == "_":
            j = i + 1
            while j < len(source) and (source[j].isalnum() or source[j] == "_"):
                j += 1
            value = source[i:j]
            tokens.append(Token("ID", value, line, col))
            col += j - i
            i = j
            continue

        # Unknown character - skip
        col += 1
        i += 1

    return tokens
