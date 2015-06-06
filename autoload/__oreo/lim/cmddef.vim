if exists('s:save_cpo')| finish| endif
let s:save_cpo = &cpo| set cpo&vim
scriptencoding utf-8
"=============================================================================
let s:TYPE_LIST = type([])
let s:TYPE_STR = type('')
let s:TYPE_NUM = type(0)
let s:TYPE_FLOAT = type(0.0)

"Misc:
function! s:split_into_words(cmdline) "{{{
  return split(a:cmdline, '\%(\\\@!<\\\)\@<!\s\+')
endfunction
"}}}
function! s:_matches(pat, list) "{{{
  if type(a:pat)==s:TYPE_LIST
    return filter(a:list, 'index(a:pat, v:val)!=-1')
  end
  return filter(a:list, 'v:val =~ a:pat')
endfunction
"}}}
function! s:divisionholder(holder, divisions) "{{{
  for division in a:divisions
    let type = type(division)
    if type==s:TYPE_LIST
      call s:divisionholder(a:holder, division)
    elseif type==s:TYPE_STR
      if division!=''
        let a:holder[division] = 1
      end
    elseif type==s:TYPE_NUM || type==s:TYPE_FLOAT
      let a:holder[string(division)] = 1
    end
    unlet division
  endfor
  return a:holder
endfunction
"}}}
let s:Assorter = {}
function! s:newAssorter(inputs) "{{{
  let obj = copy(s:Assorter)
  let obj.inputs = a:inputs
  let obj.should_del_groups = {}
  let obj.candidates = []
  let obj.divisions = []
  return obj
endfunction
"}}}
function! s:Assorter.assort_candidates(candidates) "{{{
  for cand in a:candidates
    let type = type(cand)
    if type!=s:TYPE_LIST
      let cnd = type==s:TYPE_STR ? cand : string(cand)
      if cnd!='' && index(self.inputs, cnd)==-1
        call self._add([cnd], [{}])
      end
    elseif cand!=[]
      call self._assort_listcand(cand)
    end
    unlet cand
  endfor
endfunction
"}}}
function! s:Assorter._assort_listcand(cand) "{{{
  let type = type(a:cand[0])
  if !(type==s:TYPE_NUM || type==s:TYPE_FLOAT || type==s:TYPE_STR && a:cand[0]!='')
    return
  end
  let cnd = type==s:TYPE_STR ? a:cand[0] : string(a:cand[0])
  let division = s:divisionholder({}, a:cand[1:])
  if cnd!='' && index(self.inputs, cnd)==-1
    call self._add([cnd], [division])
    return
  end
  call extend(self.should_del_groups, division)
  if has_key(division, '__PARM')
    call self._add([cnd], [division])
  end
endfunction
"}}}
function! s:Assorter._add(cand, division) "{{{
  let self.candidates += a:cand
  let self.divisions += a:division
endfunction
"}}}
function! s:Assorter.remove_del_grouped_candidates() "{{{
  if has_key(self.should_del_groups, '__PARM')
    unlet self.should_del_groups.__PARM
  end
  if self.should_del_groups!={}
    let divisions = self.divisions
    call filter(self.candidates, 'has_key(divisions[v:key], "__PARM") || !('. join(map(keys(self.should_del_groups), '"has_key(divisions[v:key], ''". v:val. "'')"'), '||'). ')')
  end
  return self.candidates
endfunction
"}}}

let s:func = {}
function! s:func._get_optignorepat() "{{{
  return '^\%('.self._shortoptbgn.'\|'.self._longoptbgn.'\)\S'
endfunction
"}}}
function! s:func._get_arg(pat, variadic, list) "{{{
  let type = type(a:pat)
  if type==s:TYPE_STR
    let default = get(a:variadic, 0, '')
    let idx = match(a:list, a:pat)
    return idx==-1 ? default : matchstr(a:list[idx], a:pat)
  elseif type==s:TYPE_LIST
    let [idx, default] = s:_solve_variadic_for_set_default(a:variadic, [0, ''])
    return get(filter(copy(a:list), 'index(a:pat, v:val)!=-1'), idx, default)
  end
  let [is_ignoreopt, default] = s:_solve_variadic_for_set_default(a:variadic, [0, ''])
  let list = copy(a:list)
  if is_ignoreopt
    let ignorepat = self._get_optignorepat()
    call filter(list, 'v:val !~# ignorepat')
  end
  return get(list, a:pat, default)
