#!/usr/bin/env python3
"""Real browser uploads to isolated local, SSH and daemon hosts; no production homes."""
import base64
import getpass
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request
import uuid

from fixtures import ROOT, free_port, create_admin, browser_environment, stop_process, Wire

with tempfile.TemporaryDirectory(prefix='aelab-files-') as folder:
    root = Path(folder); children = []; logs = []
    try:
        homes = {name: root/name for name in ['local', 'ssh', 'daemon']}
        for home in homes.values(): home.mkdir(mode=0o700)
        central = root/'central'; (central/'config').mkdir(parents=True); (central/'state/daemons').mkdir(parents=True)
        (root/'spool').mkdir()
        subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(root/'key')], check=True)
        (root/'authorized_keys').write_text((root/'key.pub').read_text()); (root/'authorized_keys').chmod(0o600)
        subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(root/'host_key')], check=True)
        ssh_port = free_port(); public = (root/'host_key.pub').read_text().split()
        (root/'known_hosts').write_text(f'[127.0.0.1]:{ssh_port} {public[0]} {public[1]}\n')
        (root/'ssh_config').write_text(f'Host file-fixture\n HostName 127.0.0.1\n Port {ssh_port}\n User {getpass.getuser()}\n IdentityFile {root}/key\n UserKnownHostsFile {root}/known_hosts\n IdentitiesOnly yes\n')
        (root/'sshd_config').write_text(f'''Port {ssh_port}
ListenAddress 127.0.0.1
HostKey {root}/host_key
PidFile {root}/sshd.pid
AuthorizedKeysFile {root}/authorized_keys
StrictModes yes
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
AllowUsers {getpass.getuser()}
SetEnv HOME={homes['ssh']} SHELL=/bin/sh PATH={os.environ['PATH']}
LogLevel VERBOSE
''')
        def start(command, env, name):
            log = open(root/(name+'.log'), 'w'); logs.append(log)
            child = subprocess.Popen(command, env=env, stdout=log, stderr=log); children.append(child); return child
        start([shutil.which('sshd') or '/usr/sbin/sshd', '-D', '-e', '-f', str(root/'sshd_config')], os.environ, 'ssh')
        for _ in range(100):
            try: probe = socket.create_connection(('127.0.0.1', ssh_port), timeout=.1); probe.close(); break
            except OSError: time.sleep(.05)
        # A tiny native TUI validates one bracketed image path, reads its bytes, and renders its own label.
        probe = root/'attachment-probe.py'
        probe.write_text('''import os,sys,tty,termios,shlex
saved=termios.tcgetattr(0)
try:
 tty.setraw(0); os.write(1,b"\\x1b[?2004hPROBE_READY\\r\\n"); data=b""; count=0
 while True:
  chunk=os.read(0,65536)
  if not chunk or b"\\x03" in chunk: break
  data+=chunk
  while b"\\x1b[201~" in data:
   frame,data=data.split(b"\\x1b[201~",1)
   if b"\\x1b[200~" not in frame: continue
   text=frame.split(b"\\x1b[200~",1)[1].decode()
   try: parts=shlex.split(text)
   except ValueError: parts=[]
   if len(parts)==1 and os.path.isfile(parts[0]):
    image=open(parts[0],"rb").read()
    if image.startswith(b"\\x89PNG\\r\\n\\x1a\\n"):
     count+=1; os.write(1,f"[Image #{count}]\\r\\n".encode())
   elif text.strip(): os.write(1,("TEXT:"+text+"\\r\\n").encode())
finally:
 termios.tcsetattr(0,termios.TCSANOW,saved)
''')
        env = dict(os.environ, HOME=str(homes['daemon']), SHELL='/bin/sh')
        daemon_home = root/'daemon-state'; daemon_port = free_port()
        subprocess.run([str(ROOT/'.build/debug/aelab-daemon'), '--home', str(daemon_home), 'init', '--endpoint', f'https://localhost:{daemon_port}', '--bind', '127.0.0.1'], env=env, check=True, capture_output=True, timeout=30)
        start([str(ROOT/'.build/debug/aelab-daemon'), '--home', str(daemon_home)], env, 'daemon')
        pairing = json.loads((daemon_home/'pairing.json').read_text())
        for _ in range(100):
            try: wire = Wire(pairing); break
            except OSError: time.sleep(.05)
        transfer = str(uuid.uuid4())
        wire.send(dict(id=transfer, operation='file-begin', name='partial.bin', size=10))
        assert wire.receive()['upload'] == transfer
        wire.send(dict(id=str(uuid.uuid4()), operation='file-write', upload=transfer, offset=1, data=base64.b64encode(b'abc').decode()))
        assert 'error' in wire.receive()
        wire.send(dict(id=str(uuid.uuid4()), operation='execute', script='printf still-alive', timeout=5))
        assert wire.receive()['result']['output'] == 'still-alive'
        wire.send(dict(id=str(uuid.uuid4()), operation='file-write', upload=transfer, offset=0, data=base64.b64encode(b'abc').decode()))
        assert wire.receive()['operation'] == 'result'
        wire.close()
        for _ in range(100):
            if not list((homes['daemon']/'.aelab/uploads').iterdir()): break
            time.sleep(.05)
        assert not list((homes['daemon']/'.aelab/uploads').iterdir()), 'Disconnect must remove partial daemon uploads'
        connection = str(uuid.uuid4()); shutil.copy2(daemon_home/'pairing.json', central/f'state/daemons/{connection}.json')
        config = dict(version=1, hosts=[dict(name='Local', transport='local', tools=['attachment-probe']), dict(name='SSH', transport='ssh', destination='file-fixture', tools=['attachment-probe']), dict(name='Daemon', transport='daemon', daemon=connection, tools=['attachment-probe'])], tools=[dict(name='Attachment probe', executable=sys.executable, arguments=['-u', str(probe)])], ttyButtons=[dict(key='alt', label='Alt'), dict(key='paste', label='Paste')])
        (central/'config/aelab.json').write_text(json.dumps(config)); password = create_admin(central)
        port = free_port(); origin = f'http://localhost:{port}'
        env = dict(os.environ, AELAB_HOME=str(central), HOME=str(homes['local']), SHELL='/bin/sh', TMPDIR=str(root/'spool'), AELAB_PORT=str(port), AELAB_ORIGIN=origin, AELAB_BASE_PATH='/lab/aelab', AELAB_PUBLIC=str(ROOT/'Frontend/dist'), AELAB_SSH_CONFIG=str(root/'ssh_config'))
        start([str(ROOT/'.build/debug/aelab-server')], env, 'server')
        for _ in range(150):
            try: urllib.request.urlopen(origin+'/lab/aelab/health', timeout=.2).close(); break
            except OSError: time.sleep(.1)
        browser_env = browser_environment(dict(env, AELAB_TEST_ORIGIN=origin, AELAB_TEST_PASSWORD=password, AELAB_TEST_UPLOAD_HOMES=json.dumps({key:str(path) for key,path in homes.items()})))
        subprocess.run(['node', str(ROOT/'Scripts/terminal-files-browser-smoke.mjs')], env=browser_env, check=True, timeout=120)
        assert not list((root/'spool').glob('aelab-transfer-*')), 'Central spools must be removed'
    except BaseException:
        for log in root.glob('*.log'): print(log.name+'\n'+log.read_text())
        raise
    finally:
        for child in reversed(children): stop_process(child, timeout=10)
        for log in logs: log.close()
