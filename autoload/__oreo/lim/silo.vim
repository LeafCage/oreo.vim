if exists('s:save_cpo')| finish| endif
let s:save_cpo = &cpo| set cpo&vim
scriptencoding utf-8
"=============================================================================
let g:__oreo#lim#silo#rootdir = get(g:, '__oreo#lim#silo#rootdir', '~/.config/silo/'. matchstr(expand('<sfile>'), 'autoload/\zs.\{-1,}\ze/'))
let s:SEP = "\<C-k>\<Tab>"
let s:TYPE_LIST = type([])
let s:TYPE_DICT = type({})
let s:TYPE_STR = type('')
let s:CNV = {'m': {'.*': '.\{-}', '.\+': '.\{-1,}'}, 'v': {'.*': '.\{-}', '.+': '.\{-1,}'}}
let s:CNV.M = {'\.\*': '\.\{-}', '\.\+': '\.\{-1,}'}

"Misc:
function! s:_listify(record) "{{{
  return split(a:record, s:SEP)
endfunction
"}}}
function! s:_innerstrify(list) "{{{
  return join(a:list, s:SEP)
endfunction
"}}}
function! s:_is_invalid_fields(fields) "{{{
  return a:fields==[] || match(a:fields, '^\H\|\W')!=-1
endfunction
"}}}
function! s:_fmtmap_by_list(record, fieldidxs) "{{{
  let rec = s:_listify(a:record)
  return map(copy(a:fieldidxs), 'rec[(v:val)]')
endfunction
"}}}
function! s:_fmtmap_by_str(record, fieldsstr, fmt) "{{{
  exe 'let '. a:fieldsstr. ' = s:_listify(a:record)'
  return eval(a:fmt)
endfunction
"}}}
function! s:_inmap_rearrange(record, fieldidxs) "{{{
  let rec = s:_listify(a:record)
  return s:_innerstrify(map(a:fieldidxs, 'rec[(v:val)]'))
endfunction
"}}}
function! s:_inmap_chk_fmt(record, fieldidxs) "{{{
  let rec = s:_listify(a:record)
  return s:_innerstrify(map(copy(a:fieldidxs), 'v:val==-1 ? "" : rec[(v:val)]'))
endfunction
"}}}
function! s:_cnv_magicpat(str, m) "{{{
  let m = a:m
  let ret = m==0 ? [] : [s:_cnv_wildcard(a:str[:m-1], 'm')]
  let n = match(a:str, '\\[vmMV]', m+1)
  while n!=-1
    call add(ret, s:_cnv_wildcard(a:str[m : n-1]))
    let m = n
    let n = match(a:str, '\\[vmMV]', m+1)
  endwhile
  call add(ret, s:_cnv_wildcard(a:str[m :]))
  return join(ret, '')
endfunction
"}}}
function! s:_cnv_wildcard(str, ...) "{{{
  let c = a:0 ? a:1 : a:str[1]
  if c==#'m'
    return substitute(a:str, '\\\@<!\.\%(\*\|\\+\)', '\=s:CNV.m[submatch(0)]', 'g')
  elseif c==#'v'
    return substitute(a:str, '\\\@<!\.[*+]', '\=s:CNV.v[submatch(0)]', 'g')
  end
  return substitute(a:str, '\\.\%(\\\*\|\\+\)', '\=s:CNV.M[submatch(0)]', 'g')
endfunction
"}}}
function! s:_sub_4updatedict(sub) "{{{
  let s:_sub_i += 1
  return get(s:_sub_idx2dest, s:_sub_i, a:sub)
endfunction
"}}}

let s:Builder = {}
function! s:newBuilder(...) "{{{
  let obj = copy(s:Builder)
  let obj.fmts = a:000
  let obj.fmtlen = a:0
  let obj.fmttypes = map(copy(a:000), 'type(v:val)')
  return obj
endfunction
"}}}
function! s:Builder.activate(records, fields, fieldslen) "{{{
  let self.records = a:records
  let self.fieldidxs = map(copy(self.fmts), 'self.fmttypes[(v:key)]==s:TYPE_LIST ? s:_index_list(a:fields, v:val) : s:_index_str(a:fields, v:val)')
  let self.fieldslen = a:fieldslen
endfunction
"}}}
function! s:_index_str(fields, str) "{{{
  let idx = index(a:fields, a:str)
  if idx==-1
    throw printf('silo: invalid field name > "%s"', a:str)
  end
  return idx
