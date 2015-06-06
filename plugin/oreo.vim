if expand('<sfile>:p')!=#expand('%:p') && exists('g:loaded_oreo')| finish| endif| let g:loaded_oreo = 1
let s:save_cpo = &cpo| set cpo&vim
scriptencoding utf-8
"=============================================================================
let g:oreo#config_dir = get(g:, 'oreo#config_dir', '~/.config/vim/oreo.vim')
let g:oreo#libs = get(g:, 'oreo#libs', {})
let g:oreo#is_verticaldiff = get(g:, 'oreo#is_verticaldiff', 1)

command! -nargs=* -complete=customlist,oreo#cmpl_attract  OreoAttract    call oreo#enter_attract([<f-args>])
command! -nargs=* -complete=customlist,oreo#cmpl_extract  OreoExtract    call oreo#enter_extract([<f-args>])
command! -nargs=* -complete=customlist,oreo#cmpl_update  OreoUpdate    call oreo#enter_update([<f-args>])
command! -nargs=* -complete=customlist,oreo#cmpl_libs   OreoStatus    call oreo#enter_status([<f-args>])
command! -nargs=0   OreoLog    call oreo#log()
command! -nargs=+ -complete=customlist,oreo#cmpl_diff  OreoDiff    call oreo#enter_diff([<f-args>])

if !exists('#lib_lock')
  aug lib_lock
    autocmd BufEnter */autoload/__*/**/*.vim  call oreo#lock()
  aug END
endif
aug oreo
  au!
  autocmd ColorScheme *  call s:define_cmphl()
aug END

function! s:define_cmphl() "{{{
  highlight default OreoAdd   guifg=Green ctermfg=Green gui=bold cterm=bold
  highlight default OreoNotEqual   guifg=Cyan ctermfg=Cyan
  highlight default OreoUpdate   guifg=Cyan ctermfg=Cyan gui=bold cterm=bold
  highlight default OreoDelete   guifg=Red ctermfg=Red gui=bold cterm=bold
  highlight default OreoBold  gui=bold cterm=bold
  highlight default OreoQuiet   guifg=DimGray ctermfg=Gray
  highlight default OreoLib   guifg=DarkCyan ctermfg=DarkCyan gui=bold cterm=bold
  highlight default OreoReci   guifg=Magenta ctermfg=Magenta gui=bold cterm=bold
endfunction
"}}}

"=============================================================================
"END "{{{1
let &cpo = s:save_cpo| unlet s:save_cpo