endfunction
"}}}
function! s:_solve_variadic_for_set_default(variadic, default) "{{{
  let [num, default] = a:default
  for val in a:variadic
    if type(val)==s:TYPE_STR
      let default = val
    else
      let num = val
    end
    unlet val
  endfor
  return [num, default]
endfunction
"}}}


"=============================================================================
"Main:
let s:Cmdcmpl = {}
function! __oreo#lim#cmddef#newCmdcmpl(cmdline, cursorpos, ...) abort "{{{
  let obj = copy(s:Cmdcmpl)
  let behavior = a:0 ? a:1 : {}
  let obj._longoptbgn = get(behavior, 'longoptbgn', '--')
  let obj._shortoptbgn = get(behavior, 'shortoptbgn', '-')
  let obj.cmdline = a:cmdline
  let obj.cursorpos = a:cursorpos
  let obj._is_on_edge = a:cmdline[a:cursorpos-1]!=' ' ? 0 : a:cmdline[a:cursorpos-2]!='/' || a:cmdline[a:cursorpos-3]=='/'
  let [obj.command; obj.inputs] = s:split_into_words(a:cmdline)
  let obj.leftwords = s:split_into_words(a:cmdline[:(a:cursorpos-1)])[1:]
  let obj.arglead = obj._is_on_edge ? '' : obj.leftwords[-1]
  let obj.preword = obj._is_on_edge ? get(obj.leftwords, -1, '') : get(obj.leftwords, -2, '')
  let obj._save_leftargscnt = {}
  return obj
endfunction
"}}}
let s:Cmdcmpl._get_optignorepat = s:func._get_optignorepat
let s:Cmdcmpl._get_arg = s:func._get_arg
function! s:Cmdcmpl.get_arglead() "{{{
  return self.arglead
endfunction
"}}}
function! s:Cmdcmpl.has_bang() "{{{
  return self.command =~ '!$'
endfunction
"}}}
function! s:Cmdcmpl.count_lefts(...) "{{{
  let NULL = "\<C-n>"
  let ignorepat = a:0 ? a:1 : self._get_optignorepat()
  let ignorepat = ignorepat=='' ? NULL : ignorepat
  if has_key(self._save_leftargscnt, ignorepat)
    return self._save_leftargscnt[ignorepat]
  end
  let leftwords = copy(self.leftwords)
  if ignorepat != NULL
    call filter(leftwords, 'v:val !~# ignorepat')
  end
  let ret = len(leftwords)
  let self._save_leftargscnt[ignorepat] = self._is_on_edge ? ret : ret-1
  return self._save_leftargscnt[ignorepat]
endfunction
"}}}
function! s:Cmdcmpl.should_optcmpl() "{{{
  let pat = '^'.self._shortoptbgn.'\|^'.self._longoptbgn
  return pat!='^\|^' && self.arglead =~# pat
endfunction
"}}}
function! s:Cmdcmpl.is_matched(pat) "{{{
  return self.arglead =~# a:pat
endfunction
"}}}
function! s:Cmdcmpl.get(pat, ...) "{{{
  return self._get_arg(a:pat, a:000, self.inputs)
endfunction
"}}}
function! s:Cmdcmpl.matches(pat) "{{{
  return s:_matches(a:pat, copy(self.inputs))
endfunction
"}}}
function! s:Cmdcmpl.get_left(pat, ...) "{{{
  return self._get_arg(a:pat, a:000, self.leftwords)
endfunction
"}}}
function! s:Cmdcmpl.match_lefts(pat) "{{{
  return s:_matches(a:pat, copy(self.leftwords))
endfunction
"}}}
function! s:Cmdcmpl._filtered_by_inputs(candidates) "{{{
  let assorter = s:newAssorter(self.inputs)
  call assorter.assort_candidates(a:candidates)
  return assorter.remove_del_grouped_candidates()
  let canddicts = map(a:candidates, 's:dictify_{type(v:val)}(v:val)')
  let should_del_groups = {}
  for canddict in canddicts
    if index(self.inputs, get(canddict, 'word', ''))!=-1
      call extend(should_del_groups, canddict.division)
    end
  endfor
  let expr = should_del_groups=={} ? '' : '!('. join(map(keys(should_del_groups), '"has_key(v:val.division, ''". v:val. "'')"'), '||'). ') &&'
  call filter(canddicts, 'v:val!={} && ( v:val.is_parm || '. expr. ' index(self.inputs, v:val.word)==-1 )')
  return map(canddicts, 'v:val.word')
