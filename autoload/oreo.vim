if exists('s:save_cpo')| finish| endif
let s:save_cpo = &cpo| set cpo&vim
scriptencoding utf-8
"=============================================================================
let s:MESON = '_l'
let s:UNKNOWN = ' '
let s:TYPE_LIST = type([])
let s:LOGLIMIT = 20
let s:LOGVERSION = 'v1'
let s:FIELDS = ['time', 'cmd', 'libname', 'reciname', 'reciroot', 'module']
function! s:import_vital()
  if !exists('s:File')
    let s:File = vital#of('oreo').import('System.File')
  end
endfunction

"Misc:
function! s:fetch_modules(dir) "{{{
  let paths = split(globpath(a:dir, '**/*.vim'), '\n')
  return map(paths, 'substitute(v:val, a:dir."/", "", "")')
endfunction
"}}}
function! s:get_libaldir(libname) "{{{
  return has_key(g:oreo#libs, a:libname) ? expand(g:oreo#libs[a:libname]).'/autoload' : ''
endfunction
"}}}
function! s:path_to_alname(module) "{{{
  return fnamemodify(a:module, ':r:gs?/?#?').'#'
endfunction
"}}}
function! s:invalidlib_warningmsg(libname) "{{{
  let mes = has_key(g:oreo#libs, a:libname) ? printf('"%s/autoload" path is not found.', g:oreo#libs[a:libname]) : printf('"%s" key is not found in g:oreo#libs.', a:libname)
  echoh WarningMsg| echom 'oreo.vim:' mes | echoh NONE
endfunction
"}}}
function! s:get_libnames() "{{{
  return keys(g:oreo#libs)
endfunction
"}}}
function! s:fetch_libs() "{{{
  let libs = {}
  for libname in s:get_libnames()
    let lib = s:newLib(libname)
    if lib.is_invalid
      call s:invalidlib_warningmsg(libname)
      continue
    end
    let libs[libname] = lib
  endfor
  return libs
endfunction
"}}}
function! s:fetch_attracted_libnames(reci) "{{{
  let libnames = []
  for libname in s:get_libnames()
    let lib = s:newLib(libname)
    if lib.is_invalid || a:reci.pick_hadmodules(lib.modules)==[]
      continue
    end
    call add(libnames, libname)
  endfor
  return libnames
endfunction
"}}}

function! s:fetch_libmodules(libname) "{{{
  return s:fetch_modules(s:get_libaldir(a:libname))
endfunction
"}}}
function! s:get_reqset_by_modules(reqmodules, reci, libs) "{{{
  call a:reci.pick_hadmodules(a:reqmodules)
  let reqset = {}
  for libname in s:get_libnames()
    let lib = a:libs[libname]
    let maybe_reqmodules = filter(copy(lib.modules), 'index(a:reqmodules, v:val)!=-1')
    if maybe_reqmodules!=[]
      let reqset[libname] = maybe_reqmodules
    end
  endfor
  return reqset
endfunction
"}}}
function! s:get_updatecmps(reqset, reci, libs) "{{{
  let cmps = []
  for [libname, reqmodules] in items(a:reqset)
    if libname==s:UNKNOWN
      continue
    end
    let lib = a:libs[libname]
    let reqmodules = lib.filter_reqmodules(reqmodules)
    call a:reci.pick_hadmodules(reqmodules)
    if reqmodules==[]
      continue
    end
    let cmp = s:newCmp(lib, a:reci, reqmodules)
    call add(cmps, cmp)
  endfor
  return cmps
endfunction
"}}}
function! s:get_updatecmps_with_libs(reqset, reci, libs) "{{{
  let cmps = []
  for [libname, reqmodules] in items(a:reqset)
    let lib = a:libs[libname]
    let cmp = s:newCmp(lib, a:reci, reqmodules)
    call add(cmps, cmp)
  endfor
  return cmps
endfunction
"}}}
function! s:expand_reciroot(reciroot) "{{{
  let reciroot = fnamemodify(substitute(a:reciroot, '^\%(\.\|[%#]\%(\%(:[hp8~.tre]\|:g\?s?.\{-}?.\{-}?\)\)*\)\ze\%([/\\]\|$\)', '\=submatch(0)=="." ? getcwd() : expand(submatch(0))', ''), ':p:h')
  while reciroot=~'/\.\.\%(/\|$\)'
    let reciroot = substitute(reciroot, '/.\{-1,}/\.\.', '', '')
    let reciroot = reciroot=='' ? '/' : reciroot
  endwhile
  return reciroot
endfunction
"}}}

let s:Reci = {}
function! s:newReci(reciroot, reciname) "{{{
  let obj = copy(s:Reci)
  let a = a:reciroot==''
  let b = a:reciname==''
  let [reciroot, reciname] = ['', '']
  if a || b
    let [reciroot, reciname] = s:_infer_reciroot_and_pluginname(a ? expand('%:p:h') : a:reciroot)
  end
  let obj.root = a ? reciroot : s:expand_reciroot(a:reciroot)
  let maybename = globpath(obj.root, 'autoload/*/l/')
  let obj.name = maybename!='' ? matchstr(maybename, 'autoload/\zs.\{-1,}\ze/') : b ? reciname : a:reciname
  let obj.is_invalid = obj.root=='' || obj.name==''
  if obj.is_invalid
    return obj
  end
  let obj._namedir = printf('%s/autoload/%s', obj.root, obj.name)
  let obj.dir = obj._namedir. s:MESON
  let obj.modules = s:fetch_modules(obj.dir)
  return obj
endfunction
"}}}
function! s:_infer_reciroot_and_pluginname(path) "{{{
  let inference = oreo_l#lim#misc#infer_plugin_pathinfo(a:path)
  if inference=={}
    return ['', '']
  end
  return [inference.root, inference.name]
endfunction
"}}}
function! s:Reci.mill_hadmodules(libmodules) "{{{
  return filter(a:libmodules, 'index(self.modules, v:val)==-1')
endfunction
"}}}
function! s:Reci.pick_hadmodules(modules) "{{{
  return filter(a:modules, 'index(self.modules, v:val)!=-1')
endfunction
"}}}
function! s:Reci.get_lines(module) "{{{
  return readfile(self.dir. '/'. a:module)
endfunction
"}}}
function! s:Reci.write_and_source(module, lines) "{{{
  let path = self.dir. '/'. a:module
  if !isdirectory(fnamemodify(path, ':h'))
    call mkdir(fnamemodify(path, ':h'), 'p')
  end
  call writefile(a:lines, path)
  exe 'source' path
endfunction
"}}}
function! s:Reci.delete(module) "{{{
  let path = self.dir. '/'. a:module
  call delete(path)
endfunction
"}}}
function! s:Reci.remove_emptydir() "{{{
  let dirs = map(split(globpath(self._namedir, '**/'), '\n'), 'substitute(v:val, "/$", "", "")')
  let files = filter(split(globpath(self._namedir, '**/*'), '\n'), 'index(dirs, v:val)==-1')
  if files==[]
    call s:import_vital()
    try
      call s:File.rmdir(self._namedir, 'r')
    catch
      echoh ErrorMsg | echom 'oreo: the following directory could not be deleted. >' self._namedir | echoh NONE
    endtry
    return
  end
  for dir in dirs
    if match(files, '^'.dir.'/')!=-1 || !isdirectory(dir)
      continue
    end
    call s:import_vital()
    try
      call s:File.rmdir(dir, 'r')
    catch
      echoh ErrorMsg | echom 'oreo: the following directory could not be deleted. >' dir | echoh NONE
    endtry
  endfor
endfunction
"}}}

let s:Lib = {}
function! s:newLib(libname) "{{{
  let libaldir = s:get_libaldir(a:libname)
  let obj = copy(s:Lib)
  let obj.is_invalid = !isdirectory(libaldir)
  if obj.is_invalid
    return obj
  end
  let obj.name = a:libname
  let obj.aldir = libaldir
  let obj.modules = s:fetch_modules(libaldir)
  return obj
endfunction
"}}}
function! s:Lib.filter_reqmodules(reqmodules) "{{{
  if a:reqmodules==[]
    return copy(self.modules)
  end
  let ret = []
  for reqmodule in a:reqmodules
    if index(self.modules, reqmodule)==-1
      echoh WarningMsg| echo printf('"%s" module is not exist in library <%s>', reqmodule, self.name)| echoh NONE
    else
      call add(ret, reqmodule)
    end
  endfor
  return ret
endfunction
"}}}
function! s:Lib._get_libalnames_pat() "{{{
  if has_key(self, 'libalnames_pat')
    return self.libalnames_pat
  end
  let self.libalnames_pat = '\<\%('. join(map(copy(self.modules), 's:path_to_alname(v:val)'), '\|'). '\)'
  return self.libalnames_pat
endfunction
"}}}
function! s:Lib.get_recifyline(module, reciname) "{{{
  let libalnames_pat = self._get_libalnames_pat()
  let sub = a:reciname. s:MESON. '#\0'
  return map(readfile(self.aldir.'/'.a:module), 'substitute(v:val, libalnames_pat, sub, "g")')
endfunction
"}}}

let s:Cmp = {}
function! s:newCmp(lib, reci, reqmodules) "{{{
  let obj = copy(s:Cmp)
  let obj._reqmodules = a:reqmodules
  let obj.lib = a:lib
  let obj.reci = a:reci
  let obj._attracted_modules = a:reci.pick_hadmodules(copy(a:lib.modules))
  let librecifylines = {}
  let recilines = {}
  let not_equals = {}
  let [obj._librecifylines, obj._recilines, obj._not_equals] = [librecifylines, recilines, not_equals]
  for module in obj._attracted_modules
    let librecifylines[module] = a:lib.get_recifyline(module, a:reci.name)
    let recilines[module] = a:reci.get_lines(module)
    let not_equals[module] = librecifylines[module] !=# recilines[module]
  endfor
  return obj
endfunction
"}}}
function! s:Cmp._echo_header() "{{{
  echoh NONE
  echo 'library '
  echoh OreoLib
  echon printf('<%s>', self.lib.name)
  echoh NONE
  echon " in "
  echoh OreoReci
  echon printf('"%s"', self.reci.name)
  echoh OreoQuiet
  echon printf(' (%s)', self.reci.root)
endfunction
"}}}
function! s:Cmp.show_status() "{{{
  call self._echo_header()
  for module in self._attracted_modules + filter(copy(self._reqmodules), 'index(self._attracted_modules, v:val)==-1')
    if !has_key(self._not_equals, module)
      echoh OreoAdd | echo ' + Add      '| echoh OreoBold
    elseif self._not_equals[module]
      if index(self._reqmodules, module)==-1
        echoh OreoNotEqual | echo ' !          '| echoh NONE
      else
        echoh OreoUpdate | echo ' ! Update   '| echoh OreoBold
      end
    else
      echoh NONE | echo '            '| echoh NONE
    end
    echon module
  endfor
  echoh NONE
endfunction
"}}}
function! s:Cmp.show_deletestatus() "{{{
  call self._echo_header()
  for module in self._attracted_modules + filter(copy(self._reqmodules), 'index(self._attracted_modules, v:val)==-1')
    if !has_key(self._not_equals, module)
      echoh OreoQuiet | echo ' ?          '| echoh OreoBold
    elseif index(self._reqmodules, module)!=-1
      echoh OreoDelete | echo (self._not_equals[module] ? ' !' : ' -'). ' Delete   '| echoh OreoBold
    elseif self._not_equals[module]
      echoh OreoNotEqual | echo ' !          '| echoh NONE
    else
      echoh NONE | echo '            '| echoh NONE
    end
    echon module
  endfor
  echoh NONE
endfunction
"}}}
function! s:Cmp.show_ststatus() "{{{
  call self._echo_header()
  "for module in self._attracted_modules + self.reci.mill_hadmodules(copy(self.lib.modules))
  for module in self.reci.modules
    if !has_key(self._not_equals, module)
      echoh OreoQuiet | echo ' -          '
    elseif self._not_equals[module]
      echoh OreoNotEqual | echo ' !          '| echoh NONE
    else
      echoh NONE | echo '            '| echoh NONE
    end
    echon module
  endfor
  echoh NONE
endfunction
"}}}
function! s:Cmp.attract() "{{{
  let self._donemodules = self._reqmodules
  if self._donemodules==[]
    return
  end
  for module in self._donemodules
    call self.reci.write_and_source(module, has_key(self._librecifylines, module) ? self._librecifylines[module] : self.lib.get_recifyline(module, self.reci.name))
  endfor
  call self._echo_header()
  for module in self._donemodules
    echoh OreoAdd | echo ' + Added    '| echoh OreoBold
    echon module
  endfor
  echoh NONE
endfunction
"}}}
function! s:Cmp.extract() "{{{
  let self._donemodules = self._reqmodules
  if self._donemodules==[]
    return
  end
  for module in self._donemodules
    call self.reci.delete(module)
  endfor
  call self.reci.remove_emptydir()
  call self._echo_header()
  for module in self._donemodules
    echoh OreoDelete | echo ' - Deleted  '| echoh OreoBold
    echon module
  endfor
  echoh NONE
endfunction
"}}}
function! s:Cmp.update() "{{{
  let self._donemodules = filter(copy(self._reqmodules), 'self._not_equals[v:val]')
  if self._donemodules==[]
    return
  end
  for module in self._donemodules
    call self.reci.write_and_source(module, self._librecifylines[module])
  endfor
  call self._echo_header()
  for module in self._donemodules
    echoh OreoUpdate | echo ' + Updated  '| echoh OreoBold
    echon module
  endfor
  echoh NONE
endfunction
"}}}
function! s:Cmp.log(log) "{{{
  call a:log.register(self.lib.name, self._donemodules)
  for module in self._donemodules
    if has_key(self._recilines, module)
      call a:log.backup(self._recilines[module], module)
    end
  endfor
endfunction
"}}}

let s:Unknowns = {}
function! s:newUnknowns(reci, libs, ...) "{{{
  let obj = copy(s:Unknowns)
  let obj.reci = a:reci
  let modules = copy(a:reci.modules)
  for libname in s:get_libnames()
    let libmodules = a:libs[libname].modules
    call filter(modules, 'index(libmodules, v:val)==-1')
  endfor
  let obj.modules = modules
  let obj._reqmodules = !a:0 ? [] : a:1==[] ? modules : a:1
  call filter(obj._reqmodules, 'index(modules, v:val)!=-1')
  let obj.isreq = obj._reqmodules!=[]
  let obj._recilines = {}
  for module in obj._reqmodules
    let obj._recilines[module] = a:reci.get_lines(module)
  endfor
  return obj
endfunction
"}}}
function! s:Unknowns._echo_header() "{{{
  echoh OreoLib
  echo 'unknown modules'
  echoh NONE
  echon " in "
  echoh OreoReci
  echon printf('"%s"', self.reci.name)
  echoh OreoQuiet
  echon printf(' (%s)', self.reci.root)
endfunction
"}}}
function! s:Unknowns.show_status() "{{{
  if self.modules==[]
    return
  end
  call self._echo_header()
  for module in self.modules
    echoh OreoQuiet
    echo ' ?          '
    echoh ErrorMsg
    echon module
  endfor
  echoh NONE
endfunction
"}}}
function! s:Unknowns.show_deletestatus() "{{{
  if self.modules==[]
    return
  end
  call self._echo_header()
  for module in self.modules
    if index(self._reqmodules, module)==-1
      echoh OreoQuiet | echo ' ?          '
    else
      echoh OreoDelete | echo ' ? Delete   '
    end
    echoh ErrorMsg
    echon module
  endfor
  echoh NONE
endfunction
"}}}
let s:Unknowns.extract = s:Cmp.extract
function! s:Unknowns.log(log) "{{{
  if !self.isreq
    return
  end
  call a:log.register(s:UNKNOWN, self._donemodules)
  for module in self._donemodules
    call a:log.backup(self._recilines[module], module)
  endfor
endfunction
"}}}

let s:Log = {}
function! s:newLog(...) "{{{
  let obj = copy(s:Log)
  let dir = expand(g:oreo#config_dir)
  let obj._silo = oreo_l#lim#silo#newSilo(dir.'/log.silo', s:FIELDS)
  let obj.entriespath = dir.'/entries'
  let obj.entries = filereadable(obj.entriespath) ? readfile(obj.entriespath) : [s:LOGVERSION]
  let obj.version = remove(obj.entries, 0)
  if obj.version != s:LOGVERSION
    "TODO
  end
  let obj.reci = a:0 ? a:1 : ''
  if a:0==2
    let obj.cmd = a:2
    call obj._prepare_insert(dir.'/backup')
  end
  return obj
endfunction
"}}}
function! s:Log._prepare_insert(backuproot) "{{{
  let self.time = strftime('%Y-%m-%d-%H:%M:%S')
  call insert(self.entries, self.time)
  let self.backupdir = printf('%s/%s_%s', a:backuproot, tr(self.time, ':', ';'), self.cmd)
  if len(self.entries)<=s:LOGLIMIT
    return
  end
  let self.entries = self.entries[: s:LOGLIMIT-1]
  call self._silo.ndelete({'time': join(self.entries, '\|')})
  let backupdirs = split(globpath(a:backuproot, '*/'), "\n")
  for dir in filter(backupdirs, 'index(self.entries, fnamemodify(v:val, ":h:t:gs?;?:?:s?_.\\+$??"))==-1')
    call s:import_vital()
    try
      call s:File.rmdir(dir, 'r')
    catch
      echoh ErrorMsg | echom 'oreo: the following directory could not be deleted. >' dir | echoh NONE
    endtry
  endfor
endfunction
"}}}
function! s:Log.register(libname, modules) "{{{
  for module in a:modules
    call self._silo.insert([self.time, self.cmd, a:libname, self.reci.name, self.reci.root, module])
  endfor
endfunction
"}}}
function! s:Log.backup(lines, module) "{{{
  let path = printf('%s/%s/%s', self.backupdir, self.reci.name, a:module)
  if !isdirectory(fnamemodify(path, ':h'))
    call mkdir(fnamemodify(path, ':h'), 'p')
  end
  call writefile(a:lines, path)
endfunction
"}}}
function! s:Log.commit() "{{{
  call self._silo.commit()
  call writefile(insert(self.entries, self.version), self.entriespath)
endfunction
"}}}
function! s:Log.show() "{{{
  let SIGNS = {'Attract': '+', 'Extract': '-', 'Update': '!'}
  let records = self._silo.select_grouped({}, ['time', 'cmd', 'reciname', 'reciroot'], 'libname', 'module')
  for [time, cmd, reciname, reciroot, recs] in reverse(records)[:7]
    echoh OreoBold
    echo printf('%s  %s  ', time, cmd)
    echoh OreoReci
    echon printf('"%s"', reciname)
    echoh OreoQuiet
    echon printf(' (%s)', reciroot)
    for [libname, modules] in recs
      echoh OreoLib
      echo printf('%8s<%s>', '', libname==' ' ? '?' : libname)
      echoh NONE
      for module in modules
        echo printf(' %8s %s', get(SIGNS, cmd, ''), module)
      endfor
    endfor
  endfor
  echoh NONE
endfunction
"}}}


"======================================
"Public:
function! oreo#lock() "{{{
  setl ro nobl
  echoh WarningMsg
  echo 'oreo: this file is not original file.'
  echoh NONE
endfunction
"}}}
"--------------------------------------
function! oreo#cmpl_attract(arglead, cmdline, curpos) "{{{
  let cmpl = oreo_l#lim#cmddef#newCmdcmpl(a:cmdline, a:curpos)
  let reciroot = cmpl.get('^\%(--root\|-r\)=\zs.*')
  if cmpl.should_optcmpl()
    if reciroot==''
      let reciroot = get(oreo_l#lim#misc#infer_plugin_pathinfo(expand('%:p')), 'root', '')
    end
    let maybename = globpath(reciroot, 'autoload/*/l/')
    if maybename==''
      return cmpl.filtered([['--root=', '-r='], ['--name=', '-n='], ['--verpersonalize', '-v']])
    else
      return cmpl.filtered([['--root=', '-r='], ['--verpersonalize', '-v']])
    end
  end
  let libnames = s:get_libnames()
  if cmpl.count_lefts() == 0
    return cmpl.filtered(libnames)
  end
  let reciname = cmpl.get('^\%(--name\|-n\)=\zs.*')
  let reci = s:newReci(reciroot, reciname)
  if reci.is_invalid
    return
  end
  let libname = substitute(cmpl.get_left(libnames, -1), ':\+$', '', '')
  return libname=='' ? [] : cmpl.filtered(reci.mill_hadmodules(s:fetch_libmodules(libname)))
endfunction
"}}}
function! oreo#cmpl_extract(arglead, cmdline, curpos) "{{{
  let cmpl = oreo_l#lim#cmddef#newCmdcmpl(a:cmdline, a:curpos)
  if cmpl.should_optcmpl()
    return cmpl.filtered([['--lib', '-l'], ['--root=', '-r=']])
  end
  let reciroot = cmpl.get('^\%(--root\|-r\)=\zs.*')
  let reci = s:newReci(reciroot, '')
  if reci.is_invalid
    return []
  end
  if cmpl.get('^-l\|^--lib')==''
    return cmpl.filtered(reci.modules)
  end
  return cmpl.filtered(s:fetch_attracted_libnames(reci))
endfunction
"}}}
function! oreo#cmpl_update(arglead, cmdline, curpos) "{{{
  let cmpl = oreo_l#lim#cmddef#newCmdcmpl(a:cmdline, a:curpos)
  if cmpl.should_optcmpl()
    return cmpl.filtered([['--lib', '-l'], ['--root=', '-r='], ['--verpersonalize', '-v']])
  end
  let reciroot = cmpl.get('^\%(--root\|-r\)=\zs.*')
  let reci = s:newReci(reciroot, '')
  if reci.is_invalid
    return []
  end
  if cmpl.get('^-l\|^--lib')==''
    return cmpl.filtered(reci.modules)
  end
  return cmpl.filtered(s:fetch_attracted_libnames(reci))
endfunction
"}}}
function! oreo#cmpl_libs(arglead, cmdline, curpos) "{{{
  let beens = split(a:cmdline)[1:]
  return filter(s:get_libnames(), 'v:val=~"^".a:arglead && index(beens, v:val)==-1')
endfunction
"}}}
function! oreo#cmpl_diff(arglead, cmdline, curpos) "{{{
  let cmpl = oreo_l#lim#cmddef#newCmdcmpl(a:cmdline, a:curpos)
  if cmpl.should_optcmpl()
    return cmpl.filtered([['--root=', '-r=']])
  end
  let reciroot = cmpl.get('^\%(--root\|-r\)=\zs.*')
  let reci = s:newReci(reciroot, '')
  if reci.is_invalid || cmpl.count_lefts()>=1
    return []
  end
  return cmpl.filtered(reci.modules)
endfunction
"}}}

"======================================
"Enter:
function! oreo#enter_attract(args) "{{{
  if a:args!=[]
    let a:args[-1] = substitute(a:args[-1], '\s\+$', '', '')
  end
  let parser = oreo_l#lim#cmddef#newCmdParser(a:args)
  let opts = parser.parse_options({'reciroot': [['--root', '-r'], ''], 'reciname': [['--name', '-n'], ''], 'verpersonalize': [['--verpersonalize', '-v'], 0]})
  let reci = s:newReci(opts.reciroot, opts.reciname)
  if reci.is_invalid
    return
  elseif parser.args==[]
    call oreo#status(s:fetch_attracted_libnames(reci), reci)
  else
    let libname = remove(parser.args, 0)
    call oreo#attract({libname : a:args}, reci)
  end
endfunction
"}}}
function! oreo#enter_extract(args) "{{{
  let [reqset, reci] = s:_common_enter_update(a:args, {'is_libname': [['--lib', '-l'], 0], 'reciroot': [['--root', '-r'], '']})
  call oreo#extract(reqset, reci)
endfunction
"}}}
function! oreo#enter_update(args) "{{{
  let [reqset, reci] = s:_common_enter_update(a:args, {'is_libname': [['--lib', '-l'], 0], 'reciroot': [['--root', '-r'], '']})
  call oreo#update(reqset, reci)
endfunction
"}}}
function! s:_common_enter_update(args, optdict) "{{{
  if a:args!=[]
    let a:args[-1] = substitute(a:args[-1], '\s\+$', '', '')
  end
  let parser = oreo_l#lim#cmddef#newCmdParser(a:args)
  let opts = parser.parse_options(a:optdict)
  let reci = s:newReci(opts.reciroot, '')
  if reci.is_invalid
    return
  end
  if parser.args==[]
    let reqset = eval('{"'.join(s:get_libnames(), '": [], "').'": [], s:UNKNOWN : []}')
  elseif opts.is_libname
    let reqset = eval('{"'.join(parser.args, '": [], "').'": []}')
  else
    let reqset = parser.args
  end
  return [reqset, reci]
endfunction
"}}}
function! oreo#enter_status(args) "{{{
  if a:args!=[]
    let a:args[-1] = substitute(a:args[-1], '\s\+$', '', '')
  end
  let parser = oreo_l#lim#cmddef#newCmdParser(a:args)
  let opts = parser.parse_options({'reciroot': [['--root', '-r'], '']})
  let reci = s:newReci(opts.reciroot, '')
  if reci.is_invalid
    return
  end
  let libnames = parser.args==[] ? s:fetch_attracted_libnames(reci) : parser.args
  call oreo#status(libnames, reci)
endfunction
"}}}
function! oreo#enter_diff(args) "{{{
  if a:args!=[]
    let a:args[-1] = substitute(a:args[-1], '\s\+$', '', '')
  end
  let parser = oreo_l#lim#cmddef#newCmdParser(a:args)
  let opts = parser.parse_options({'reciroot': [['--root', '-r'], '']})
  let reci = s:newReci(opts.reciroot, '')
  if reci.is_invalid
    return
  end
  call reci.pick_hadmodules(parser.args)
  if parser.args==[]
    return
  end
  call oreo#diff(parser.args[0], reci)
endfunction
"}}}

"Main:
function! oreo#attract(reqset, reci) "{{{
  let libs = s:fetch_libs()
  let cmps = []
  for [libname, reqmodules] in items(a:reqset)
    let lib = libs[libname]
    let reqmodules = lib.filter_reqmodules(reqmodules)
    call a:reci.mill_hadmodules(reqmodules)
    if reqmodules==[]
      continue
    end
    let cmp = s:newCmp(lib, a:reci, reqmodules)
    call add(cmps, cmp)
  endfor
  for cmp in cmps
    call cmp.show_status()
  endfor
  if cmps==[]
    return
  end
  let unknowns = s:newUnknowns(a:reci, libs)
  call unknowns.show_status()
  if input('Attract: execute it? [n/y] ')!=?'y'
    redraw | echo ''
    return
  end
  redraw
  for cmp in cmps
    call cmp.attract()
  endfor
  let log = s:newLog(a:reci, 'Attract')
  for cmp in cmps
    call cmp.log(log)
  endfor
  call log.commit()
endfunction
"}}}
function! oreo#extract(req, reci) "{{{
  let libs = s:fetch_libs()
  if type(a:req)==s:TYPE_LIST
    let reqset = s:get_reqset_by_modules(a:req, a:reci, libs)
    let cmps = s:get_updatecmps_with_libs(reqset, a:reci, libs)
    let unknowns = s:newUnknowns(a:reci, libs, a:req)
  else
    let cmps = s:get_updatecmps(a:req, a:reci, libs)
    let unknowns = call('s:newUnknowns', has_key(a:req, s:UNKNOWN) ? [a:reci, libs, a:req[s:UNKNOWN]] : [a:reci, libs])
  end
  if cmps==[] && !unknowns.isreq
    return
  end
  for cmp in cmps
    call cmp.show_deletestatus()
  endfor
  call unknowns.show_deletestatus()
  if input('Extract: execute it? [n/y] ')!=?'y'
    redraw | echo ''
    return
  end
  redraw
  for cmp in cmps
    call cmp.extract()
  endfor
  if unknowns.isreq
    call unknowns.extract()
  end
  let log = s:newLog(a:reci, 'Extract')
  for cmp in cmps
    call cmp.log(log)
  endfor
  call unknowns.log(log)
  call log.commit()
endfunction
"}}}
function! oreo#update(req, reci) "{{{
  let libs = s:fetch_libs()
  if type(a:req)==s:TYPE_LIST
    let reqset = s:get_reqset_by_modules(a:req, a:reci, libs)
    let cmps = s:get_updatecmps_with_libs(reqset, a:reci, libs)
  else
    let cmps = s:get_updatecmps(a:req, a:reci, libs)
  end
  for cmp in cmps
    call cmp.show_status()
  endfor
  if cmps==[]
    return
  end
  let unknowns = s:newUnknowns(a:reci, libs)
  call unknowns.show_status()
  if input('Update: execute it? [n/y] ')!=?'y'
    redraw | echo ''
    return
  end
  redraw
  for cmp in cmps
    call cmp.update()
  endfor
  let log = s:newLog(a:reci, 'Update')
  for cmp in cmps
    call cmp.log(log)
  endfor
  call log.commit()
endfunction
"}}}
function! oreo#status(libnames, reci) "{{{
  let libs = s:fetch_libs()
  let cmps = []
  for libname in a:libnames
    let lib = libs[libname]
    let cmp = s:newCmp(lib, a:reci, [])
    call add(cmps, cmp)
  endfor
  for cmp in cmps
    call cmp.show_status()
  endfor
  call s:newUnknowns(a:reci, libs).show_status()
endfunction
"}}}
function! oreo#log() "{{{
  let log = s:newLog()
  call log.show()
endfunction
"}}}
function! oreo#diff(module, reci) "{{{
  if !has('diff')
    echoh WarningMsg | echo 'diff feature is disable.' | echoh NONE
    return
  end
  let libs = s:fetch_libs()
  let idx = -1
  for libname in s:get_libnames()
    let lib = libs[libname]
    let idx = index(lib.modules, a:module)
    if idx!=-1
      break
    end
  endfor
  if idx==-1
    echoh WarningMsg | echo printf('"%s" module is not found in libraries.', a:module) | echoh NONE
    return
  end
  silent exe 'tabedit' printf('%s/%s', a:reci.dir, a:module)
  exe (g:oreo#is_verticaldiff ? 'vertical' : '') 'new +set\ bt=nofile\ nobl\ ft=vim ORIGINAL_MODULE'
  silent %d _
  call setline(1, lib.get_recifyline(a:module, a:reci.name))
  diffthis
  silent wincmd p
  diffthis
endfunction
"}}}

"=============================================================================
"END "{{{1
let &cpo = s:save_cpo| unlet s:save_cpo
