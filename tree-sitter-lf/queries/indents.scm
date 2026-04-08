; Lingua Franca indentation queries

; ============================================================================
; Indent
; ============================================================================

; Indent inside reactor body
(reactor_body) @indent.begin

; Indent inside mode
(mode
  "{" @indent.begin)

; Indent inside key-value pairs
(key_value_pairs
  "{" @indent.begin)

; Indent inside arrays
(array
  "[" @indent.begin)

; Indent inside parenthesis lists
(parenthesis_list_expression
  "(" @indent.begin)

; Indent inside braced lists
(braced_list_expression
  "{" @indent.begin)

; ============================================================================
; Dedent
; ============================================================================

"}" @indent.end
"]" @indent.end
")" @indent.end

; ============================================================================
; Align
; ============================================================================

; Align parameters
(parameter_list
  "(" @indent.align)

; Align type arguments
(type_arguments
  "<" @indent.align)

; ============================================================================
; Branch (same level as parent)
; ============================================================================

; These don't need extra indentation
"=}" @indent.branch
