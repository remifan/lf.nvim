; Lingua Franca injection queries for embedded target language highlighting
;
; This allows the code inside {= =} blocks to be highlighted using the
; appropriate language parser based on the target declaration.

; Inject Python into code blocks
; TODO: Detect target language from target declaration and inject accordingly
((code_block) @injection.content
 (#set! injection.language "python")
 (#set! injection.include-children))
