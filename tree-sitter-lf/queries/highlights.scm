; Lingua Franca syntax highlighting queries for Neovim

; ============================================================================
; Keywords
; ============================================================================

; Target declaration
"target" @keyword
(target_language) @constant.builtin

; Reactor keywords
"reactor" @keyword.type
"main" @keyword.modifier
"federated" @keyword.modifier
"realtime" @keyword.modifier
"extends" @keyword

; Member keywords
"input" @keyword
"output" @keyword
"state" @keyword
"timer" @keyword
"action" @keyword
"watchdog" @keyword
"reaction" @keyword.function
(mutation) @keyword.function
"method" @keyword.function
"preamble" @keyword

; Control keywords
"mode" @keyword
"initial" @keyword.modifier
"reset" @keyword
"history" @keyword

; Modifiers
"mutable" @keyword.modifier
"const" @keyword.modifier
"logical" @keyword.modifier
"physical" @keyword.modifier
(visibility) @keyword.modifier

; Import
"import" @keyword.import
"from" @keyword.import
"as" @keyword.import

; Other keywords
"new" @keyword.operator
"after" @keyword
"deadline" @keyword
"at" @keyword
"widthof" @keyword.function
"interleaved" @keyword
"STP" @keyword
"STAA" @keyword
"tardy" @keyword
"serializer" @keyword

; ============================================================================
; Builtin triggers
; ============================================================================

(builtin_trigger) @constant.builtin

; ============================================================================
; Types
; ============================================================================

"time" @type.builtin

(type
  (dotted_name) @type)

(type_parameter) @type

; ============================================================================
; Functions and Methods
; ============================================================================

(method
  name: (identifier) @function.method)

(reaction
  name: (identifier) @function)

; ============================================================================
; Variables and Fields
; ============================================================================

; Reactor name
(reactor
  name: (identifier) @type)

; State variable
(state_var
  name: (identifier) @variable)

; Input/output ports
(input
  name: (identifier) @variable)
(output
  name: (identifier) @variable)

; Timer
(timer
  name: (identifier) @variable)

; Action
(action
  name: (identifier) @variable)

; Watchdog
(watchdog
  name: (identifier) @variable)

; Mode
(mode
  name: (identifier) @label)

; Instantiation
(instantiation
  name: (identifier) @variable)
(instantiation
  class: (identifier) @type)

; Parameters
(parameter
  name: (identifier) @variable.parameter)

; Method arguments
(method_argument
  name: (identifier) @variable.parameter)

; Variable references
(var_ref
  container: (identifier) @variable)
(var_ref
  variable: (identifier) @variable)

; Assignment
(assignment
  lhs: (identifier) @variable.parameter)

; ============================================================================
; Imports
; ============================================================================

(imported_reactor
  class: (identifier) @type)
(imported_reactor
  alias: (identifier) @type)

; ============================================================================
; Attributes
; ============================================================================

(attribute
  name: (identifier) @attribute)
(attribute_parameter
  name: (identifier) @property)

; ============================================================================
; Key-value pairs (for target config)
; ============================================================================

(key_value_pair
  key: (kebab) @property)
(key_value_pair
  key: (string) @property)

; ============================================================================
; Time units
; ============================================================================

((time_unit
  (identifier) @keyword)
  (#match? @keyword "^(nsecs?|usecs?|msecs?|secs?|seconds?|mins?|minutes?|hours?|days?|weeks?|ns|us|ms|[smhd])$"))

; ============================================================================
; Literals
; ============================================================================

(boolean) @constant.builtin
(integer) @number
(float) @number.float
(string) @string
(char_literal) @character
"forever" @constant.builtin
"never" @constant.builtin

; ============================================================================
; Operators
; ============================================================================

"->" @operator
"~>" @operator
"=" @operator
":" @punctuation.delimiter
"::" @punctuation.delimiter
"." @punctuation.delimiter
"," @punctuation.delimiter
";" @punctuation.delimiter
"@" @punctuation.special

; ============================================================================
; Brackets and delimiters
; ============================================================================

"(" @punctuation.bracket
")" @punctuation.bracket
"[" @punctuation.bracket
"]" @punctuation.bracket
"{" @punctuation.bracket
"}" @punctuation.bracket
"<" @punctuation.bracket
">" @punctuation.bracket

; Code block delimiters
"{=" @punctuation.special
"=}" @punctuation.special

; ============================================================================
; Comments
; ============================================================================

(line_comment) @comment
(block_comment) @comment

; ============================================================================
; Code block content (target language)
; ============================================================================

(code_block) @none
