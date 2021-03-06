" Vim integration with IPython 0.11+
"
" A two-way integration between Vim and IPython. 
"
" Using this plugin, you can send lines or whole files for IPython to execute,
" and also get back object introspection and word completions in Vim, like
" what you get with: object?<enter> object.<tab> in IPython
"
" -----------------
" Quickstart Guide:
" -----------------
" Start ipython qtconsole and copy the connection string.
" Source this file, which provides new IPython command
"   :source ipy.vim  
"   :IPythonClipboard   
"   (or :IPythonXSelection if you're using X11 without having to copy)
"
" written by Paul Ivanov (http://pirsquared.org)
python << EOF
reselect = False            # reselect lines after sending from Visual mode
show_execution_count = True # wait to get numbers for In[43]: feedback?
monitor_subchannel = True   # update vim-ipython 'shell' on every send?
run_flags= "-i"             # flags to for IPython's run magic when using <F5>

import time
import vim
import sys

try:
    sys.stdout.flush
except AttributeError:
    # IPython complains if stderr and stdout don't have flush
    # this is fixed in newer version of Vim
    class WithFlush(object):
        def __init__(self,noflush):
            self.write=noflush.write
            self.writelines=noflush.writelines
        def flush(self):pass
    sys.stdout = WithFlush(sys.stdout)
    sys.stderr = WithFlush(sys.stderr)

from IPython.zmq.blockingkernelmanager import BlockingKernelManager

from IPython.config.loader import KeyValueConfigLoader
from IPython.zmq.kernelapp import kernel_aliases


ip = '127.0.0.1'
try:
    km
except NameError:
    km = None

def km_from_string(s):
    """create kernel manager from IPKernelApp string
    such as '--shell=47378 --iopub=39859 --stdin=36778 --hb=52668'
    """
    global km,send
    # vim interface currently only deals with existing kernels
    s = s.replace('--existing','')
    loader = KeyValueConfigLoader(s.split(), aliases=kernel_aliases)
    cfg = loader.load_config()['KernelApp']
    try:
        km = BlockingKernelManager(
            shell_address=(ip, cfg['shell_port']),
            sub_address=(ip, cfg['iopub_port']),
            stdin_address=(ip, cfg['stdin_port']),
            hb_address=(ip, cfg['hb_port']))
    except KeyError,e:
        echo(":IPython " +s + " failed", "Info")
        echo("^-- failed --"+e.message.replace('_port','')+" not specified", "Error")
        return
    km.start_channels()
    send = km.shell_channel.execute
    return km



def echo(arg,style="Question"):
    try:
        vim.command("echohl %s" % style)
        vim.command("echom \"%s\"" % arg.replace('\"','\\\"'))
        vim.command("echohl None")
    except vim.error:
        print "-- %s" % arg

def disconnect():
    "disconnect kernel manager"
    # XXX: make a prompt here if this km owns the kernel
    pass

def get_doc(word):
    if km is None:
        return ["Not connected to IPython, cannot query \"%s\"" %word]
    msg_id = km.shell_channel.object_info(word)
    time.sleep(.1)
    doc = get_doc_msg(msg_id)
    # get around unicode problems when interfacing with vim
    encoding=vim.eval('&encoding')
    return [d.encode(encoding) for d in doc]

import re
# from http://serverfault.com/questions/71285/in-centos-4-4-how-can-i-strip-escape-sequences-from-a-text-file
strip = re.compile('\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]')
def strip_color_escapes(s):
    return strip.sub('',s)
    
def get_doc_msg(msg_id):
    content = get_child_msgs(msg_id)[0]['content']
    n = 13 # longest field name (empirically)
    b=[]

    if not content['found']:
        return b

    for field in ['type_name','base_class','string_form','namespace',
            'file','length','definition','source','docstring']:
        c = content.get(field,None)
        if c:
            if field in ['definition']:
                c = strip_color_escapes(c).rstrip()
            s = field.replace('_',' ').title()+':'
            s = s.ljust(n)
            if c.find('\n')==-1:
                b.append(s+c)
            else:
                b.append(s)
                b.extend(c.splitlines())
    return b

def get_doc_buffer(level=0):
    word = vim.eval('expand("<cfile>")')
    doc = get_doc(word)
    if len(doc) ==0:
        echo(word+" not found","Error")
        return
    vim.command('pcl')
    vim.command('new '+word)
    vim.command('setlocal pvw modifiable noro')
    # doc window quick quit keys: 'q' and 'escape'
    vim.command('map <buffer> q :q<CR>')
    vim.command('map <buffer>  :q<CR>')
    #vim.command('pedit '+docbuf.name)
    b = vim.current.buffer
    #b.append(doc)
    b[:] = None
    b[:] = doc
    #b.append(doc)
    vim.command('setlocal nomodified bufhidden=wipe')
    #vim.command('setlocal previewwindow nomodifiable nomodified ro')
    #vim.command('set previewheight=%d'%len(b))# go to previous window
    vim.command('resize %d'%len(b))
    #vim.command('pcl')
    #vim.command('pedit doc')
    #vim.command('normal ') # go to previous window

