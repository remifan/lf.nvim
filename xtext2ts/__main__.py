"""CLI entry point for xtext2ts converter."""

import argparse
import sys
from pathlib import Path

from .tokenizer import tokenize
from .parser import parse
from .emitter import emit


def main():
    ap = argparse.ArgumentParser(
        description="Convert Xtext grammar to tree-sitter grammar.js"
    )
    ap.add_argument(
        "--xtext", required=True,
        help="Path to LinguaFranca.xtext file"
    )
    ap.add_argument(
        "--output", "-o",
        help="Output grammar.js path (default: stdout)"
    )
    ap.add_argument(
        "--dry-run", action="store_true",
        help="Print to stdout without writing"
    )
    args = ap.parse_args()

    source = Path(args.xtext).read_text()
    tokens = tokenize(source)
    grammar = parse(tokens)
    output = emit(grammar)

    if args.dry_run or not args.output:
        print(output)
    else:
        Path(args.output).write_text(output)
        print(f"Wrote {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
