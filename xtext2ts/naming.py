"""Name mapping between Xtext PascalCase and tree-sitter snake_case."""

import re

# Explicit name overrides (Xtext name -> tree-sitter name)
NAME_MAP = {
    "Model": "source_file",
    "TargetDecl": "target_declaration",
    "Import": "import_statement",
    "Code": "code_block",
    "Body": "_code_body",
    "ID": "identifier",
    "INT": "integer",
    "NEGINT": "integer",  # folded into integer with /-?\d+/
    "STRING": "string",
    "CHAR_LIT": "char_literal",
    "TRUE": "boolean",
    "FALSE": "boolean",
    "TypeParm": "type_parameter",
    "TypeExpr": "type_expression",
    "AttrParm": "attribute_parameter",
    "HostName": "hostname",
    "NamedHost": "named_host",
    "IPV4Host": "ipv4_host",
    "IPV6Host": "ipv6_host",
    "IPV4Addr": "ipv4_addr",
    "IPV6Addr": "ipv6_addr",
    "IPV6Seg": "ipv6_seg",
}


def pascal_to_snake(name: str) -> str:
    """Convert PascalCase to snake_case."""
    # Insert underscore before uppercase letters preceded by lowercase
    s = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", name)
    # Insert underscore between consecutive uppercase and following lowercase
    s = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1_\2", s)
    return s.lower()


def xtext_to_ts(name: str) -> str:
    """Convert an Xtext rule name to a tree-sitter rule name."""
    if name in NAME_MAP:
        return NAME_MAP[name]
    return pascal_to_snake(name)