def update_subchannel_msgs(debug=False):
    msgs = km.sub_channel.get_msgs()
    if debug:
        #try:
        #    vim.command("b debug_msgs")
        #except vim.error:
        #    vim.command("new debug_msgs")
        #finally:
        db = vim.current.buffer
    else:
        db = []
    vim.command("pcl")
    vim.command("silent pedit vim-ipython")
    vim.command("normal P") #switch to preview window
    # subchannel window quick quit key 'q'
    vim.command('map <buffer> q :q<CR>')
    vim.command("set bufhidden=hide buftype=nofile ft=python")
    
    #syntax highlighting for python prompt
    # QtConsole In[] is blue, but I prefer the oldschool green
    # since it makes the vim-ipython 'shell' look like the holidays!
    #vim.command("hi Blue ctermfg=Blue guifg=Blue")
    vim.command("hi Green ctermfg=Green guifg=Green")
    vim.command("hi Red ctermfg=Red guifg=Red")
    vim.command("syn keyword Green 'In\ []:'")
    vim.command("syn match Green /^In \[[0-9]*\]\:/")
    vim.command("syn match Red /^Out\[[0-9]*\]\:/")
    b = vim.current.buffer
    for m in msgs:
        db.append(str(m).splitlines())
        if m['msg_type'] == 'status':
            continue
        if m['msg_type'] == 'stream':
            s = strip_color_escapes(m['content']['data'])
        if m['msg_type'] == 'pyout':
            s = "Out[%d]: " % m['content']['execution_count']
            s += m['content']['data']['text/plain']
        if m['msg_type'] == 'pyin':
            s = "\nIn []: "
            s += m['content']['code'].strip()
        if m['msg_type'] == 'pyerr':
            c = m['content']
            s = "\n".join(map(strip_color_escapes,c['traceback']))
            s += c['ename'] + ":" + c['evalue']
        if s.find('\n')==-1:
            # somewhat ugly unicode workaround from http://vim.1045645.n5.nabble.com/Limitations-of-vim-python-interface-with-respect-to-character-encodings-td1223881.html
            if isinstance(s,unicode):
                s=s.encode(vim.eval("&encoding"))
            b.append(s)
        else:
            try:
                b.append(s.splitlines())
            except:
                encoding = vim.eval("&encoding")
                b.append([l.encode(encoding) for l in s.splitlines()])
    vim.command('normal G') # go to the end of the file
    vim.command('silent e #|silent pedit vim-ipython')
    
def get_child_msgs(msg_id):
    # XXX: message handling should be split into its own process in the future
    msgs= km.shell_channel.get_msgs()
    children = [m for m in msgs if m['parent_header']['msg_id'] == msg_id]
    return children
            
def print_prompt(prompt,msg_id=None):
    """Print In[] or In[42] style messages"""
    global show_execution_count
    if show_execution_count and msg_id:
        time.sleep(.1) # wait to get message back from kernel
        children = get_child_msgs(msg_id)
        if len(children):
            count = children[0]['content']['execution_count']
            echo("In[%d]: %s" %(count,prompt))
        else:
            echo("In[]: %s (no reply from kernel)" % prompt)
    else:
        echo("In[]: %s" % prompt)

def with_subchannel(f):
    "conditionally monitor subchannel"
    def f_with_update():
        try:
            f()
            if monitor_subchannel:
                update_subchannel_msgs()
                vim.command('normal p') # go back to where you were
        except AttributeError: #if km is None
            echo("not connected to IPython", 'Error')
    return f_with_update

@with_subchannel
def run_this_file():
    msg_id = send('run %s %s' % (run_flags, vim.current.buffer.name,))
    print_prompt("In[]: run %s %s" % (run_flags, vim.current.buffer.name),msg_id)

@with_subchannel
def run_this_line():
    msg_id = send(vim.current.line)
    print_prompt(vim.current.line, msg_id)

@with_subchannel
def run_these_lines():
    r = vim.current.range
    lines = "\n".join(vim.current.buffer[r.start:r.end+1])
    msg_id = send(lines)
    #alternative way of doing this in more recent versions of ipython
    #but %paste only works on the local machine
    #vim.command("\"*yy")
    #send("'%paste')")
    #reselect the previously highlighted block
    vim.command("normal gv")
    if not reselect:
        vim.command("normal ")

    #vim lines start with 1
    #print "lines %d-%d sent to ipython"% (r.start+1,r.end+1)
    prompt = "lines %d-%d "% (r.start+1,r.end+1)
    print_prompt(prompt,msg_id)

def dedent_run_this_line():
    vim.command("left")
    run_this_line()
    vim.command("undo")

def dedent_run_these_lines():
    vim.command("'<,'>left")
    run_these_lines()
    vim.command("undo")
    
#def set_this_line():
#    # not sure if there's a way to do this, since we have multiple clients
#    send("_ip.IP.rl_next_input= \'%s\'" % vim.current.line.replace("\'","\\\'"))
#    #print "line \'%s\' set at ipython prompt"% vim.current.line
#    echo("line \'%s\' set at ipython prompt"% vim.current.line,'Statement')


