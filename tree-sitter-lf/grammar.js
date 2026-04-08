/**
 * Tree-sitter grammar for Lingua Franca
 * Based on the official Xtext grammar from lf-lang/lingua-franca
 *
 * @see https://github.com/lf-lang/lingua-franca/blob/master/core/src/main/java/org/lflang/LinguaFranca.xtext
 */

/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

// Helper functions
const commaSep = (rule) => optional(commaSep1(rule));
const commaSep1 = (rule) => seq(rule, repeat(seq(',', rule)));

module.exports = grammar({
  name: 'lf',

  externals: ($) => [$._code_body],

  extras: ($) => [/\s/, $.line_comment, $.block_comment],

  word: ($) => $.identifier,

  inline: ($) => [$.reactor_member],

  conflicts: ($) => [
    [$.ipv4_host, $.named_host, $.hostname],
  ],

  rules: {
    // Top-level AST node
    source_file: ($) =>
      seq(
        $.target_declaration,
        repeat($.import_statement),
        repeat($.preamble),
        repeat1($.reactor)
      ),

    // ========== Target Declaration ==========
    target_declaration: ($) =>
      seq(
        'target',
        field('name', $.target_language),
        optional(field('config', $.key_value_pairs)),
        optional(';')
      ),

    target_language: ($) =>
      choice('C', 'CCpp', 'Cpp', 'Python', 'TypeScript', 'Rust'),

    // ========== Import Statement ==========
    import_statement: ($) =>
      seq(
        'import',
        field('reactors', commaSep1($.imported_reactor)),
        'from',
        field('source', choice($.string, $.import_path)),
        optional(';')
      ),

    imported_reactor: ($) =>
      seq(
        field('class', $.identifier),
        optional(seq('as', field('alias', $.identifier)))
      ),

    import_path: ($) => seq('<', $.path, '>'),

    path: ($) => /[a-zA-Z_][a-zA-Z0-9_.\/-]*/,

    // ========== Preamble ==========
    preamble: ($) =>
      seq(
        optional(field('visibility', $.visibility)),
        'preamble',
        field('code', $.code_block)
      ),

    visibility: ($) => choice('private', 'public'),

    // ========== Reactor Declaration ==========
    reactor: ($) =>
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
      ),

    type_parameters: ($) => seq('<', commaSep1($.type_parameter), '>'),

    type_parameter: ($) => choice($.type_expression, $.code_block),

    type_expression: ($) => repeat1($.identifier),

    parameter_list: ($) => seq('(', commaSep($.parameter), ')'),

    parameter: ($) =>
      seq(
        repeat($.attribute),
        field('name', $.identifier),
        optional(seq(':', field('type', $.type))),
        optional(field('init', $.initializer))
      ),

    reactor_body: ($) =>
      seq('{', repeat($.reactor_member), '}'),

    reactor_member: ($) =>
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
      ),

    // ========== State Variable ==========
    state_var: ($) =>
      prec.right(seq(
        repeat($.attribute),
        optional('reset'),
        'state',
        field('name', $.identifier),
        optional(seq(':', field('type', $.type))),
        optional(field('init', $.initializer)),
        optional(';')
      )),

    // ========== Method ==========
    method: ($) =>
      seq(
        optional('const'),
        'method',
        field('name', $.identifier),
        '(',
        commaSep($.method_argument),
        ')',
        optional(seq(':', field('return_type', $.type))),
        field('body', $.code_block),
        optional(';')
      ),

    method_argument: ($) =>
      seq(
        field('name', $.identifier),
        optional(seq(':', field('type', $.type)))
      ),

    // ========== Input/Output ==========
    input: ($) =>
      prec.right(seq(
        repeat($.attribute),
        optional('mutable'),
        'input',
        optional(field('width', $.width_spec)),
        field('name', $.identifier),
        optional(seq(':', field('type', $.type))),
        optional(';')
      )),

    output: ($) =>
      prec.right(seq(
        repeat($.attribute),
        'output',
        optional(field('width', $.width_spec)),
        field('name', $.identifier),
        optional(seq(':', field('type', $.type))),
        optional(';')
      )),

    // ========== Timer ==========
    timer: ($) =>
      prec.right(seq(
        repeat($.attribute),
        'timer',
        field('name', $.identifier),
        optional($.timer_spec),
        optional(';')
      )),

    timer_spec: ($) =>
      seq(
        '(',
        field('offset', $.expression),
        optional(seq(',', field('period', $.expression))),
        ')'
      ),

    // ========== Action ==========
    action: ($) =>
      prec.right(seq(
        repeat($.attribute),
        optional(field('origin', $.action_origin)),
        'action',
        field('name', $.identifier),
        optional($.action_spec),
        optional(seq(':', field('type', $.type))),
        optional(';')
      )),

    action_origin: ($) => choice('logical', 'physical'),

    action_spec: ($) =>
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
      ),

    // ========== Watchdog ==========
    watchdog: ($) =>
      seq(
        repeat($.attribute),
        'watchdog',
        field('name', $.identifier),
        '(',
        field('timeout', $.expression),
        ')',
        optional(seq('->', commaSep1($.var_ref_or_mode_transition))),
        field('handler', $.code_block)
      ),

    // ========== Reaction ==========
    reaction: ($) =>
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
      )),

    trigger_list: ($) => seq('(', commaSep($.trigger_ref), ')'),

    source_list: ($) => prec.right(repeat1($.var_ref)),

    effect_list: ($) => seq('->', commaSep1($.var_ref_or_mode_transition)),

    trigger_ref: ($) => choice($.builtin_trigger, $.var_ref),

    builtin_trigger: ($) => choice('startup', 'shutdown', 'reset'),

    var_ref: ($) =>
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
      )),

    var_ref_or_mode_transition: ($) =>
      choice(
        $.var_ref,
        seq(field('transition', $.mode_transition), '(', field('mode', $.identifier), ')')
      ),

    mode_transition: ($) => choice('reset', 'history'),

    stp: ($) =>
      seq(choice('STP', 'STAA'), '(', field('value', $.expression), ')', optional($.code_block)),

    tardy: ($) => seq('tardy', optional($.code_block)),

    deadline: ($) =>
      seq('deadline', '(', field('delay', $.expression), ')', field('handler', $.code_block)),

    // ========== Mode ==========
    mode: ($) =>
      seq(
        optional('initial'),
        'mode',
        optional(field('name', $.identifier)),
        '{',
        repeat($.mode_member),
        '}'
      ),

    mode_member: ($) =>
      choice(
        $.state_var,
        $.timer,
        $.action,
        $.watchdog,
        $.instantiation,
        $.connection,
        $.reaction
      ),

    // ========== Instantiation ==========
    instantiation: ($) =>
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
      )),

    type_arguments: ($) => seq('<', commaSep1($.type), '>'),

    assignment: ($) =>
      seq(field('lhs', $.identifier), field('rhs', $.initializer)),

    // ========== Connection ==========
    connection: ($) =>
      prec.right(seq(
        repeat($.attribute),
        field('left', $.connection_left),
        field('arrow', choice('->', '~>')),
        field('right', commaSep1($.var_ref)),
        optional(seq('after', field('delay', $.expression))),
        optional($.serializer),
        optional(';')
      )),

    connection_left: ($) =>
      choice(
        prec(1, seq('(', commaSep1($.var_ref), ')', optional('+'))),
        commaSep1($.var_ref)
      ),

    serializer: ($) => seq('serializer', $.string),

    // ========== Attributes ==========
    attribute: ($) =>
      prec.right(seq(
        '@',
        field('name', $.identifier),
        optional(seq('(', commaSep($.attribute_parameter), ')'))
      )),

    attribute_parameter: ($) =>
      seq(
        optional(seq(field('name', $.identifier), '=')),
        field('value', choice($.literal, $.time))
      ),

    // ========== Key-Value Pairs (for target config) ==========
    key_value_pairs: ($) => seq('{', commaSep($.key_value_pair), '}'),

    key_value_pair: ($) =>
      seq(field('key', choice($.kebab, $.string)), ':', field('value', $.element)),

    kebab: ($) => seq($.identifier, repeat(seq('-', $.identifier))),

    element: ($) =>
      choice($.key_value_pairs, $.array, $.time, $.literal, $.path),

    array: ($) => seq('[', commaSep($.element), ']'),

    // ========== Type System ==========
    type: ($) =>
      choice(
        'time',
        seq(
          $.dotted_name,
          optional($.type_arguments),
          repeat('*'),
          optional($.c_style_array_spec)
        ),
        $.code_block
      ),

    dotted_name: ($) => prec.left(seq($.identifier, repeat(seq(choice('.', '::'), $.identifier)))),

    c_style_array_spec: ($) => seq('[', choice(']', seq($.integer, ']'))),

    // ========== Width Specification ==========
    width_spec: ($) =>
      seq(
        '[',
        choice(
          ']', // Variable length
          seq($.width_body, ']')
        )
      ),

    width_body: ($) => seq($.width_term, repeat(seq('+', $.width_term))),

    width_term: ($) =>
      choice(
        $.integer,
        $.identifier, // parameter reference
        seq('widthof', '(', $.var_ref, ')'),
        $.code_block
      ),

    // ========== Initializer ==========
    initializer: ($) =>
      choice(
        seq('=', $.expression),
        $.braced_list_expression,
        $.parenthesis_list_expression
      ),

    // ========== Expression ==========
    expression: ($) =>
      choice(
        $.time,
        $.literal,
        $.identifier, // parameter reference
        $.code_block,
        $.braced_list_expression,
        $.bracket_list_expression,
        $.parenthesis_list_expression
      ),

    braced_list_expression: ($) => prec(-1, seq('{', commaSep($.expression), '}')),

    bracket_list_expression: ($) => seq('[', commaSep($.expression), ']'),

    parenthesis_list_expression: ($) => seq('(', commaSep($.expression), ')'),

    // ========== Time ==========
    time: ($) =>
      choice(
        seq(field('interval', $.integer), field('unit', $.time_unit)),
        'forever',
        'never'
      ),

    time_unit: ($) =>
      choice(
        'nsec', 'usec', 'msec', 'sec', 'secs', 'second', 'seconds',
        'min', 'mins', 'minute', 'minutes',
        'hour', 'hours',
        'day', 'days',
        'week', 'weeks',
        // Short forms
        'ns', 'us', 'ms', 's', 'm', 'h', 'd'
      ),

    // ========== Host ==========
    host: ($) => choice($.ipv4_host, $.ipv6_host, $.named_host),

    ipv4_host: ($) =>
      seq(
        optional(seq($.kebab, '@')),
        $.ipv4_addr,
        optional(seq(':', $.integer))
      ),

    ipv6_host: ($) =>
      seq(
        '[',
        optional(seq($.kebab, '@')),
        $.ipv6_addr,
        ']',
        optional(seq(':', $.integer))
      ),

    named_host: ($) =>
      seq(
        optional(seq($.kebab, '@')),
        $.hostname,
        optional(seq(':', $.integer))
      ),

    hostname: ($) => seq($.kebab, repeat(seq('.', $.kebab))),

    ipv4_addr: ($) => /\d+\.\d+\.\d+\.\d+/,

    ipv6_addr: ($) => /[0-9a-fA-F:]+/,

    // ========== Literals ==========
    literal: ($) =>
      choice($.string, $.char_literal, $.number, $.boolean),

    string: ($) =>
      choice(
        $.double_quoted_string,
        $.triple_double_quoted_string
      ),

    double_quoted_string: ($) => /"[^"\\]*(?:\\.[^"\\]*)*"/,

    triple_double_quoted_string: ($) => /"""[\s\S]*?"""/,

    char_literal: ($) => /'[^'\\](?:\\.[^'\\])*'/,

    number: ($) => choice($.float, $.integer),

    integer: ($) => /-?\d+/,

    float: ($) => /-?\d*\.\d+([eE][+-]?\d+)?/,

    boolean: ($) => choice('true', 'false', 'True', 'False'),

    // ========== Code Block ==========
    code_block: ($) => seq('{=', optional($._code_body), '=}'),

    // ========== Comments ==========
    line_comment: ($) => token(choice(seq('//', /.*/), seq('#', /.*/))),

    block_comment: ($) =>
      token(seq('/*', /[^*]*\*+([^/*][^*]*\*+)*/, '/')),

    // ========== Identifier ==========
    identifier: ($) => /[a-zA-Z_][a-zA-Z0-9_]*/,
  },
});
