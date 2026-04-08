"""Recursive descent parser for Xtext grammar files."""

from . import ast
from .tokenizer import Token


class ParseError(Exception):
    def __init__(self, msg, token=None):
        if token:
            super().__init__(f"Line {token.line}:{token.col}: {msg} (got {token})")
        else:
            super().__init__(msg)


class Parser:
    def __init__(self, tokens: list[Token]):
        self.tokens = tokens
        self.pos = 0
        self._last_doc = None

    def peek(self) -> Token | None:
        if self.pos < len(self.tokens):
            return self.tokens[self.pos]
        return None

    def advance(self) -> Token:
        t = self.tokens[self.pos]
        self.pos += 1
        return t

    def expect(self, type_: str, value: str | None = None) -> Token:
        t = self.peek()
        if t is None:
            raise ParseError(f"Expected {type_} {value!r}, got EOF")
        if t.type != type_ or (value is not None and t.value != value):
            raise ParseError(f"Expected {type_} {value!r}", t)
        return self.advance()

    def match(self, type_: str, value: str | None = None) -> Token | None:
        t = self.peek()
        if t and t.type == type_ and (value is None or t.value == value):
            return self.advance()
        return None

    def at(self, type_: str, value: str | None = None) -> bool:
        t = self.peek()
        return t is not None and t.type == type_ and (value is None or t.value == value)

    # ── Grammar file ───────────────────────────────────────────

    def parse(self) -> ast.GrammarFile:
        # Consume doc comments before grammar declaration
        self._consume_doc_comments()

        self.expect("ID", "grammar")
        name = self._qualified_name()

        hidden = []
        if self.match("ID", "hidden"):
            self.expect("SYM", "(")
            hidden.append(self.expect("ID").value)
            while self.match("SYM", ","):
                hidden.append(self.expect("ID").value)
            self.expect("SYM", ")")

        # Skip import and generate declarations
        while self.at("ID", "import") or self.at("ID", "generate"):
            self._skip_declaration()

        rules = []
        while self.peek() is not None:
            self._consume_doc_comments()
            t = self.peek()
            if t is None:
                break
            if t.type == "ID" and t.value == "terminal":
                rules.append(self._terminal_rule())
            elif t.type == "ID" and t.value == "enum":
                rules.append(self._enum_rule())
            elif t.type == "ID":
                rules.append(self._parser_rule())
            else:
                self.advance()  # skip unexpected tokens

        return ast.GrammarFile(name=name, hidden=hidden, rules=rules)

    def _qualified_name(self) -> str:
        name = self.expect("ID").value
        while self.at("SYM", ".") or self.at("SYM", "::"):
            sep = self.advance().value
            name += sep + self.expect("ID").value
        return name

    def _skip_declaration(self):
        """Skip import/generate declarations until semicolon."""
        while self.peek() is not None:
            if self.match("SYM", ";"):
                return
            # Also stop if we hit something that looks like a rule start
            t = self.peek()
            if t and t.type == "ID" and t.value in ("terminal", "enum"):
                return
            # Stop at a colon preceded by an ID (rule definition)
            if t and t.type == "SYM" and t.value == ":":
                # Check if the previous token was an ID (a rule name)
                # Actually, let's just look for semicolons
                pass
            self.advance()

    def _consume_doc_comments(self):
        while self.at("DOC_COMMENT"):
            self._last_doc = self.advance().value

    # ── Parser rules ───────────────────────────────────────────

    def _parser_rule(self) -> ast.ParserRule:
        doc = self._last_doc
        self._last_doc = None

        name = self.expect("ID").value

        returns_type = None
        if self.match("ID", "returns"):
            returns_type = self.expect("ID").value

        self.expect("SYM", ":")
        body = self._alternatives()
        self.expect("SYM", ";")

        return ast.ParserRule(name=name, body=body, returns_type=returns_type,
                              doc_comment=doc)

    # ── Terminal rules ─────────────────────────────────────────

    def _terminal_rule(self) -> ast.TerminalRule:
        self.expect("ID", "terminal")
        fragment = bool(self.match("ID", "fragment"))
        name = self.expect("ID").value

        returns_type = None
        if self.match("ID", "returns"):
            returns_type = self._qualified_name()

        self.expect("SYM", ":")
        body = self._terminal_body()
        self.expect("SYM", ";")

        return ast.TerminalRule(name=name, body=body, returns_type=returns_type,
                                fragment=fragment)

    def _terminal_body(self) -> ast.Node:
        """Parse terminal rule body (alternatives of sequences)."""
        return self._terminal_alternatives()

    def _terminal_alternatives(self) -> ast.Node:
        first = self._terminal_sequence()
        options = [first]
        while self.match("SYM", "|"):
            options.append(self._terminal_sequence())
        if len(options) == 1:
            return options[0]
        return ast.Alternatives(options=options)

    def _terminal_sequence(self) -> ast.Node:
        elements = []
        while self.peek() is not None:
            t = self.peek()
            if t.type == "SYM" and t.value in (";", "|", ")"):
                break
            el = self._terminal_element()
            if el is None:
                break
            elements.append(el)
        if len(elements) == 1:
            return elements[0]
        return ast.Sequence(elements=elements)

    def _terminal_element(self) -> ast.Node | None:
        node = self._terminal_atom()
        if node is None:
            return None

        # Cardinality
        t = self.peek()
        if t and t.type == "SYM" and t.value in ("?", "*", "+"):
            self.advance()
            return ast.Group(body=node, cardinality=t.value)
        return node

    def _terminal_atom(self) -> ast.Node | None:
        t = self.peek()
        if t is None:
            return None

        # String literal (keyword/char) - single or double quoted
        if t.type in ("STRING", "DSTRING"):
            self.advance()
            # Check for character range 'a'..'z'
            if self.at("SYM", ".."):
                self.advance()
                end_tok = self.peek()
                if end_tok and end_tok.type in ("STRING", "DSTRING"):
                    self.advance()
                    return ast.CharRange(start=t.value, end=end_tok.value)
            return ast.Keyword(value=t.value)

        # Negation
        if t.type == "SYM" and t.value == "!":
            self.advance()
            body = self._terminal_atom()
            return ast.Negation(body=body)

        # Wildcard
        if t.type == "SYM" and t.value == ".":
            self.advance()
            return ast.Wildcard()

        # Group
        if t.type == "SYM" and t.value == "(":
            self.advance()
            body = self._terminal_alternatives()
            self.expect("SYM", ")")
            card = None
            tc = self.peek()
            if tc and tc.type == "SYM" and tc.value in ("?", "*", "+"):
                card = self.advance().value
            return ast.Group(body=body, cardinality=card)

        # -> (until token)
        if t.type == "SYM" and t.value == "->":
            self.advance()
            body = self._terminal_atom()
            return ast.UntilToken(body=body)

        # Rule reference (ID)
        if t.type == "ID":
            self.advance()
            return ast.RuleCall(name=t.value)

        return None

    # ── Enum rules ─────────────────────────────────────────────

    def _enum_rule(self) -> ast.EnumRule:
        self.expect("ID", "enum")
        name = self.expect("ID").value
        self.expect("SYM", ":")
        literals = [self._enum_literal()]
        while self.match("SYM", "|"):
            literals.append(self._enum_literal())
        self.expect("SYM", ";")
        return ast.EnumRule(name=name, literals=literals)

    def _enum_literal(self) -> ast.EnumLiteral:
        name = self.expect("ID").value
        value = None
        if self.match("SYM", "="):
            value = self.expect("STRING").value
        return ast.EnumLiteral(name=name, value=value)

    # ── Parser rule body ───────────────────────────────────────

    def _alternatives(self) -> ast.Node:
        first = self._unordered_group()
        options = [first]
        while self.match("SYM", "|"):
            options.append(self._unordered_group())
        if len(options) == 1:
            return options[0]
        return ast.Alternatives(options=options)

    def _unordered_group(self) -> ast.Node:
        first = self._sequence()
        elements = [first]
        while self.match("SYM", "&"):
            elements.append(self._sequence())
        if len(elements) == 1:
            return elements[0]
        return ast.UnorderedGroup(elements=elements)

    def _sequence(self) -> ast.Node:
        elements = []
        while True:
            t = self.peek()
            if t is None:
                break
            if t.type == "SYM" and t.value in (";", "|", ")", "&"):
                break
            el = self._element()
            if el is None:
                break
            elements.append(el)
        if len(elements) == 0:
            return ast.Sequence(elements=[])
        if len(elements) == 1:
            return elements[0]
        return ast.Sequence(elements=elements)

    def _element(self) -> ast.Node | None:
        # Check for => predicate
        if self.match("SYM", "=>"):
            body = self._element()
            return ast.Predicate(body=body)

        # Check for assignment: name= / name+= / name?=
        assign_feature = None
        assign_op = None
        if self.peek() and self.peek().type == "ID":
            # Look ahead for =, +=, ?=
            save = self.pos
            ident = self.advance()
            t2 = self.peek()
            if t2 and t2.type == "SYM" and t2.value in ("=", "+=", "?="):
                assign_feature = ident.value
                assign_op = self.advance().value
            else:
                # Not an assignment, restore
                self.pos = save

        node = self._atom()
        if node is None:
            if assign_feature:
                # Shouldn't happen, but recover
                return None
            return None

        # Cardinality
        t = self.peek()
        if t and t.type == "SYM" and t.value in ("?", "*", "+"):
            card = self.advance().value
            node = ast.Group(body=node, cardinality=card)

        if assign_feature:
            node = ast.Assignment(feature=assign_feature, operator=assign_op, body=node)

        return node

    def _atom(self) -> ast.Node | None:
        t = self.peek()
        if t is None:
            return None

        # Keyword string (single or double quoted)
        if t.type in ("STRING", "DSTRING"):
            self.advance()
            return ast.Keyword(value=t.value)

        # Cross-reference [Type]
        if t.type == "SYM" and t.value == "[":
            self.advance()
            type_name = self.expect("ID").value
            self.expect("SYM", "]")
            return ast.CrossRef(type_name=type_name)

        # Type action {Type}
        if t.type == "SYM" and t.value == "{":
            self.advance()
            type_name = self.expect("ID").value
            self.expect("SYM", "}")
            return ast.Action(type_name=type_name)

        # Parenthesized group
        if t.type == "SYM" and t.value == "(":
            self.advance()
            body = self._alternatives()
            self.expect("SYM", ")")
            card = None
            tc = self.peek()
            if tc and tc.type == "SYM" and tc.value in ("?", "*", "+"):
                card = self.advance().value
            return ast.Group(body=body, cardinality=card)

        # Rule call (identifier)
        if t.type == "ID":
            self.advance()
            return ast.RuleCall(name=t.value)

        return None


def parse(tokens: list[Token]) -> ast.GrammarFile:
    """Parse a token stream into an Xtext grammar AST."""
    p = Parser(tokens)
    return p.parse()
