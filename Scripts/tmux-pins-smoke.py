#!/usr/bin/env python3
"""Tmux pin acceptance using an isolated home and an owned tmux socket."""
import json
import shutil
import shlex
import uuid
import os
from pathlib import Path
import subprocess
import tempfile
import time
import urllib.request

from fixtures import ROOT, free_port, create_admin, browser_environment, stop_process
with tempfile.TemporaryDirectory(prefix='aelab-base-', dir='/tmp') as folder:
    home = Path(folder); (home/'config').mkdir(); (home/'state').mkdir()
    socket = 'aelab-pins-' + uuid.uuid4().hex
    tmux = shutil.which('tmux')
    assert tmux, 'tmux is required'
    bindir = home/'bin'; bindir.mkdir()
    wrapper = bindir/'tmux'
    wrapper.write_text('#!/bin/sh\nexec ' + shlex.quote(tmux) + ' -L ' + shlex.quote(socket) + ' \"$@\"\n')
    wrapper.chmod(0o700)
    subprocess.run([tmux, '-L', socket, 'new-session', '-d', '-s', 'pin-work', 'sleep 300'], check=True)
    (home/'config/aelab.json').write_text(json.dumps(dict(version=1, paths=[str(bindir)], hosts=[dict(name='Local', transport='local', projects=[dict(name='Work', dir=folder)], services=[], tools=[], plugins=[])])))
    password = create_admin(home)
    port = free_port()
    origin = f'http://localhost:{port}'
    env = dict(os.environ, AELAB_HOME=folder, AELAB_PORT=str(port), AELAB_ORIGIN=origin, AELAB_BASE_PATH='/lab/aelab/', AELAB_PUBLIC=str(ROOT/'Frontend/dist'), AELAB_TEST_ORIGIN=origin, AELAB_TEST_PASSWORD=password)
    env = browser_environment(env)
    log = open(home/'server.log', 'w')
    binary = ROOT/'.build'/os.environ.get('AELAB_TEST_CONFIGURATION', 'debug')/'aelab-cli'
    server = subprocess.Popen([str(binary), 'server'], env=env, stdout=log, stderr=log)
    try:
        for _ in range(100):
            try:
                urllib.request.urlopen(origin+'/lab/aelab/health', timeout=.2).close(); break
            except OSError: time.sleep(.1)
        log.flush(); assert 'Starting aelab at '+origin+'/lab/aelab/' in (home/'server.log').read_text()
        script = str(ROOT/'Scripts'/os.environ.get('AELAB_TEST_BROWSER_SCRIPT', 'tmux-pins-browser-smoke.mjs'))
        subprocess.run(['node', script], env=dict(env, AELAB_TEST_PHASE='before'), check=True, timeout=90)
        if os.environ.get('AELAB_TEST_RESTART'):
            state = home/'state/tmux-pins.json'
            saved = json.loads(state.read_text())
            assert len(saved) == 1 and state.stat().st_mode & 0o777 == 0o600
            stop_process(server, timeout=10)
            subprocess.run([tmux, '-L', socket, 'has-session', '-t', '=pin-work'], check=True)
            server = subprocess.Popen([str(binary), 'server'], env=env, stdout=log, stderr=log)
            for _ in range(100):
                try:
                    urllib.request.urlopen(origin+'/lab/aelab/health', timeout=.2).close(); break
                except OSError: time.sleep(.1)
            subprocess.run(['node', script], env=dict(env, AELAB_TEST_PHASE='after', AELAB_TEST_PIN_ID=saved[0]['id'], AELAB_TEST_PIN_NUMBER=str(saved[0]['number'])), check=True, timeout=90)
            assert json.loads(state.read_text()) == []
            subprocess.run([tmux, '-L', socket, 'has-session', '-t', '=pin-work'], check=True)
    except BaseException:
        log.flush(); print((home/'server.log').read_text()); raise
    finally:
        stop_process(server, timeout=10)
        log.close()
        subprocess.run([tmux, '-L', socket, 'kill-server'], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