def toggle_reselect():
    global reselect
    reselect=not reselect
    print "F9 will%sreselect lines after sending to ipython"% (reselect and " " or " not ")

#def set_breakpoint():
#    send("__IP.InteractiveTB.pdb.set_break('%s',%d)" % (vim.current.buffer.name,
#                                                        vim.current.window.cursor[0]))
#    print "set breakpoint in %s:%d"% (vim.current.buffer.name, 
#                                      vim.current.window.cursor[0])
#    
#def clear_breakpoint():
#    send("__IP.InteractiveTB.pdb.clear_break('%s',%d)" % (vim.current.buffer.name,
#                                                          vim.current.window.cursor[0]))
#    print "clearing breakpoint in %s:%d" % (vim.current.buffer.name,
#                                            vim.current.window.cursor[0])
#
#def clear_all_breakpoints():
#    send("__IP.InteractiveTB.pdb.clear_all_breaks()");
#    print "clearing all breakpoints"
#
#def run_this_file_pdb():
#    send(' __IP.InteractiveTB.pdb.run(\'execfile("%s")\')' % (vim.current.buffer.name,))
#    #send('run -d %s' % (vim.current.buffer.name,))
#    echo("In[]: run -d %s (using pdb)" % vim.current.buffer.name)

EOF

fun! <SID>toggle_send_on_save()
    if exists("s:ssos") && s:ssos == 0
        let s:ssos = 1
        au BufWritePost *.py :py run_this_file()
        echo "Autosend On"
    else
        let s:ssos = 0
        au! BufWritePost *.py
        echo "Autosend Off"
    endif
endfun

map <silent> <F5> :python run_this_file()<CR>
map <silent> <S-F5> :python run_this_line()<CR>
map <silent> <F9> :python run_these_lines()<CR>
map <leader>d :py get_doc_buffer()<CR>
map <leader>s :py update_subchannel_msgs()<CR>
map <silent> <S-F9> :python toggle_reselect()<CR>
"map <silent> <C-F6> :python send('%pdb')<CR>
"map <silent> <F6> :python set_breakpoint()<CR>
"map <silent> <s-F6> :python clear_breakpoint()<CR>
"map <silent> <F7> :python run_this_file_pdb()<CR>
"map <silent> <s-F7> :python clear_all_breaks()<CR>
imap <C-F5> <C-O><F5>
imap <S-F5> <C-O><S-F5>
imap <silent> <F5> <C-O><F5>
map <C-F5> :call <SID>toggle_send_on_save()<CR>

"pi custom
map <silent> <C-Return> :python run_this_file()<CR>
map <silent> <C-s> :python run_this_line()<CR>
imap <silent> <C-s> <C-O>:python run_this_line()<CR>
map <silent> <M-s> :python dedent_run_this_line()<CR>
vmap <silent> <C-S> :python run_these_lines()<CR>
vmap <silent> <M-s> :python dedent_run_these_lines()<CR>
"map <silent> <C-p> :python set_this_line()<CR>
map <silent> <M-c> I#<ESC>
vmap <silent> <M-c> I#<ESC>
map <silent> <M-C> :s/^\([ \t]*\)#/\1/<CR>
vmap <silent> <M-C> :s/^\([ \t]*\)#/\1/<CR>

command! -nargs=+ IPython :py km_from_string("<args>")
command! -nargs=0 IPythonClipboard :py km_from_string(vim.eval('@+'))
command! -nargs=0 IPythonXSelection :py km_from_string(vim.eval('@*'))

function! IPythonBalloonExpr()
python << endpython
word = vim.eval('v:beval_text')
reply = get_doc(word)
vim.command("let l:doc = %s"% reply)
endpython
return l:doc
endfunction
if has("gui_running")
	set bexpr=IPythonBalloonExpr()
	set ballooneval
endif

fun! CompleteIPython(findstart, base)
	  if a:findstart
	    " locate the start of the word
	    let line = getline('.')
	    let start = col('.') - 1
	    while start > 0 && line[start-1] =~ '\k\|\.' "keyword
	      let start -= 1
	    endwhile
        echo start
	    return start
	  else
	    " find months matching with "a:base"
	    let res = []
        python << endpython
base = vim.eval("a:base")
findstart = vim.eval("a:findstart")
msg_id = km.shell_channel.complete(base, vim.current.line, vim.eval("col('.')"))
time.sleep(.1)
m = get_child_msgs(msg_id)[0]
# get rid of unicode (sporadic issue, haven't tracked down when it happens)
#matches = [str(u) for u in m['content']['matches']]
# mirk sez do: completion_str = '[' + ', '.join(msg['content']['matches'] ) + ']'
# because str() won't work for non-ascii characters
matches = m['content']['matches']
#end = len(base)
#completions = [m[end:]+findstart+base for m in matches]
matches.insert(0,base) # the "no completion" version
#echo(str(matches))
completions = matches
vim.command("let l:completions = %s"% completions)
endpython
	    for m in l:completions
	      "if m =~ '^' . a:base
            call add(res, m)
	      "endif
	    endfor
	    return res
	  endif
	endfun
set completefunc=CompleteIPython
