"""
Override configuration for the Xtext-to-tree-sitter converter.

Contains rules that cannot be mechanically translated from Xtext,
including terminal regex patterns, precedence annotations, and
rules with tree-sitter-specific constructs.
"""

# Rules to skip entirely (handled by regex, external scanner, or not needed)
SKIP_RULES = {
    # Terminal rules - handled as regex patterns in REPLACE_RULES or by extras
    "WS", "ML_COMMENT", "SL_COMMENT", "ANY_OTHER",
    "LT_ANNOT", "CPP_RAW_STR", "FLOAT_EXP_SUFFIX",
    "TRUE", "FALSE",
    # Xtext-specific productions
    "Token",       # List of all terminals for Xtext lexer, not needed in tree-sitter
    "Body",        # Handled by external scanner (_code_body)
    # Abstract/intermediate rules folded into others
    "ReactorDecl",      # Just Reactor | ImportedReactor, inlined
    "TypedVariable",     # Port | Action, inlined
    "Variable",          # TypedVariable | Timer | Mode | Watchdog, inlined
    "Port",              # Input | Output, inlined
    "SignedInt",         # Folded into integer regex
    "SignedFloat",       # Folded into float regex
    "Forever",           # Inlined as keyword in time rule
    "Never",             # Inlined as keyword in time rule
    "FSName",            # Inlined into path regex
    # Rules folded into parent overrides
    "BuiltinTriggerRef",  # Inlined into trigger_ref as $.builtin_trigger
    "ParameterReference", # Just parameter=[Parameter], use $.identifier
    # IPV6 helper rules - too complex, handled via regex
    "IPV6Seg",
    # Model rule is generated specially as source_file
    "Model",
    # Terminal rules with explicit overrides below
    "ID", "INT", "NEGINT", "STRING", "CHAR_LIT",
}

