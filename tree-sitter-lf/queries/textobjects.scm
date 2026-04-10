; Lingua Franca text objects for nvim-treesitter-textobjects
;
; These queries define selectable text objects for common code patterns.
; They work with nvim-treesitter-textobjects plugin.
;
; Also used by incremental selection to define meaningful selection nodes.

; ============================================================================
; Function/Method text objects (@function.inner, @function.outer)
; ============================================================================

; Reaction as function
(reaction
  body: (code_block) @function.inner) @function.outer

; Reaction without body (still selectable as outer)
(reaction) @function.outer

; Method as function
(method
  code: (code_block) @function.inner) @function.outer

; Deadline handler
(deadline
  code: (code_block) @function.inner) @function.outer

; Watchdog handler
(watchdog
  handler: (code_block) @function.inner) @function.outer

; Preamble as function (contains target language code)
(preamble
  code: (code_block) @function.inner) @function.outer

; ============================================================================
; Class text objects (@class.inner, @class.outer)
; ============================================================================

; Reactor as class
(reactor
  body: (reactor_body) @class.inner) @class.outer

; Mode as class
(mode) @class.outer

; ============================================================================
; Parameter text objects (@parameter.inner, @parameter.outer)
; ============================================================================

; Reactor parameters
(parameter) @parameter.outer
(parameter
  name: (identifier) @parameter.inner)

; Method arguments
(method_argument) @parameter.outer
(method_argument
  name: (identifier) @parameter.inner)

; Assignment parameters
(assignment) @parameter.outer

; ============================================================================
; Statement text objects (@statement.outer)
; ============================================================================

; Member declarations as statements
(state_var) @statement.outer
(input) @statement.outer
(output) @statement.outer
(timer) @statement.outer
(action) @statement.outer
(instantiation) @statement.outer
(connection) @statement.outer
(reaction) @statement.outer

; ============================================================================
; Block text objects (@block.inner, @block.outer)
; ============================================================================

; Reactor body
(reactor_body) @block.outer
(reactor_body
  "{" . (_)* @block.inner . "}")

; Code block
(code_block) @block.outer

; Key-value pairs
(key_value_pairs) @block.outer

; ============================================================================
; Comment text objects (@comment.outer)
; ============================================================================

(line_comment) @comment.outer
(block_comment) @comment.outer

; ============================================================================
; Conditional text objects (@conditional.outer)
; ============================================================================

; Mode can be considered conditional
(mode) @conditional.outer

; ============================================================================
; Loop text objects - N/A for LF but included for completeness
; ============================================================================

; LF doesn't have traditional loops at the coordination level

; ============================================================================
; Call text objects (@call.outer, @call.inner)
; ============================================================================

; Instantiation as a "call" to create reactor instance
(instantiation) @call.outer
(instantiation
  class: (identifier) @call.inner)

; ============================================================================
; Assignment text objects (@assignment.outer, @assignment.lhs, @assignment.rhs)
; ============================================================================

(instantiation
  name: (identifier) @assignment.lhs
  class: (identifier) @assignment.rhs) @assignment.outer

(state_var
  name: (identifier) @assignment.lhs
  init: (_) @assignment.rhs) @assignment.outer

; ============================================================================
; Scope text objects (@scope.inner, @scope.outer) - For incremental selection
; ============================================================================

; Reactor scope
(reactor
  body: (reactor_body) @scope.inner) @scope.outer

; Mode scope
(mode) @scope.outer

; ============================================================================
; Number text objects (@number.inner)
; ============================================================================

(integer) @number.inner
(float) @number.inner
(time
  interval: (integer) @number.inner)

; ============================================================================
; String text objects
; ============================================================================

(double_quoted_string) @string.inner
(triple_double_quoted_string) @string.inner

; ============================================================================
; Attribute text objects (@attribute.outer, @attribute.inner)
; ============================================================================

(attribute) @attribute.outer
(attribute
  name: (identifier) @attribute.inner)

; ============================================================================
; Import text objects (@import.outer)
; ============================================================================

(import_statement) @import.outer
(imported_reactor) @import.inner

; ============================================================================
; Return/Effect text objects (@return.outer, @return.inner)
; ============================================================================

; Effect list in reaction (what the reaction can write to)
(effect_list) @return.outer
(var_ref_or_mode_transition) @return.inner

; ============================================================================
; Swap nodes - nodes that can be swapped with siblings
; ============================================================================

; Parameters can be swapped
(parameter) @swap

; Reactor members can be swapped
(state_var) @swap
(input) @swap
(output) @swap
(timer) @swap
(action) @swap
(reaction) @swap
(instantiation) @swap
(connection) @swap

; Triggers can be swapped
(trigger_ref) @swap

; Effects can be swapped
(var_ref_or_mode_transition) @swap

; Key-value pairs can be swapped
(key_value_pair) @swap

; Imported reactors can be swapped
(imported_reactor) @swap
