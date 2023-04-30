vim9script noclear

# Vim global plugin to enhance recovering files, showing diffs and deleting 
# backups.
# Last change: 2023 Apr 14
# Maintainer: Xavier Nicollet <xnicollet@gmail.com>
# License: tbd

if exists("g:loaded_myrecover")
  finish
endif
g:loaded_typecorrect = 1

def Recover(on: bool)
    if !on
      augroup Swap
        autocmd!
      augroup end
      return
    endif
    augroup Swap
      autocmd!
      au SwapExists * :call ConfirmSwapDiff()
    augroup end
enddef

def EqualsSwap(): bool
  var current = expand('%:p')
  var t = tempname()
  try
    exe 'recover' fnameescape(current)
  catch /^Vim\%((\a\+)\)\=:E/
  # Prevent any recovery error from disrupting the diff-split.
  endtry
  exe ':silent w' t
  system('cmp ' .. shellescape(current, 1) .. ' ' .. shellescape(t, 1))
  delete(t)
  return v:shell_error == 0
enddef

def DiffRecoveredFile()
  diffthis
  noa vert new
  set bt=nofile
  if !empty(glob(fnameescape(expand('#'))))
    execute ":0r" fnameescape(expand('#'))
    execute ":$d _"
  endif
  exe 'file!' escape(expand('<afile>'), ' ') escape('(on-disk)', ' ')
  diffthis
  setl noswapfile buftype=nowrite bufhidden=delete nobuflisted
  var swapbufnr = bufnr('')
  wincmd p
  b:swapbufnr = swapbufnr
  setl modified # because we're in BufReadPost
enddef

def CheckRecover()
  if !exists("b:swapname") || exists("b:did_recovery")
    return
  endif
  if EqualsSwap()
    echomsg "No differences with swapfile, deleting: '" .. b:swapname .. "'."
    v:swapchoice = ''
    delete(b:swapname)
    # can trigger SwapExists autocommands again!
    SetSwapFile()
    SwapBufferReadPost(false)
    return
  endif
  SwapBufferReadPost(false)
  DiffRecoveredFile()
  command! -buffer FinishRecovery :call RecoverFinish()
  b:did_recovery = 1
enddef

def RecoverFinish()
  var swapname = b:swapname
  var curbufnr = bufnr('')
  delcommand FinishRecovery
  exe ":" .. bufwinnr(b:swapbufnr) " wincmd w"
  diffoff
  bd!
  delete(swapname)
  SwapBufferReadPost(false)
  exe ":" .. bufwinnr(curbufnr) " wincmd w"
  diffoff
  SetSwapFile()
  unlet! b:swapname b:did_recovery b:swapbufnr b:swapchoice
enddef

def SwapBufferReadPost(on: bool)
  if on && !exists("#SwapBufferReadPost")
    augroup SwapBufferReadPost
      au! BufNewFile,BufReadPost <buffer> :call s:CheckRecover()
    augroup END
  elseif !on && exists('#SwapBufferReadPost')
    augroup SwapBufferReadPost
      au!
    augroup END
    augroup! SwapBufferReadPost
  endif
enddef

def EchoMsg(msg: string)
  echohl WarningMsg
  unsilent echomsg msg
  echohl None
enddef

def SetSwapFile()
  if &l:swf || empty(bufname(''))
    return
  endif
  silent setl noswapfile swapfile
enddef

def ConfirmSwapDiff()
  var bufname = shellescape(expand('%'))
  var vim = v:progpath
  inputsave()
  var swapfile = fnamemodify(v:swapname, ":p")
  var p = confirm(
    "Swap '" .. swapfile .. "' found: ",
    "&Compare\n&Open RO\n&Edit anyway\n&Recover\n&Quit\n&Abort\n&Delete",
    1, "Info",
  )
  inputrestore()
  var choices = {
    1: 'Compare',
    2: 'OpenRO',
    3: 'Edit',
    4: 'Recover',
    5: 'Quit',
    6: 'Abort',
    7: 'Delete',
  }
  if !has_key(choices, p)
    echoerr "wrong choice: " .. p
    return
  endif
  var choice = choices[p]
  b:swapname = v:swapname
  var direct = { 'Recover': 'r', 'Quit': 'q', 'Abort': 'a', }
  if choice == 'Compare' || choice == 'Edit' # Diff or Edit anyway
    v:swapchoice = "e"
    b:swapchoice = "e"
    # Postpone recovering until later (CheckRecover, called from BufReadPos
    # autocommand).
    if choice == 'Compare'
      SwapBufferReadPost(true)
    endif
  elseif choice == 'OpenRO'
    # Don't show the Recovery dialog
    v:swapchoice = 'o'
    # EchoMsg("Found SwapFile, opening file readonly!")
  elseif has_key(direct, choice)
    v:swapchoice = direct[choice]
  elseif choice == 'Delete'
    EchoMsg("Found SwapFile, deleting...")
    # might triger SwapExists again!
    SetSwapFile()
  else
    # Show default menu from vim
    return
  endif
enddef

call Recover(true)

def TestVert()
  noa vert new
enddef

command! RecoverEnable :call Recover(true)
command! RecoverDisable :call Recover(false)
command! DiffOrig :call DiffOrig()
command! TestVert :call TestVert()