# Complete rule replacements (tree-sitter rule name -> JS function body string)
# These override the entire auto-generated rule.
REPLACE_RULES = {
    # ── source_file (Model) ─────────────────────────────────────
    "source_file": """($) =>
      seq(
        $.target_declaration,
        repeat($.import_statement),
        repeat($.preamble),
        repeat1($.reactor)
      )""",

    # ── target_language (not in Xtext - target name is just ID) ──
    "target_language": """($) =>
      choice('C', 'CCpp', 'Cpp', 'Python', 'TypeScript', 'Rust')""",

    # ── time_unit (Xtext just uses ID, validated later) ──────────
    "time_unit": """($) =>
      choice(
        'nsec', 'nsecs', 'usec', 'usecs', 'msec', 'msecs',
        'sec', 'secs', 'second', 'seconds',
        'min', 'mins', 'minute', 'minutes',
        'hour', 'hours',
        'day', 'days',
        'week', 'weeks',
        'ns', 'us', 'ms', 's', 'm', 'h', 'd'
      )""",

    # ── Regex-based terminals ────────────────────────────────────
    "identifier": """($) => /[a-zA-Z_][a-zA-Z0-9_]*/""",
    "integer": """($) => /-?\\d+/""",
    "float": """($) => /-?\\d*\\.\\d+([eE][+-]?\\d+)?/""",
    "string": """($) =>
      choice(
        $.double_quoted_string,
        $.triple_double_quoted_string
      )""",
    "boolean": """($) => choice('true', 'false', 'True', 'False')""",
    "code_block": """($) => seq('{=', optional($._code_body), '=}')""",
    "path": """($) => /[a-zA-Z_][a-zA-Z0-9_.\\/-]*/""",
    "ipv4_addr": """($) => /\\d+\\.\\d+\\.\\d+\\.\\d+/""",
    "ipv6_addr": """($) => /[0-9a-fA-F:]+/""",

    # ── Rules needing tree-sitter-specific structure ──────────────

    # target_declaration: Xtext uses 'target' name=ID, but we want target_language
    "target_declaration": """($) =>
      seq(
        'target',
        field('name', $.target_language),
        optional(field('config', $.key_value_pairs)),
        optional(';')
      )""",

    # import_statement: uses import_path for <...> syntax
    "import_statement": """($) =>
      seq(
        'import',
        field('reactors', commaSep1($.imported_reactor)),
        'from',
        field('source', choice($.string, $.import_path)),
        optional(';')
      )""",

    # reactor: complex rule with unordered groups, needs manual layout
    "reactor": """($) =>
      seq(
        repeat($.attribute),
        optional(choice(seq(optional('federated'), 'main'), 'federated')),
        optional('realtime'),
        'reactor',
        optional(field('name', $.identifier)),
        optional(field('type_params', $.type_parameters)),
        optional(field('parameters', $.parameter_list)),
        optional(seq('at', field('host', $.host))),
        optional(seq('extends', field('extends', commaSep1($.identifier)))),
        field('body', $.reactor_body)
      )""",

    # reaction: complex with => predicate and multiple optional sections
    "reaction": """($) =>
      prec.right(seq(
        repeat($.attribute),
        choice('reaction', alias('mutation', $.mutation)),
        optional(field('name', $.identifier)),
        $.trigger_list,
        optional($.source_list),
        optional($.effect_list),
        optional(field('body', $.code_block)),
        optional($.stp),
        optional($.tardy),
        optional($.deadline),
        optional(';')
      ))""",

    # var_ref: complex with interleaved and container.variable
    "var_ref": """($) =>
      prec.left(seq(
        choice(
          seq(
            field('container', $.identifier),
            '.',
            field('variable', $.identifier)
          ),
          field('variable', $.identifier),
          seq(
            'interleaved',
            '(',
            choice(
              seq(
                field('container', $.identifier),
                '.',
                field('variable', $.identifier)
              ),
              field('variable', $.identifier)
            ),
            ')'
          )
        ),
        optional(seq('as', field('alias', $.identifier)))
      ))""",

    # connection_left: iterated pattern with special parens+
    "connection_left": """($) =>
      choice(
        prec(1, seq('(', commaSep1($.var_ref), ')', optional('+'))),
        commaSep1($.var_ref)
      )""",

    # expression: contains ParameterReference (just identifier) and CodeExpr
    "expression": """($) =>
      choice(
        $.time,
        $.literal,
        $.identifier,
        $.code_block,
        $.braced_list_expression,
        $.bracket_list_expression,
        $.parenthesis_list_expression
      )""",

    # time: Xtext uses interval=INT unit=TimeUnit | forever | never
    "time": """($) =>
      choice(
        seq(field('interval', $.integer), field('unit', $.time_unit)),
        'forever',
        'never'
      )""",

    # literal: different decomposition than Xtext
    "literal": """($) =>
      choice($.string, $.char_literal, $.number, $.boolean)""",

    # number: not in Xtext, combines float and integer
    "number": """($) => choice($.float, $.integer)""",

    # type: uses dotted_name instead of DottedName
    "type": """($) =>
      choice(
        'time',
        seq(
          $.dotted_name,
          optional($.type_arguments),
          repeat('*'),
          optional($.c_style_array_spec)
        ),
        $.code_block
      )""",

    # parameter: match hand-ported version
    "parameter": """($) =>
      seq(
        repeat($.attribute),
        field('name', $.identifier),
        optional(seq(':', field('type', $.type))),
        optional(field('init', $.initializer))
      )""",

    # state_var: fix double-optional from ?= operator
    "state_var": """($) =>
      prec.right(seq(
        repeat($.attribute),
        optional('reset'),
        'state',
        field('name', $.identifier),
        optional(seq(':', field('type', $.type))),
        optional(field('init', $.initializer)),
        optional(';')
      ))""",

    # input/output: match hand-ported structure
    "input": """($) =>
      prec.right(seq(
        repeat($.attribute),
        optional('mutable'),
        'input',
        optional(field('width', $.width_spec)),
        field('name', $.identifier),
        optional(seq(':', field('type', $.type))),
        optional(';')
      ))""",

    "output": """($) =>
      prec.right(seq(
        repeat($.attribute),
        'output',
        optional(field('width', $.width_spec)),
        field('name', $.identifier),
        optional(seq(':', field('type', $.type))),
        optional(';')
      ))""",

    # timer: extract timer_spec as sub-rule
    "timer": """($) =>
      prec.right(seq(
        repeat($.attribute),
        'timer',
        field('name', $.identifier),
        optional($.timer_spec),
        optional(';')
      ))""",

    # action: extract action_spec as sub-rule
    "action": """($) =>
      prec.right(seq(
        repeat($.attribute),
        optional(field('origin', $.action_origin)),
        'action',
        field('name', $.identifier),
        optional($.action_spec),
        optional(seq(':', field('type', $.type))),
        optional(';')
      ))""",

    # watchdog: match hand-ported
    "watchdog": """($) =>
      seq(
        repeat($.attribute),
        'watchdog',
        field('name', $.identifier),
        '(',
        field('timeout', $.expression),
        ')',
        optional(seq('->', commaSep1($.var_ref_or_mode_transition))),
        field('handler', $.code_block)
      )""",

    # instantiation: match hand-ported
    "instantiation": """($) =>
      prec.right(seq(
        repeat($.attribute),
        field('name', $.identifier),
        '=',
        'new',
        optional(field('width', $.width_spec)),
        field('class', $.identifier),
        optional(field('type_args', $.type_arguments)),
        '(',
        commaSep($.assignment),
        ')',
        optional(seq('at', $.host)),
        optional(';')
      ))""",

    # connection: match hand-ported
    "connection": """($) =>
      prec.right(seq(
        repeat($.attribute),
        field('left', $.connection_left),
        field('arrow', choice('->', '~>')),
        field('right', commaSep1($.var_ref)),
        optional(seq('after', field('delay', $.expression))),
        optional($.serializer),
        optional(';')
      ))""",

    # initializer: '=' is required (not optional), other forms handle no-= case
    "initializer": """($) =>
      choice(
        seq('=', $.expression),
        $.braced_list_expression,
        $.parenthesis_list_expression
      )""",

    # width_spec: match hand-ported version
    "width_spec": """($) =>
      seq(
        '[',
        choice(
          ']',
          seq($.width_body, ']')
        )
      )""",

    # c_style_array_spec: match hand-ported version
    "c_style_array_spec": """($) => seq('[', choice(']', seq($.integer, ']')))""",

    # tardy: Xtext has present?='tardy' which is optional, but TS requires non-empty
    "tardy": """($) => seq('tardy', optional($.code_block))""",

    # trigger_ref: flattens BuiltinTriggerRef into direct choice
    "trigger_ref": """($) => choice($.builtin_trigger, $.var_ref)""",

    # source_list: needs prec.right to avoid ambiguity with effect_list
    "source_list": """($) => prec.right(repeat1($.var_ref))""",

    # braced_list_expression: negative prec to avoid conflict with reactor_body
    "braced_list_expression": """($) => prec(-1, seq('{', commaSep($.expression), '}'))""",

    # IPV6 rules - too complex for auto-generation, use regex
    "ipv6_seg": """($) => /[0-9a-fA-F]+/""",
    "ipv6_addr": """($) => /[0-9a-fA-F:]+/""",
}

