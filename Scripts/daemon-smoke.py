#!/usr/bin/env python3
"""Isolated direct-TLS daemon, credentials and CLI tests; SSH is deliberately unavailable."""
import base64
import json
import os
from pathlib import Path
import shutil
import socket
import ssl
import subprocess
import tempfile
import time
import uuid
import urllib.request

from fixtures import ROOT, free_port, create_admin, browser_environment, stop_process, Wire
BIN = ROOT / '.build/debug'

def main():
    with tempfile.TemporaryDirectory(prefix='aelab-daemon-') as folder:
        root = Path(folder); remote = root/'remote'; remote.mkdir(); central = root/'central'
        daemon_home = remote/'daemon'; daemon_port = free_port()
        endpoint = f'https://localhost:{daemon_port}'
        env = dict(os.environ, AELAB_HOME=str(central), AELAB_SSH_CONFIG=str(root/'no-ssh-config'), HOME=str(remote), SHELL='/bin/sh', TMUX_TMPDIR=str(remote/'tmux'))
        env.pop('TMUX', None); env.pop('TMUX_PANE', None)
        (remote/'tmux').mkdir(mode=0o700)
        def cli(*args, success=True):
            result = subprocess.run([str(BIN/'aelab'), '--home', str(central), *args], env=env, text=True, capture_output=True, timeout=40)
            assert (result.returncode == 0) == success, result.stderr + result.stdout
            return result
        subprocess.run([str(BIN/'aelab-daemon'), '--home', str(daemon_home), 'init', '--endpoint', endpoint, '--bind', '127.0.0.1'], env=env, check=True, capture_output=True, timeout=40)
        original = (daemon_home/'pairing.json').read_bytes(); pairing = json.loads(original)
        assert (daemon_home/'key.pem').stat().st_mode & 0o077 == 0
        refused = subprocess.run([str(BIN/'aelab-daemon'), '--home', str(daemon_home), 'init', '--endpoint', endpoint], env=env, capture_output=True, timeout=40)
        assert refused.returncode != 0 and (daemon_home/'pairing.json').read_bytes() == original
        log = open(root/'daemon.log', 'w'); process = subprocess.Popen([str(BIN/'aelab-daemon'), '--home', str(daemon_home), 'run'], env=env, stdout=log, stderr=log)
        try:
            for _ in range(100):
                try:
                    probe = socket.create_connection(('127.0.0.1', daemon_port), timeout=.2); probe.close(); break
                except OSError: time.sleep(.05)
            for kwargs in [dict(trusted=False), dict(hostname='wrong-host.invalid')]:
                try: Wire(pairing, **kwargs)
                except ssl.SSLCertVerificationError: pass
                else: raise AssertionError('TLS verification was bypassed')
            for kwargs in [dict(token='0'*64), dict(origin='https://untrusted.example')]:
                wire = Wire(pairing, **kwargs); assert not wire.accepted; wire.close()
            cli('init')
            cli('daemon', 'pair', 'Laptop', '--file', str(daemon_home/'pairing.json'))
            # The Swift client itself must reject an untrusted certificate, not just Python's TLS stack.
            other_home = root/'other-daemon'
            subprocess.run([str(BIN/'aelab-daemon'), '--home', str(other_home), 'init', '--endpoint', endpoint], env=env, check=True, capture_output=True, timeout=40)
            wrong_certificate = dict(pairing, certificate=json.loads((other_home/'pairing.json').read_text())['certificate'])
            bad_pairing = root/'untrusted-pairing.json'; bad_pairing.write_text(json.dumps(wrong_certificate)); bad_pairing.chmod(0o600)
            original_config = (central/'config/aelab.json').read_bytes()
            refused_pairing = cli('daemon', 'pair', 'Untrusted', '--file', str(bad_pairing), success=False)
            assert 'Daemon connection failed' in refused_pairing.stderr and pairing['token'] not in refused_pairing.stderr
            assert (central/'config/aelab.json').read_bytes() == original_config
            config_path = central/'config/aelab.json'; config = json.loads(config_path.read_text()); host = next(h for h in config['hosts'] if h['name'] == 'Laptop')
            assert host['transport'] == 'daemon'; assert host.get('destination', '') == ''
            credentials = central/f'state/daemons/{host["daemon"]}.json'; assert credentials.stat().st_mode & 0o077 == 0
            config['tools'] = [dict(name=f'Tool {n}', executable='/usr/bin/printf', arguments=[f'TOOL-{n}']) for n in range(12)]
            host['tools'] = [f'tool-{n}' for n in range(12)]
            shutil.copy2(ROOT/'Plugins/disk-space.sh', remote/'probe.sh')
            config['plugins'] = [dict(name='Disk', executable='/bin/bash', arguments=['~/probe.sh'])]; host['plugins'] = ['disk']
            host['projects'] = [dict(name='Work', directory=str(remote))]
            config_path.write_text(json.dumps(config))
            status = json.loads(cli('status', 'laptop').stdout); assert status['reachable'] and status['connection']['transport'] == 'daemon'
            assert 'tools' not in status
            assert len(json.loads(cli('tools', 'laptop').stdout)['tools']) == 12
            assert json.loads(cli('probe', 'laptop', 'disk').stdout)['report']['summary']
            terminal = cli('tty', 'laptop', '--tool', 'tool-1'); assert 'TOOL-1' in terminal.stdout
            wire = Wire(pairing); assert wire.accepted
            # Multiplex commands and a real remote PTY on the same persistent connection.
            first, second = str(uuid.uuid4()), str(uuid.uuid4())
            wire.send(dict(id=first, operation='execute', script='sleep 0.15; printf slow', timeout=5))
            wire.send(dict(id=second, operation='execute', script='printf fast', timeout=5))
            results = [wire.receive(), wire.receive()]
            assert results[0]['id'] == second and {r['result']['output'] for r in results} == {'slow','fast'}
            timeout_id = str(uuid.uuid4()); wire.send(dict(id=timeout_id, operation='execute', script='sleep 5', timeout=.1)); assert wire.receive()['result']['status'] == 124
            session = str(uuid.uuid4()); wire.send(dict(id=session, operation='open', script='printf "PTY_READY\\n"; exec /bin/sh'))
            assert wire.receive()['operation'] == 'opened'
            output = b''
            while b'PTY_READY' not in output: output += base64.b64decode(wire.receive().get('data', ''))
            wire.send(dict(id=session, operation='resize', cols=101, rows=37))
            wire.send(dict(id=session, operation='input', data=base64.b64encode(b'stty size\n').decode()))
            output = b''
            while b'37 101' not in output: output += base64.b64decode(wire.receive().get('data', ''))
            wire.send(dict(id=session, operation='close')); wire.close()
            # A malformed protocol version closes the connection without executing a script.
            bad = Wire(pairing); bad.socket.sendall(b'\x81\x80' + b'0000')
            try: bad.receive()
            except (EOFError, ssl.SSLError): pass
            else: raise AssertionError('Malformed protocol accepted')
            bad.close()
            # Exercise the existing authenticated dashboard against this daemon.
            server_port = free_port(); origin = f'http://localhost:{server_port}'; password = create_admin(central)
            server_env = dict(env, AELAB_PORT=str(server_port), AELAB_ORIGIN=origin, AELAB_PUBLIC=str(ROOT/'Frontend/dist'))
            server_log = open(root/'server.log', 'w'); server = subprocess.Popen([str(BIN/'aelab-server')], env=server_env, stdout=server_log, stderr=server_log)
            try:
                for _ in range(100):
                    try:
                        urllib.request.urlopen(origin+'/health', timeout=.2).close(); break
                    except OSError: time.sleep(.05)
                browser_env = dict(server_env, AELAB_TEST_ORIGIN=origin, AELAB_TEST_PASSWORD=password)
                browser_env = browser_environment(browser_env)
                subprocess.run(['node', str(ROOT/'Scripts/daemon-browser-smoke.mjs')], env=browser_env, check=True, timeout=90)
            finally:
                stop_process(server, timeout=8)
                server_log.close()
            # Pairing token never enters the main config or CLI output.
            assert pairing['token'] not in config_path.read_text()
            broken = json.loads(credentials.read_text()); broken['token'] = '0'*64; credentials.write_text(json.dumps(broken))
            failed = cli('status', 'laptop', success=False); assert 'Daemon connection failed' in failed.stderr
            assert pairing['token'] not in failed.stderr
            print('PASS: direct daemon TLS/pairing without SSH; strict certificates/auth/Origin, multiplexing, limits, CLI status/tools/plugins/PTY, resize, timeout and malformed-message rejection')
        finally:
            stop_process(process, timeout=8)
            log.close()
            if process.returncode not in [0, -15]: print((root/'daemon.log').read_text())

if __name__ == '__main__': main()
