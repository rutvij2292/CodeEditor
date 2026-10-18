import os, pty, sys, time, json, select, struct, fcntl, termios, re

control, prompt = sys.argv[1], sys.argv[2]
info = json.load(open(os.path.join(control, 'info.json')))
env = dict(os.environ)
env['CLAUDE_CODE_SSE_PORT'] = str(info['port'])
env['CLAUDE_CODE_AUTO_CONNECT_IDE'] = 'true'
env['TERM'] = 'xterm-256color'
for k in list(env):
    if k.startswith('CLAUDE_CODE_') and k not in ('CLAUDE_CODE_SSE_PORT', 'CLAUDE_CODE_AUTO_CONNECT_IDE'):
        del env[k]
pid, fd = pty.fork()
if pid == 0:
    os.chdir(info['root'])
    os.execvpe('/Users/rutvijkothari/.local/bin/claude', ['claude', '--model', 'haiku', '--permission-mode', 'default'], env)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', 50, 160, 0, 0))
log = open(os.path.join(control, 'screen.log'), 'wb')
buf = b''
sent_prompt = False
trusted = 0
start = time.time()
last_data = time.time()
def pump(t=0.5):
    global buf, last_data
    r, _, _ = select.select([fd], [], [], t)
    if r:
        try:
            d = os.read(fd, 65536)
        except OSError:
            return False
        if not d:
            return False
        buf += d; log.write(d); log.flush(); last_data = time.time()
    return True
def text():
    return re.sub(rb'\x1b\[[0-9;?]*[a-zA-Z]', b'', buf[-6000:]).decode('utf8', 'replace')
alive = True
while alive and time.time() - start < 200:
    alive = pump()
    t = text()
    if trusted < 3 and ('trust' in t.lower() and 'folder' in t.lower()) and time.time() - last_data > 1:
        os.write(fd, b'\x1b[B'); time.sleep(0.5); os.write(fd, b'\r'); trusted += 1; buf = b''
    if not sent_prompt and time.time() - start > 12 and time.time() - last_data > 2 and ('trust' not in t.lower() or trusted):
        os.write(fd, prompt.encode()); time.sleep(1.5); os.write(fd, b'\r'); sent_prompt = True; sent_at = time.time()
    if sent_prompt and time.time() - sent_at > 90:
        break
    if sent_prompt and os.path.exists(os.path.join(control, 'done')):
        break
try:
    os.write(fd, b'\x03'); time.sleep(0.3); os.write(fd, b'\x03')
except OSError:
    pass
time.sleep(1)
try:
    os.kill(pid, 15)
except Exception:
    pass
print('finished; sent_prompt=', sent_prompt, 'alive=', alive, 'elapsed', time.time()-start)
