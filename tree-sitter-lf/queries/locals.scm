; Lingua Franca locals queries for scope tracking
; Used for incremental selection and local variable references

; ============================================================================
; Scopes - Define scope boundaries for incremental selection
; ============================================================================

; Top-level file scope
(source_file) @local.scope

; Reactor is a scope (entire reactor declaration)
(reactor) @local.scope

; Reactor body is a scope
(reactor_body) @local.scope

; Mode is a scope
(mode) @local.scope

; Reaction is a scope (includes triggers, effects, and body)
(reaction) @local.scope

; Code block (target language code) is a scope
(code_block) @local.scope

; Method is a scope
(method) @local.scope

; Preamble is a scope
(preamble) @local.scope

; Key-value pairs (target config) is a scope
(key_value_pairs) @local.scope

; Trigger list is a scope (for selection expanding within triggers)
(trigger_list) @local.scope

; Effect list is a scope
(effect_list) @local.scope

; Parameter list is a scope
(parameter_list) @local.scope

; Deadline handler is a scope
(deadline) @local.scope

; Watchdog is a scope
(watchdog) @local.scope

; Connection is a scope
(connection) @local.scope

; Instantiation is a scope
(instantiation) @local.scope

; Import statement is a scope
(import_statement) @local.scope

; Target declaration is a scope
(target_declaration) @local.scope

; ============================================================================
; Definitions - Variables defined in scopes
; ============================================================================

; Reactor definition
(reactor
  name: (identifier) @local.definition.type)

; State variable definition
(state_var
  name: (identifier) @local.definition.var)

; Input port definition
(input
  name: (identifier) @local.definition.var)

; Output port definition
(output
  name: (identifier) @local.definition.var)

; Timer definition
(timer
  name: (identifier) @local.definition.var)

; Action definition
(action
  name: (identifier) @local.definition.var)

; Watchdog definition
(watchdog
  name: (identifier) @local.definition.var)

; Instantiation definition
(instantiation
  name: (identifier) @local.definition.var)

; Parameter definition
(parameter
  name: (identifier) @local.definition.parameter)

; Method argument definition
(method_argument
  name: (identifier) @local.definition.parameter)

; Method definition
(method
  name: (identifier) @local.definition.function)

; Mode definition
(mode
  name: (identifier) @local.definition.type)

; Import alias
(imported_reactor
  name: (identifier) @local.definition.type)

; ============================================================================
; References - References to defined variables
; ============================================================================

; Variable references
(var_ref
  variable: (identifier) @local.reference)

; Container references
(var_ref
  container: (identifier) @local.reference)

; Parameter references in assignments
(assignment
  lhs: (identifier) @local.reference)

; Type references
(instantiation
  class: (identifier) @local.reference)
