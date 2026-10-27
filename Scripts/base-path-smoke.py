#!/usr/bin/env python3
"""Real mounted dashboard/login/docs/WebSocket test with an isolated local host."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import urllib.request

from fixtures import ROOT, free_port, create_admin, browser_environment, stop_process
with tempfile.TemporaryDirectory(prefix='aelab-base-', dir='/tmp') as folder:
    home = Path(folder); (home/'config').mkdir(); (home/'state').mkdir()
    (home/'config/aelab.json').write_text(json.dumps(dict(version=1, hosts=[dict(name='Local', transport='local', projects=[dict(name='Work', dir=folder)], services=[], tools=[], plugins=[])])))
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
        subprocess.run(['node', str(ROOT/'Scripts'/os.environ.get('AELAB_TEST_BROWSER_SCRIPT', 'base-path-browser-smoke.mjs'))], env=env, check=True, timeout=90)
    except BaseException:
        log.flush(); print((home/'server.log').read_text()); raise
    finally:
        stop_process(server, timeout=10)
        log.close()