endfunction
"}}}
function! s:Cmdcmpl.filtered(candidates) "{{{
  let candidates = self._filtered_by_inputs(a:candidates)
  return filter(candidates, 'v:val =~ "^".self.arglead')
endfunction
"}}}
function! s:Cmdcmpl.backward_filtered(candidates) "{{{
  let candidates = self._filtered_by_inputs(a:candidates)
  return filter(candidates, 'v:val =~ self.arglead."$"')
endfunction
"}}}
function! s:Cmdcmpl.partial_filtered(candidates) "{{{
  let candidates = self._filtered_by_inputs(a:candidates)
  return filter(candidates, 'v:val =~ self.arglead')
endfunction
"}}}
function! s:Cmdcmpl.exact_filtered(candidates) "{{{
  let candidates = self._filtered_by_inputs(a:candidates)
  return filter(candidates, 'v:val == self.arglead')
endfunction
"}}}


"--------------------------------------
let s:CmdParser = {}
function! __oreo#lim#cmddef#newCmdParser(args, ...) "{{{
  let obj = copy(s:CmdParser)
  let behavior = a:0 ? a:1 : {}
  let obj._longoptbgn = get(behavior, 'longoptbgn', '--')
  let obj._shortoptbgn = get(behavior, 'shortoptbgn', '-')
  let obj.assignpat = get(behavior, 'assignpat', '=')
  let obj.endpat = '\%('. obj.assignpat. '\(.*\)\)\?$'
  let obj.args = a:args
  let obj.args_original = copy(a:args)
  return obj
endfunction
"}}}
let s:CmdParser._get_optignorepat = s:func._get_optignorepat
let s:CmdParser._get_arg = s:func._get_arg
function! s:CmdParser.get(pat, ...) "{{{
  return self._get_arg(a:pat, a:000, self.args)
endfunction
"}}}
function! s:CmdParser.matches(pat) "{{{
  return s:_matches(a:pat, copy(self.args))
endfunction
"}}}
function! s:CmdParser.divide(pat, ...) "{{{
  let way = a:0 ? a:1 : 'sep'
  let self._len = len(self.args)
  try
    let ret = self['_divide_'. way](a:pat)
  catch /E716/
    echoerr 'CmdParser: invalid way > "'. way. '"'
    return self.arg
  endtry
  return ret==[[]] ? [] : ret
endfunction
"}}}
function! s:CmdParser.filter(pat, ...) "{{{
  let __cmpparser_args__ = self.args
  if a:0
    for __cmpparser_key__ in keys(a:1)
      exe printf('let %s = a:1[__cmpparser_key__]', __cmpparser_key__)
    endfor
  end
  return filter(__cmpparser_args__, a:pat)
endfunction
"}}}
function! s:CmdParser.parse_options(optdict, ...) "{{{
  let [self._first, self._last] = a:0 ? type(a:1)==s:TYPE_LIST ? a:1 : [a:1, a:1] : [0, -1]
  let self._last = self._last < 0 ? len(self.args) + self._last : self._last
  let ret = {}
  for [key, vals] in items(a:optdict)
    let ret[key] = self._get_optval(self._get_optval_evalset(vals, key))
    unlet vals
  endfor
  return ret
endfunction
"}}}

function! s:CmdParser._get_optval_evalset(vals, part_of_pats) "{{{
  let [default, pats, invertpats] = [0, [self._longoptbgn. a:part_of_pats], []]
  if type(a:vals) != s:TYPE_LIST
    return [a:vals, pats, invertpats]
  end
  let types = map(copy(a:vals), 'type(v:val)')
  if index(types, s:TYPE_LIST)==-1
    return a:vals==[] ? [default, pats, invertpats] : types[0]== s:TYPE_STR ? [default, a:vals, invertpats] : [a:vals, pats, invertpats]
  end
  let [len, i, done_pats] = [len(a:vals), 0, 0]
  while i < len
    if types[i]==s:TYPE_LIST
      exe 'let' (done_pats ? 'invertpats' : 'pats') '= a:vals[i]'
      let done_pats = 1
    else
      let default = a:vals[i]
    end
    let i += 1
  endwhile
  return [default, pats, invertpats]