# Additional rules not in the Xtext grammar (added to output)
EXTRA_RULES = {
    "double_quoted_string": '''($) => /"[^"\\\\]*(?:\\\\.[^"\\\\]*)*"/''',
    "triple_double_quoted_string": '''($) => /"""[\\s\\S]*?"""/''',
    "char_literal": '''($) => /'[^'\\\\](?:\\\\.[^'\\\\])*'/''',
    "import_path": """($) => seq('<', $.path, '>')""",
    "target_language": None,  # Already in REPLACE_RULES
    "timer_spec": """($) =>
      seq(
        '(',
        field('offset', $.expression),
        optional(seq(',', field('period', $.expression))),
        ')'
      )""",
    "action_spec": """($) =>
      seq(
        '(',
        field('min_delay', $.expression),
        optional(
          seq(
            ',',
            field('min_spacing', $.expression),
            optional(seq(',', field('policy', $.string)))
          )
        ),
        ')'
      )""",
    "trigger_list": """($) => seq('(', commaSep($.trigger_ref), ')')""",
    "source_list": None,  # Already in REPLACE_RULES
    "effect_list": """($) => seq('->', commaSep1($.var_ref_or_mode_transition))""",
    "reactor_body": """($) =>
      seq('{', repeat($.reactor_member), '}')""",
    "reactor_member": """($) =>
      choice(
        $.preamble,
        $.state_var,
        $.method,
        $.input,
        $.output,
        $.timer,
        $.action,
        $.watchdog,
        $.instantiation,
        $.connection,
        $.reaction,
        $.mode
      )""",
    "mode_member": """($) =>
      choice(
        $.state_var,
        $.timer,
        $.action,
        $.watchdog,
        $.instantiation,
        $.connection,
        $.reaction
      )""",
    "number": None,  # Already in REPLACE_RULES
    "type_arguments": """($) => seq('<', commaSep1($.type), '>')""",
    "type_parameters": """($) => seq('<', commaSep1($.type_parameter), '>')""",
    "parameter_list": """($) => seq('(', commaSep($.parameter), ')')""",
    "width_body": """($) => seq($.width_term, repeat(seq('+', $.width_term)))""",
    "connection_left": None,  # Already in REPLACE_RULES
    "line_comment": """($) => token(choice(seq('//', /.*/), seq('#', /.*/))),""",
    "block_comment": """($) =>
      token(seq('/*', /[^*]*\\*+([^/*][^*]*\\*+)*/, '/'))""",
}