endfunction
"}}}
function! s:_index_list(fields, list) "{{{
  let ret = map(copy(a:list), 'index(a:fields, v:val)')
  if index(ret, -1)!=-1
    throw 'silo: invalid fields > '. string(a:list)
  end
  return ret
endfunction
"}}}
function! s:Builder._get_fmt_of(idx) "{{{
  return [self.fieldidxs[a:idx], self.fmttypes[a:idx]]
endfunction
"}}}
function! s:Builder.is_overidx(fmtidx) "{{{
  return a:fmtidx >= self.fmtlen
endfunction
"}}}
function! s:Builder.build(fmtidx, records, len) "{{{
  let [fieldidx, type] = self._get_fmt_of(a:fmtidx)
  let childfmtidx = a:fmtidx+1
  if self.is_overidx(childfmtidx)
    return self['_termsamples_'.type](a:records, fieldidx)
  end
  let ret = []
  let len = a:len
  while len > 0
    let [refined, refinedlen, sample] = self._refine_for_child(fieldidx, a:records, type)
    let child = self.build(childfmtidx, refined, refinedlen)
    call add(ret, (type==s:TYPE_LIST ? add(sample, child) : [sample, child]))
    let len -= refinedlen
  endw
  return ret
endfunction
"}}}
function! s:Builder['_termsamples_'.s:TYPE_STR](records, fieldidx) "{{{
  let pat = s:_get_samplegetpat(a:fieldidx)
  let ret = map(a:records, 'matchstr(v:val, pat)')
  try
    let ret = __oreo#lim#misc#uniq(ret)
  catch /E117/
    echoerr 'silo.select_grouped(): select_grouped() depends misc-module but it is not found.'
  endtry
  return ret
endfunction
"}}}
function! s:Builder['_termsamples_'.s:TYPE_LIST](records, fieldidxs) "{{{
  let ret = map(a:records, 's:_inmap_buildterm(s:_listify(v:val), a:fieldidxs)')
  try
    let ret = __oreo#lim#misc#uniq(ret)
  catch /E117/
    echoerr 'silo-select_grouped: select_grouped() depends misc-module but it is not found.'
  endtry
  return ret
endfunction
"}}}
function! s:_inmap_buildterm(rec, fieldidxs) "{{{
  return map(copy(a:fieldidxs), 'a:rec[v:val]')
endfunction
"}}}
function! s:Builder._refine_for_child(fieldidx, records, type) "{{{
  let record = remove(a:records, 0)
  let [sample, pat] = self['_get_sample_and_pat_'.a:type](a:fieldidx, record)
  let refined = [record]
  let len = 1
  let i = match(a:records, pat)
  while i != -1
    call add(refined, remove(a:records, i))
    let len += 1
    let i = match(a:records, pat)
  endwhile
  return [refined, len, sample]
endfunction
"}}}
function! s:Builder['_get_sample_and_pat_'.s:TYPE_STR](fieldidx, record) "{{{
  let sample = matchstr(a:record, s:_get_samplegetpat(a:fieldidx))
  let pat = '^\%(.\{-}'. s:SEP. '\)\{'. a:fieldidx. '}'. sample. '\%('. s:SEP. '\|$\)'
  return [sample, pat]
endfunction
"}}}
function! s:Builder['_get_sample_and_pat_'.s:TYPE_LIST](fieldidxs, record) "{{{
  let sample = map(copy(a:fieldidxs), 'matchstr(a:record, s:_get_samplegetpat(v:val))')
  let pat = '^'
  let i = 0
  while i < self.fieldslen-1
    let idx = index(a:fieldidxs, i)
    let pat .= idx==-1 ? '\%(.\{-}\)'.s:SEP : sample[idx].s:SEP
    let i += 1
  endw
  let idx = index(a:fieldidxs, i)
  let pat .= idx==-1 ? '\%(.\{-}\)' : sample[idx]
  return [sample, pat]
endfunction
"}}}
function! s:_get_samplegetpat(fieldidx) "{{{
  return '^\%(.\{-}'. s:SEP. '\)\{'. a:fieldidx. '}\zs.\{-}\ze\%('. s:SEP. '\|$\)'
endfunction
"}}}


