" Vim syntax file
" Language: Lingua Franca
" Maintainer: Generated for Neovim
" Latest Revision: 2025

if exists("b:current_syntax")
  finish
endif

" Skip regex syntax if tree-sitter highlighting is available
" Tree-sitter provides better highlighting especially for embedded code blocks
if has('nvim') && luaeval('pcall(vim.treesitter.language.inspect, "lf")')
  finish
endif

" Save current syntax name
let s:cpo_save = &cpo
set cpo&vim

" Comments (must be defined early to avoid conflicts)
syn keyword lfTodo contained TODO FIXME XXX NOTE
syn match lfLineComment "//.*$" contains=lfTodo,@Spell
syn match lfLineComment "#.*$" contains=lfTodo,@Spell
syn region lfBlockComment start="/\*" end="\*/" contains=lfTodo,@Spell

" Keywords - Core Language
syn keyword lfKeyword reactor federated main realtime
syn keyword lfKeyword input output action state timer
syn keyword lfKeyword reaction method mode reset continue
syn keyword lfKeyword preamble extends new const
syn keyword lfKeyword target import from as at
syn keyword lfKeyword after interleaved serializer
syn keyword lfKeyword physical logical startup shutdown

" Modifiers
syn keyword lfModifier public private widthof

" Boolean
syn keyword lfBoolean true false True False

" Control flow
syn keyword lfConditional if else
syn keyword lfRepeat for while
syn keyword lfOperator return

" Time units
syn keyword lfTimeUnit nsec usec msec sec min hour day week
syn keyword lfTimeUnit nsecs usecs msecs secs mins hours days weeks

" Numbers
syn match lfNumber '\<\d\+\>'
syn match lfNumber '\<\d\+\.\d*\>'
syn match lfNumber '\<\d*\.\d\+\>'
syn match lfNumber '\<\d\+[eE][+-]\=\d\+\>'
syn match lfNumber '\<\d\+\.\d*[eE][+-]\=\d\+\>'

" Strings
syn region lfString start=+"+ skip=+\\\\\|\\"+ end=+"+ contains=lfEscape
syn region lfString start=+'+ skip=+\\\\\|\\'+ end=+'+ contains=lfEscape
syn region lfString start=+"""+ end=+"""+ contains=lfEscape
syn region lfString start=+'''+ end=+'''+ contains=lfEscape

" Escape sequences
syn match lfEscape contained '\\[nrt"'\\]'
syn match lfEscape contained '\\x\x\{2}'
syn match lfEscape contained '\\u\x\{4}'
syn match lfEscape contained '\\U\x\{8}'

" Operators
syn match lfOperator "->"
syn match lfOperator "\~>"
syn match lfOperator "::"
syn match lfOperator "+"
syn match lfOperator "-"
syn match lfOperator "\*"
syn match lfOperator "/"
syn match lfOperator "%"
syn match lfOperator "="
syn match lfOperator "+="
syn match lfOperator "-="
syn match lfOperator "\*="
syn match lfOperator "/="
syn match lfOperator "@"
syn match lfOperator "\."

" Delimiters
syn match lfDelimiter "("
syn match lfDelimiter ")"
syn match lfDelimiter "\["
syn match lfDelimiter "\]"
syn match lfDelimiter ","
syn match lfDelimiter ";"
syn match lfDelimiter ":"

" Identifiers and Types
syn match lfIdentifier '\<[a-zA-Z_][a-zA-Z0-9_]*\>'
syn match lfType '\<[A-Z][a-zA-Z0-9_]*\>'

" Load embedded language syntaxes
" We need to unset b:current_syntax before including to allow nested syntaxes
unlet! b:current_syntax

" Include C syntax for embedded code
silent! syntax include @lfEmbedC syntax/c.vim
unlet! b:current_syntax

" Include Python syntax for embedded code
silent! syntax include @lfEmbedPython syntax/python.vim
unlet! b:current_syntax

" Include Rust syntax for embedded code
silent! syntax include @lfEmbedRust syntax/rust.vim
unlet! b:current_syntax

" Include TypeScript syntax for embedded code
silent! syntax include @lfEmbedTypeScript syntax/typescript.vim
unlet! b:current_syntax

" Target code regions - delimited by {= and =}
" The region includes all embedded language clusters
syn region lfTargetCode matchgroup=lfTargetDelimiter start="{=" end="=}" contains=@lfEmbedC,@lfEmbedPython,@lfEmbedRust,@lfEmbedTypeScript

" Preamble code regions
syn region lfPreambleCode matchgroup=lfTargetDelimiter start="preamble\s\+{=" end="=}" contains=@lfEmbedC,@lfEmbedPython,@lfEmbedRust,@lfEmbedTypeScript

" Default highlighting
hi def link lfTodo Todo
hi def link lfLineComment Comment
hi def link lfBlockComment Comment
hi def link lfKeyword Keyword
hi def link lfModifier StorageClass
hi def link lfBoolean Boolean
hi def link lfConditional Conditional
hi def link lfRepeat Repeat
hi def link lfOperator Operator
hi def link lfTimeUnit Special
hi def link lfNumber Number
hi def link lfString String
hi def link lfEscape SpecialChar
hi def link lfDelimiter Delimiter
hi def link lfIdentifier Identifier
hi def link lfType Type
hi def link lfTargetDelimiter Special

let b:current_syntax = "lf"

let &cpo = s:cpo_save
unlet s:cpo_save
