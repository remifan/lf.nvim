"""
Code generator: translates Xtext AST nodes into tree-sitter grammar.js expressions.
"""

from . import ast
from .naming import xtext_to_ts, pascal_to_snake
from .overrides import FIELD_RENAMES, PRECEDENCE


def gen_rule_body(node: ast.Node) -> str:
    """Generate a tree-sitter expression string from an Xtext AST node."""
    if node is None:
        return "''"

    if isinstance(node, ast.Keyword):
        return _gen_keyword(node)
    if isinstance(node, ast.RuleCall):
        return _gen_rule_call(node)
    if isinstance(node, ast.CrossRef):
        return "$.identifier"
    if isinstance(node, ast.Action):
        return ""  # Xtext type actions are dropped
    if isinstance(node, ast.Assignment):
        return _gen_assignment(node)
    if isinstance(node, ast.Group):
        return _gen_group(node)
    if isinstance(node, ast.Sequence):
        return _gen_sequence(node)
    if isinstance(node, ast.Alternatives):
        return _gen_alternatives(node)
    if isinstance(node, ast.UnorderedGroup):
        return _gen_unordered_group(node)
    if isinstance(node, ast.Predicate):
        return gen_rule_body(node.body)  # Drop => predicate

    return f"/* unhandled: {type(node).__name__} */"


def _gen_keyword(node: ast.Keyword) -> str:
    escaped = node.value.replace("\\", "\\\\").replace("'", "\\'")
    return f"'{escaped}'"


def _gen_rule_call(node: ast.RuleCall) -> str:
    name = xtext_to_ts(node.name)
    if name.startswith("_"):
        return f"$._code_body"  # External
    return f"$.{name}"


def _gen_assignment(node: ast.Assignment) -> str:
    body_str = gen_rule_body(node.body)
    if not body_str:
        return ""

    if node.operator == "?=":
        # Boolean flag: flag?='keyword' -> optional('keyword')
        return f"optional({body_str})"

    # Determine field name
    feature = node.feature
    if feature in FIELD_RENAMES:
        renamed = FIELD_RENAMES[feature]
        if renamed is None:
            return body_str  # Drop field wrapper
        feature = renamed
    else:
        feature = pascal_to_snake(feature)

    return f"field('{feature}', {body_str})"


def _gen_group(node: ast.Group) -> str:
    body_str = gen_rule_body(node.body)
    if not body_str:
        return ""

    if node.cardinality == "?":
        return f"optional({body_str})"
    elif node.cardinality == "*":
        return f"repeat({body_str})"
    elif node.cardinality == "+":
        return f"repeat1({body_str})"
    return body_str


def _gen_sequence(node: ast.Sequence) -> str:
    parts = []
    for el in node.elements:
        s = gen_rule_body(el)
        if s:
            parts.append(s)

    if not parts:
        return ""

    # Check for commaSep pattern: X (',' X)*
    parts = _detect_comma_sep(parts, node.elements)

    if len(parts) == 1:
        return parts[0]
    return f"seq(\n        {',\n        '.join(parts)}\n      )"


def _detect_comma_sep(parts: list[str], elements: list) -> list[str]:
    """
    Detect commaSep1 pattern: A (',' A)* and replace with commaSep1(A).
    Also detect (A (',' A)*)? -> commaSep(A).
    """
    if len(parts) < 2:
        return parts

    # Look for the pattern: ITEM, repeat(seq(',', ITEM))
    new_parts = []
    i = 0
    while i < len(parts):
        if i + 1 < len(parts) and i < len(elements):
            # Check if next element is repeat(seq(',', SAME))
            item_str = parts[i]
            repeat_str = parts[i + 1]

            # Extract the base name from field('name', $.X) or $.X
            base = _extract_rule_ref(item_str)
            if base and (
                repeat_str == f"repeat(seq(',', {item_str}))" or
                repeat_str == f"repeat(seq(',', {base}))"
            ):
                new_parts.append(f"commaSep1({item_str})")
                i += 2
                continue

        new_parts.append(parts[i])
        i += 1
    return new_parts


def _extract_rule_ref(s: str) -> str | None:
    """Extract $.rule_name from field('name', $.rule_name) or return $.rule_name directly."""
    if s.startswith("$."):
        return s
    if s.startswith("field("):
        # field('name', $.something)
        idx = s.find(", $.")
        if idx >= 0:
            return s[idx+2:s.rindex(")")]
    return None


def _gen_alternatives(node: ast.Alternatives) -> str:
    options = []
    for opt in node.options:
        s = gen_rule_body(opt)
        if s:
            options.append(s)

    if not options:
        return ""
    if len(options) == 1:
        return options[0]
    return f"choice(\n        {',\n        '.join(options)}\n      )"


def _gen_unordered_group(node: ast.UnorderedGroup) -> str:
    """
    Unordered groups (A & B) mean elements can appear in any order.
    For small groups, generate choice() of all permutations.
    The LF grammar only has one: ((federated|main)? & realtime?)
    """
    # For simplicity, just emit them as a sequence of optionals
    # The override for 'reactor' handles the actual complex case
    parts = []
    for el in node.elements:
        s = gen_rule_body(el)
        if s:
            parts.append(f"optional({s})")

    if len(parts) == 1:
        return parts[0]
    return f"seq(\n        {',\n        '.join(parts)}\n      )"


def gen_full_rule(name: str, node: ast.Node) -> str:
    """Generate a complete tree-sitter rule with optional precedence wrapping."""
    body = gen_rule_body(node)
    ts_name = xtext_to_ts(name)

    # Apply precedence if configured
    if ts_name in PRECEDENCE:
        prec_info = PRECEDENCE[ts_name]
        if isinstance(prec_info, tuple):
            func, level = prec_info
            body = f"{func}({level}, {body})"
        else:
            body = f"{prec_info}({body})"

    return body
