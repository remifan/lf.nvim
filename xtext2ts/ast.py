"""AST node types for the Xtext grammar."""

from dataclasses import dataclass, field
from typing import Optional


@dataclass
class Node:
    """Base AST node."""
    pass


# ── Rule body nodes ──────────────────────────────────────────────

@dataclass
class Keyword(Node):
    value: str


@dataclass
class RuleCall(Node):
    name: str


@dataclass
class CrossRef(Node):
    type_name: str


@dataclass
class Action(Node):
    """Xtext type action like {Reactor} or {Code}."""
    type_name: str


@dataclass
class Assignment(Node):
    feature: str
    operator: str  # '=', '+=', '?='
    body: Node


@dataclass
class Group(Node):
    body: Node
    cardinality: Optional[str] = None  # None, '?', '*', '+'


@dataclass
class Sequence(Node):
    elements: list


@dataclass
class Alternatives(Node):
    options: list


@dataclass
class UnorderedGroup(Node):
    elements: list


@dataclass
class Predicate(Node):
    """Xtext => syntactic predicate."""
    body: Node


@dataclass
class Negation(Node):
    """Terminal rule negation !('x')."""
    body: Node


@dataclass
class CharRange(Node):
    """Terminal rule character range 'a'..'z'."""
    start: str
    end: str


@dataclass
class UntilToken(Node):
    """Terminal rule -> (match until)."""
    body: Node


@dataclass
class Wildcard(Node):
    """Terminal rule . (any character)."""
    pass


# ── Top-level rule nodes ────────────────────────────────────────

@dataclass
class ParserRule(Node):
    name: str
    body: Node
    returns_type: Optional[str] = None
    doc_comment: Optional[str] = None


@dataclass
class TerminalRule(Node):
    name: str
    body: Node
    returns_type: Optional[str] = None
    fragment: bool = False


@dataclass
class EnumLiteral(Node):
    name: str
    value: Optional[str] = None  # The keyword string, e.g., 'logical'


@dataclass
class EnumRule(Node):
    name: str
    literals: list = field(default_factory=list)


@dataclass
class GrammarFile(Node):
    name: str
    hidden: list = field(default_factory=list)
    rules: list = field(default_factory=list)
