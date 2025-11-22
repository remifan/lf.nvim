" Vim filetype plugin for Lingua Franca
" Language: Lingua Franca
" Maintainer: Generated for Neovim

if exists("b:did_ftplugin")
  finish
endif
let b:did_ftplugin = 1

" Set comment strings for commenting plugins
setlocal commentstring=//\ %s
setlocal comments=://,:#,sO:*\ -,mO:*\ \ ,exO:*/,s1:/*,mb:*,ex:*/

" Set formatting options
setlocal formatoptions-=t formatoptions+=croql

" Enable folding on reactor/preamble blocks
setlocal foldmethod=syntax
setlocal foldlevel=99

" Set indentation
setlocal expandtab
setlocal shiftwidth=4
setlocal softtabstop=4
setlocal tabstop=4

" Undo ftplugin settings
let b:undo_ftplugin = "setlocal commentstring< comments< formatoptions< foldmethod< foldlevel< expandtab< shiftwidth< softtabstop< tabstop<"