# Grammar-level declarations
GRAMMAR_META = {
    "externals": """($) => [$._code_body]""",
    "extras": """($) => [/\\s/, $.line_comment, $.block_comment]""",
    "word": """($) => $.identifier""",
    "inline": """($) => [$.reactor_member]""",
    "conflicts": """($) => [\n    [$.ipv4_host, $.named_host, $.hostname],\n  ]""",
}

# Precedence wrappers (tree-sitter rule name -> wrapper)
# Value is either a string like "prec.right" or a tuple ("prec", level)
PRECEDENCE = {
    "state_var": "prec.right",
    "input": "prec.right",
    "output": "prec.right",
    "timer": "prec.right",
    "action": "prec.right",
    "reaction": "prec.right",
    "instantiation": "prec.right",
    "connection": "prec.right",
    "attribute": "prec.right",
    "var_ref": "prec.left",
    "dotted_name": "prec.left",
    "braced_list_expression": ("prec", -1),
}

# Field name renames (Xtext feature name -> tree-sitter field name or None to drop)
FIELD_RENAMES = {
    "importURI": "source",
    "reactorClasses": "reactors",
    "attrName": "name",
    "attrParms": None,
    "typeParms": "type_params",
    "superClasses": "extends",
    "widthSpec": "width",
    "minDelay": "min_delay",
    "minSpacing": "min_spacing",
    "leftPorts": "left",
    "rightPorts": "right",
    "stateVars": None,     # Drop field wrapper on reactor members
    "methods": None,
    "inputs": None,
    "outputs": None,
    "timers": None,
    "actions": None,
    "watchdogs": None,
    "instantiations": None,
    "connections": None,
    "reactions": None,
    "modes": None,
    "preambles": None,
}

# Rules to emit in the output (order matters)
# Rules not listed here are emitted in Xtext order after these
RULE_ORDER = [
    "source_file",
    "target_declaration",
    "target_language",
    "import_statement",
    "imported_reactor",
    "import_path",
    "path",
    "preamble",
    "visibility",
    "reactor",
    "type_parameters",
    "type_parameter",
    "type_expression",
    "parameter_list",
    "parameter",
    "reactor_body",
    "reactor_member",
    "state_var",
    "method",
    "method_argument",
    "input",
    "output",
    "timer",
    "timer_spec",
    "action",
    "action_origin",
    "action_spec",
    "watchdog",
    "reaction",
    "trigger_list",
    "source_list",
    "effect_list",
    "trigger_ref",
    "builtin_trigger",
    "var_ref",
    "var_ref_or_mode_transition",
    "mode_transition",
    "stp",
    "tardy",
    "deadline",
    "mode",
    "mode_member",
    "instantiation",
    "type_arguments",
    "assignment",
    "connection",
    "connection_left",
    "serializer",
    "attribute",
    "attribute_parameter",
    "key_value_pairs",
    "key_value_pair",
    "kebab",
    "element",
    "array",
    "type",
    "dotted_name",
    "c_style_array_spec",
    "width_spec",
    "width_body",
    "width_term",
    "initializer",
    "expression",
    "braced_list_expression",
    "bracket_list_expression",
    "parenthesis_list_expression",
    "time",
    "time_unit",
    "host",
    "ipv4_host",
    "ipv6_host",
    "named_host",
    "hostname",
    "ipv4_addr",
    "ipv6_addr",
    "literal",
    "string",
    "double_quoted_string",
    "triple_double_quoted_string",
    "char_literal",
    "number",
    "integer",
    "float",
    "boolean",
    "code_block",
    "line_comment",
    "block_comment",
    "identifier",
]