endfunction
"}}}
function! s:CmdParser._get_optval(optval_evalset) "{{{
  let [default, optpats, invertpats] = a:optval_evalset
  if self._first<0
    return default
  end
  for pat in invertpats
    let [optval, is_matched] = self._solve_optpat(pat)
    if is_matched
      return 0
    end
  endfor
  for pat in optpats
    let [optval, is_matched] = self._solve_optpat(pat)
    if is_matched
      return optval
    end
  endfor
  return default
endfunction
"}}}
function! s:CmdParser._solve_optpat(pat) "{{{
  if a:pat =~# '^'.self._longoptbgn || a:pat !~# '^'.self._shortoptbgn.'.$'
    let i = match(self.args, '^'.a:pat. self.endpat, self._first)
    if i!=-1 && i <= self._last
      call self._adjust_ranges()
      return [self._solve_optval(substitute(remove(self.args, i), '^'. a:pat, '', '')), 1]
    end
  else
    let shortchr = matchstr(a:pat, '^'.self._shortoptbgn.'\zs.$')
    let i = match(self.args, printf('^\%%(%s\)\@!\&^%s.\{-}%s.\{-}%s', self._longoptbgn, self._shortoptbgn, shortchr, self.endpat), self._first)
    if i!=-1 && i <= self._last
      let optval = matchstr(self.args[i], shortchr. '\zs'. self.assignpat.'.*$')
      let self.args[i] = substitute(self.args[i], '^'. self._shortoptbgn.'.\{-}\zs'.shortchr. (optval=='' ? '' : self.assignpat.'.*'), '', '')
      if self.args[i] ==# self._shortoptbgn
        unlet self.args[i]
        call self._adjust_ranges()
      end
      return [self._solve_optval(optval), 1]
    end
  end
  return ['', 0]
endfunction
"}}}
function! s:CmdParser._solve_optval(optval) "{{{
  return a:optval=='' ? 1 : matchstr(a:optval, '^'. self.assignpat. '\zs.*')
endfunction
"}}}
function! s:CmdParser._adjust_ranges() "{{{
  if self._first == self._last
    let self._first -= 1
  end
  let self._last -= 1
endfunction
"}}}
function! s:CmdParser._get_firstmatch_idx(patlist, bgnidx) "{{{
  let i = a:bgnidx
  while i < self._len
    if index(a:patlist, self.args[i])!=-1
      return i
    end
    let i+=1
  endwhile
  return -1
endfunction
"}}}
function! s:CmdParser._divide_start(pat) "{{{
  let expr = type(a:pat)==s:TYPE_LIST ? 'self._get_firstmatch_idx(a:pat, i+1)' : 'match(self.args, a:pat, i+1)'
  let ret = []
  let i = 0
  let j = eval(expr)
  while j!=-1
    call add(ret, self.args[i :j-1])
    let i = j
    let j = eval(expr)
  endwhile
  call add(ret, self.args[i :-1])
  return ret
endfunction
"}}}
function! s:CmdParser._divide_sep(pat) "{{{
  let expr = type(a:pat)==s:TYPE_LIST ? 'self._get_firstmatch_idx(a:pat, i)' : 'match(self.args, a:pat, i)'
  let ret = []
  let i = 0
  let j = eval(expr)
  while j!=-1
    if j-i != 0
      call add(ret, self.args[i :j-1])
    end
    let i = j+1
    let j = eval(expr)
  endwhile
  if i < self._len
    call add(ret, self.args[i :-1])
  end
  return ret
endfunction
"}}}
function! s:CmdParser._divide_stop(pat) "{{{
  let expr = type(a:pat)==s:TYPE_LIST ? 'self._get_firstmatch_idx(a:pat, i)' : 'match(self.args, a:pat, i)'
  let ret = []
  let i = 0
  let j = eval(expr)
  while j!=-1
    call add(ret, self.args[i :j])
    let i = j+1
    let j = eval(expr)
  endwhile
  if i < self._len
    call add(ret, self.args[i :-1])
  end
  return ret
endfunction
"}}}


"=============================================================================
"END "{{{1
let &cpo = s:save_cpo| unlet s:save_cpo