"=============================================================================
"Public:
let s:Silo = {}
function! __oreo#lim#silo#newSilo(name, fields, ...) abort "{{{
  let funcopt = a:0 ? a:1 : {}
  let obj = copy(s:Silo)
  let obj.key = get(funcopt, 'key', '')
  let obj.path = a:name=~'[/\\]' ? a:name : expand(g:__oreo#lim#silo#rootdir).'/'.a:name
  let obj.dir = fnamemodify(obj.path, ':h')
  if s:_is_invalid_fields(a:fields)
    echoerr '__oreo#lim#silo#newSilo(): invalid fields > '. string(a:fields)
  end
  let obj.fields = a:fields
  let obj.fieldslen = len(a:fields)
  let obj.records = filereadable(obj.path) ? readfile(obj.path) : []
  try
    let oldformat = s:_listify(remove(obj.records, 0))
    if obj._chk_version(oldformat)
      return {}
    end
  catch /E684:/
  endtry
  let obj.save_records = copy(obj.records)
  let obj.chgdtick = 0
  return obj
endfunction
"}}}
function! s:Silo._chk_version(oldformat) "{{{
  if a:oldformat ==# self.fields
    return
  end
  let missingidxs = []
  let i = len(a:oldformat)
  while i
    let i -= 1
    if index(self.fields, a:oldformat[i])==-1
      call add(missingidxs, i)
    end
  endwhile
  let fieldidxs = map(copy(self.fields), 'index(a:oldformat, v:val)')
  if missingidxs!=[]
    let i = len(missingidxs)
    while i
      let i -= 1
      let idx = missingidxs[i]
      if fieldidxs[idx] ==# -1
        let fieldidxs[idx] = idx
        unlet missingidxs[i]
      end
    endwhile
    if missingidxs!=[]
      echoerr 'silo: invalid field >' join(missings, ', ')
      return 1
    end
  end
  call map(self.records, 's:_inmap_chk_fmt(v:val, fieldidxs)')
endfunction
"}}}
function! s:Silo._get_refinepat_by_list(listwhere) "{{{
  if len(a:listwhere)!=self.fieldslen
    throw 'silo: invalid condition > '. string(a:listwhere)
  end
  return s:_innerstrify(a:listwhere)
endfunction
"}}}
function! s:Silo._get_refinepat_by_dict(dictwhere) "{{{
  let denial = {}
  let order = {}
  for [field, val] in items(a:dictwhere)
    let idx = field=~'^!' ? index(self.fields, field[1:]) : index(self.fields, field)
    if idx==-1
      echoerr 'silo: invalid field name >' field
    end
    if field=~'^!'
      let denial[idx] = type(val)!=s:TYPE_STR ? string(val) : val
    else
      let order[idx] = type(val)!=s:TYPE_STR ? string(val) : val
    end
  endfor
  let i = 0
  let pat = '^'
  let denialpat = ''
  let save_ignorecase = &ic
  set noic
  try
    while i < self.fieldslen
      if has_key(denial, i)
        let denialpat .= denialpat=='' ? '' : '\|'
        let denialpat .= '\m'.repeat('.\{-}'.s:SEP, i). denial[i]
      end
      let i += 1
    endwhile
    if denialpat!=''
      let pat = '^\%('. denialpat. '\)\@!\&'. pat
    end
    let i = 0
    while i < self.fieldslen-1
      if has_key(order, i)
        let m = match(order[i], '\\[vmMV]')
        let order[i] = m!=-1 ? s:_cnv_magicpat(order[i], m) : s:_cnv_wildcard(order[i], 'm')
      end
      let pat .= '\%('. get(order, i, '\m.\{-}'). '\)'. s:SEP
      let i += 1
    endwhile
    let pat .= '\%('. get(order, i, '\m.\{-}'). '\)'. '$'
  finally
    let &ic = save_ignorecase
  endtry
  return pat
endfunction
"}}}
function! s:Silo._get_fieldidxs(fmt) "{{{
  let fieldidxs = map(copy(a:fmt), 'index(self.fields, v:val)')
  if index(fieldidxs, -1)!=-1
    throw printf('silo: invalid format > "%s"', string(a:fmt))
  end
  return fieldidxs
endfunction
"}}}
function! s:Silo._fmt_by_list(records, listfmt) "{{{
  if a:listfmt==[]
    return map(a:records, 's:_listify(v:val)')
  end
  let fieldidxs = self._get_fieldidxs(a:listfmt)
  if len(a:listfmt)==1
    let idx = fieldidxs[0]
    return map(a:records, 's:_listify(v:val)[idx]')
  end
  return map(a:records, 's:_fmtmap_by_list(v:val, fieldidxs)')
endfunction
"}}}
function! s:Silo._fmt_by_str(records, strfmt) "{{{
  let idx = index(self.fields, a:strfmt)
  if idx==-1
    throw 'silo: invalid format > '. a:strfmt
  end
  return map(a:records, 's:_listify(v:val)[idx]')
endfunction
"}}}
function! s:Silo.is_changed() "{{{
  return self.chgdtick
endfunction
"}}}
function! s:Silo.has(where) "{{{
  let type = type(a:where)
  if type==s:TYPE_LIST
    try
      return index(self.records, self._get_refinepat_by_list(a:where))!=-1
    catch /silo: invalid condition/
      echoerr substitute(v:exception, 'silo', 'silo.has()', '')
    endtry
  elseif type==s:TYPE_DICT
    return match(self.records, self._get_refinepat_by_dict(a:where))!=-1
  end
  return match(self.records, a:where)!=-1
endfunction
"}}}
function! s:Silo._select(is_negative, where, fmt) "{{{
  let refineds = self._get_refineds(a:is_negative, a:where)
  let type = type(a:fmt)
  if type==s:TYPE_LIST
    return self._fmt_by_list(refineds, a:fmt)
  elseif type==s:TYPE_STR
    return self._fmt_by_str(refineds, a:fmt)
  end
  throw 'silo: invalid format > '. stirng(fmt)
endfunction
"}}}
function! s:Silo._get_refineds(is_negative, where) "{{{
  let sign = a:is_negative ? '!' : '='
  let type = type(a:where)
  if empty(a:where)
    return copy(self.records)
  elseif type==s:TYPE_LIST
    let pat = self._get_refinepat_by_list(a:where)
    return filter(copy(self.records), printf('v:val %s=# pat', sign))
  elseif type==s:TYPE_DICT
    let pat = self._get_refinepat_by_dict(a:where)
    return filter(copy(self.records), printf('v:val %s~# pat', sign))
  else
    return filter(copy(self.records), printf('v:val %s~# a:where', sign))
  end
endfunction
"}}}
function! s:Silo.select(where, ...) "{{{
  let fmt = a:0 ? a:1 : []
  try
    return self._select(0, a:where, fmt)
  catch /silo: invalid \%(condition\|format\)/
    echoerr substitute(v:exception, 'silo', 'silo.select', '')
  endtry
endfunction
"}}}
function! s:Silo.nselect(where, ...) "{{{
  let fmt = a:0 ? a:1 : []
  try
    return self._select(1, a:where, fmt)
  catch /silo: invalid \%(condition\|format\)/
    echoerr substitute(v:exception, 'silo', 'silo.nselect', '')
  endtry
  throw 'silo.nselect(): invalid format > '. stirng(fmt)
endfunction
"}}}
function! s:Silo.select_distinct(where, ...) "{{{
  let fmt = a:0 ? a:1 : []
  try
    let records = self._select(0, a:where, fmt)
    let ret = __oreo#lim#misc#uniq(records)
    return ret
  catch /silo: invalid \%(condition\|format\)/
    echoerr substitute(v:exception, 'silo', 'silo.select_distinct', '')
  catch /E117:/
    echoerr 'silo.select_distinct: select_distinct() depends misc-module but it is not found.'
    return records
  endtry
endfunction
"}}}
function! s:Silo.nselect_distinct(where, ...) "{{{
  let fmt = a:0 ? a:1 : []
  try
    let records = self._select(1, a:where, fmt)
    let ret = __oreo#lim#misc#uniq(records)
    return ret
  catch /silo: invalid \%(condition\|format\)/
    echoerr substitute(v:exception, 'silo', 'silo.select_distinct', '')
  catch /E117:/
    echoerr 'silo.select_distinct: select_distinct() depends misc-module but it is not found.'
    return records
  endtry
endfunction
"}}}
function! s:Silo.select_grouped(where, ...) "{{{
  let builder = call('s:newBuilder', a:000)
  try
    let refineds = self._get_refineds(0, a:where)
    let len = len(refineds)
    if len==0
      return []
    end
    call builder.activate(refineds, self.fields, self.fieldslen)
  catch /silo: invalid \%(field\|condition\)/
    echoerr substitute(v:exception, 'silo', 'silo.select_glouped()', '')
  endtry
  let idx = 0
  if builder.is_overidx(idx)
    return []
  end
  return builder.build(idx, refineds, len)
endfunction
"}}}
function! s:Silo.get(where, ...) "{{{
  let fmt = a:0 ? a:1 : []
  let type = type(a:where)
  if empty(a:where)
    let idx = self.records==[] ? -1 : 0
  elseif type==s:TYPE_LIST
    try
      let idx = index(self.records, self._get_refinepat_by_list(a:where))
    catch /silo: invalid condition/
      echoerr substitute(v:exception, 'silo', 'silo.get()', '')
    endtry
  elseif type==s:TYPE_DICT
    let idx = match(self.records, self._get_refinepat_by_dict(a:where))
  else
    let idx = match(self.records, a:where)
  end
  if type(fmt)==s:TYPE_LIST
    if fmt==[]
      return idx==-1 ? [] : s:_listify(self.records[idx])
    end
    try
      let fieldidxs = self._get_fieldidxs(fmt)
    catch /silo: invalid format/
      echoerr substitute(v:exception, 'silo', 'silo.get()', '')
    endtry
    return idx==-1 ? [] : s:_fmtmap_by_list(self.records[idx], fieldidxs)
  end
  let fieldidx = index(self.fields, fmt)
  if fieldidx==-1
    throw 'silo.get(): invalid format > '. fmt
  end
  return idx==-1 ? '' : s:_listify(self.records[idx])[fieldidx]
endfunction
"}}}
function! s:Silo.nextkey(...) "{{{
  let field = a:0 ? a:1 : self.key
  let self._save_nextkeys = get(self, '_save_chgdtick', -1) != self.chgdtick ? {} : self._save_nextkeys
  let self._save_chgdtick = self.chgdtick
  if has_key(self._save_nextkeys, field)
    let self._save_nextkeys[field] = self._save_nextkeys[field] +1
    return self._save_nextkeys[field]
  elseif field!=''
    let self._save_nextkeys[field] = max(self.select({}, [field])) +1
    return self._save_nextkeys[field]
  end
  unlet self._save_chgdtick
  echoerr 'silo-nextkey: keyfield is not defined.'
endfunction
"}}}
function! s:Silo.set_nextkey(...) "{{{
  if !a:0 || a:0==1 && self.key==''
    echoerr 'silo-set_nextkey: 引数の数が足りません'
  end
  let val = a:000[-1]
  let field = a:0>1 ? a:1 : self.key
  let self._save_nextkeys = get(self, '_save_chgdtick', -1) != self.chgdtick ? {} : self._save_nextkeys
  let self._save_nextkeys[field] = val-1
endfunction
"}}}
function! s:Silo.commit(...) "{{{
  if !self.is_changed()
    return 1
  end
  if !isdirectory(self.dir)
    call mkdir(self.dir, 'p')
  end
  let fields = [s:_innerstrify(self.fields)]
  call writefile(fields + self.records, self.path)
  if a:0
    let rollbackpath = a:1=~'[/\\]' ? a:1 : expand(g:__oreo#lim#silo#rootdir). '/backup/'. a:1
    call writefile(fields + self.save_records, rollbackpath)
  end
endfunction
"}}}
function! s:Silo.insert(rec, ...) "{{{
  if type(get(a:rec, 0, []))!=s:TYPE_LIST
    return self._insert(a:rec, a:000)
  end
  let ret = 0
  for rec in a:rec
    let ret = self._insert(rec, a:000) || ret
  endfor
  return ret
endfunction
"}}}
function! s:Silo.update(where, rec) "{{{
  try
    let targidxs = empty(a:where) ? range(self.fieldslen) : self._get_update_targidxs(a:where)
  catch /silo: invalid condition/
    echoerr substitute(v:exception, 'silo', 'silo.update', '')
  endtry
  let targlen = len(targidxs)
  if !targlen
    return -1
  end
  let rectype = type(a:rec)
  if rectype==s:TYPE_LIST
    return self._update_byreclist(a:rec, targlen, targidxs[0])
  elseif rectype==s:TYPE_DICT
    try
      call self._update_byrecdict(a:rec, targidxs)
    catch /silo: record is duplicated/
      echoerr substitute(v:exception, 'silo', 'silo.update', '')
      return 1
    catch /silo: invalid field/
      echoerr substitute(v:exception, 'silo', 'silo.update', '')
      return 2
    endtry
  end
endfunction
"}}}
function! s:Silo._delete(is_negative, where) "{{{
  let sign = a:is_negative ? '=' : '!'
  let wheretype = type(a:where)
  if empty(a:where)
    let self.records = a:is_negative ? self.records : []
  elseif wheretype==s:TYPE_LIST
    try
      let pat = self._get_refinepat_by_list(a:where)
    catch /silo: invalid condition/
      echoerr substitute(v:exception, 'silo', 'silo.delete()', '')
    endtry
    call filter(self.records, printf('v:val %s=# pat', sign))
  elseif wheretype==s:TYPE_DICT
    let pat = self._get_refinepat_by_dict(a:where)
    call filter(self.records, printf('v:val %s~# pat', sign))
  else
    call filter(self.records, printf('v:val %s~# a:where', sign))
  end
  let self.chgdtick += 1
  return self
endfunction
"}}}
function! s:Silo.delete(where) "{{{
  return self._delete(0, a:where)
endfunction
"}}}
function! s:Silo.ndelete(where) "{{{
  return self._delete(1, a:where)
endfunction
"}}}
function! s:Silo.sort(...) "{{{
  if a:0
    call sort(self.records, a:1)
  else
    call sort(self.records)
  end
  let self.chgdtick += 1
  return self
endfunction
"}}}
function! s:Silo.rearrange(destfields) abort "{{{
  if len(a:destfields) != self.fieldslen
    echoerr 'silo.rearrenge: invalid order > '. string(a:destfields)
  end
  try
    let fieldidxs = self._get_fieldidxs(a:destfields)
  catch 'silo: invalid format'
    echoerr substitute(v:exception, 'silo', 'silo.rearrange()', '')
  endtry
  call map(self.records, 's:_inmap_rearrange(v:val, fieldidxs)')
  let self.fields = a:destfields
  let self.chgdtick += 1
  return self
endfunction
"}}}
function! s:Silo._insert(rec, variadic) "{{{
  if self.has(a:rec)
    return 1
  end
  if len(a:rec)!=self.fieldslen
    echoh ErrorMsg | echom 'silo-insert : invalid insert >' a:rec | echoh NONE
    return 2
  end
  if a:variadic==[]
    call add(self.records, s:_innerstrify(a:rec))
  else
    call insert(self.records, s:_innerstrify(a:rec), a:variadic[0])
  end
  let self.chgdtick += 1
endfunction
"}}}
function! s:Silo._get_update_targidxs(where) "{{{
  let wheretype = type(a:where)
  let pat = wheretype==s:TYPE_LIST ? self._get_refinepat_by_list(a:where) : wheretype==s:TYPE_DICT ? self._get_refinepat_by_dict(a:where) : a:where
  let targidxs = []
  let idx = match(self.records, pat)
  while idx!=-1
    call add(targidxs, idx)
    let idx = match(self.records, pat, idx+1)
  endwhile
  return targidxs
endfunction
"}}}
function! s:Silo._update_byreclist(reclist, targlen, targidx) "{{{
  if a:targlen>1
    echoh ErrorMsg | echom 'silo-update: 条件が一意ではありません。' | echoh NONE
    return 2
  elseif len(a:reclist)!=self.fieldslen
    echoh ErrorMsg | echom 'silo-update : fields'' len is invalid >' a:reclist | echoh NONE
    return 2
  elseif self.has(a:reclist)
    echoh ErrorMsg | echom 'silo-update: 既に存在するレコードです。' | echoh NONE
    return 1
  end
  let self.records[a:targidx] = s:_innerstrify(a:reclist)
  let self.chgdtick += 1
endfunction
"}}}
function! s:Silo._update_byrecdict(recdict, targidxs) "{{{
  let PAT = '.\{-}\%('.s:SEP.'\|$\)'
  let s:_sub_idx2dest = self._fieldkeydict_to_idxkeydict(a:recdict)
  let records = copy(self.records)
  for idx in a:targidxs
    let s:_sub_i = -1
    let records[idx] = substitute(records[idx], PAT, '\=s:_sub_4updatedict(submatch(0))', 'g')
  endfor
  unlet s:_sub_i s:_sub_idx2dest
  let seens = {}
  for record in records
    let str = ':'. record
    if has_key(seens, str)
      throw 'silo: record is duplicated > '. record
    end
    let seens[str] = 1
  endfor
  let self.records = records
  let self.chgdtick += 1
endfunction
"}}}
function! s:Silo._fieldkeydict_to_idxkeydict(destdict) "{{{
  let ret = {}
  let lastidx = self.fieldslen-1
  for [field, dest] in items(a:destdict)
    let idx = index(self.fields, field)
    let ret[idx] = dest. (idx==lastidx ? '' : s:SEP)
  endfor
  if has_key(ret, '-1')
    throw 'silo: invalid field > '. ret['-1']
  end
  return ret
endfunction
"}}}


"=============================================================================
"END "{{{1
let &cpo = s:save_cpo| unlet s:save_cpo
