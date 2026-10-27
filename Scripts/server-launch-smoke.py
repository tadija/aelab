#!/usr/bin/env python3
"""Isolated server launch orchestration test with real CLI, admin setup and HTTP server.

Build commands are recorded stand-ins; build the release binaries and frontend first.
No production home, server or SSH configuration is touched.
"""
import json
import os
from pathlib import Path
import pty
import re
import secrets
import select
import signal
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import urllib.parse

from fixtures import ROOT, free_port


def main():
    with tempfile.TemporaryDirectory(prefix='aelab-server-') as temporary:
        root = Path(temporary)
        home = root / 'private home'
        commands = root / 'commands'
        commands.mkdir()
        log = root / 'build.log'
        for command in ['swift', 'npm']:
            path = commands / command
            path.write_text('#!/bin/sh\nset -eu\nif [ "${1:-}" = --version ]; then printf \'%s\\n\' fixture-npm; exit 0; fi\nprintf "%s|%s|%s\\n" "$PWD" "${0##*/}" "$*" >> "$RUN_TEST_LOG"\n')
            path.chmod(0o755)
        env = dict(os.environ, PATH=str(commands) + os.pathsep + os.environ['PATH'], RUN_TEST_LOG=str(log))
        for key in ['AELAB_HOME', 'AELAB_PORT', 'AELAB_ORIGIN', 'AELAB_PUBLIC', 'AELAB_BIND']:
            env.pop(key, None)
        password = secrets.token_urlsafe(24)
        saved_config = saved_credentials = None
        for attempt in range(4):
            port = free_port()
            origin = f'http://localhost:{port}'
            master, slave = pty.openpty()
            command_env = dict(env)
            if attempt < 2:
                arguments = ['server', '--home', str(home)] if attempt == 0 else ['--home', 'private home', 'server', '--configuration', 'debug']
                command = [str(ROOT / '.ae'), *arguments, '--port', str(port)]
            else:
                prefix = root / 'installed application'
                if attempt == 2:
                    subprocess.run([str(ROOT / '.ae'), 'install', '--prefix', str(prefix)],
                                   cwd=root, env=env, check=True, capture_output=True, text=True, timeout=15)
                assert (prefix/'bin/aelab-daemon').is_file()
                assert (prefix/'bin/aelab-cli').is_file()
                assert os.readlink(prefix/'bin/aelab') == 'aelab-cli'
                command_env['PATH'] = str(prefix / 'bin') + os.pathsep + env['PATH']
                if attempt == 2:
                    command = ['aelab', 'server', '--home', str(home), '--port', str(port)]
                else:
                    command_env.update(AELAB_HOME=str(home), AELAB_PORT=str(port))
                    command = ['aelab-server']
            process = subprocess.Popen(command,
                                       cwd=root, env=command_env, stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
            os.close(slave)
            output = b''
            prompted = False
            try:
                ready = False
                deadline = time.monotonic() + 20
                while time.monotonic() < deadline:
                    if select.select([master], [], [], .05)[0]:
                        try:
                            output += os.read(master, 65536)
                        except OSError:
                            break
                    if not prompted and b'Administrator password' in output:
                        assert attempt == 0, 'Existing credentials must not prompt for replacement'
                        os.write(master, (password + '\n').encode())
                        prompted = True
                    if process.poll() is not None:
                        raise AssertionError(f'Server launch exited unexpectedly: {process.returncode}')
                    try:
                        with urllib.request.urlopen(origin + '/health', timeout=.1) as response:
                            ready = response.status == 200
                    except (OSError, urllib.error.URLError):
                        continue
                    if ready:
                        break
                assert ready, 'CLI did not start the server'
                assert prompted == (attempt == 0)
                with urllib.request.urlopen(origin + '/', timeout=2) as response:
                    html = response.read().decode()
                    assets = re.findall(r'(?:src|href)="((?:\./|/)assets/[^"]+)"', html)
                    assert assets, 'Dashboard assets must be served'
                for asset in assets:
                    with urllib.request.urlopen(urllib.parse.urljoin(origin + "/", asset), timeout=2) as response:
                        assert response.status == 200 and response.read()
                request = urllib.request.Request(origin + '/api/auth/session',
                    data=json.dumps({'password': password}).encode(),
                    headers={'Origin': origin, 'Content-Type': 'application/json'})
                with urllib.request.urlopen(request, timeout=3) as response:
                    assert response.status == 200
                config = (home / 'config/aelab.json').read_bytes()
                credentials = (home / 'state/admin.json').read_bytes()
                assert json.loads(config)['ttyButtons'] == json.loads((ROOT/'Docs/Config/aelab.example.json').read_text())['ttyButtons']
                assert json.loads(config)['hosts'][0]['transport'] == 'local'
                if attempt == 0:
                    saved_config, saved_credentials = config, credentials
                else:
                    assert config == saved_config and credentials == saved_credentials
            finally:
                if process.poll() is None:
                    process.send_signal(signal.SIGINT)
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
                        raise AssertionError("Foreground server did not stop with Ctrl+C")
                os.close(master)
        expected = [f'{ROOT}|swift|build -c release', f'{ROOT}|npm|ci --include=dev --prefix Frontend', f'{ROOT}|npm|run build --prefix Frontend', f'{ROOT}|swift|build -c debug', f'{ROOT}|npm|run build --prefix Frontend -- --mode development --sourcemap', f'{ROOT}|swift|build -c release', f'{ROOT}|npm|run build --prefix Frontend']
        assert log.read_text().splitlines() == expected
        result = subprocess.run([str(ROOT / '.ae'), 'server', '--port', 'invalid'], env=env,
                                capture_output=True, text=True, timeout=3)
        assert result.returncode != 0 and log.read_text().splitlines() == expected
        result = subprocess.run([str(ROOT / '.ae'), 'server', '--configuration', 'invalid'], env=env, capture_output=True, text=True, timeout=3)
        assert result.returncode != 0 and log.read_text().splitlines() == expected
        print('PASS: debug/release selection, server build order, first-run interactive admin, custom home/port, real dashboard/login, repeat-update preservation, installed CLI/server/daemon/assets without checkout cwd, and invalid-port rejection')


if __name__ == '__main__':
    main()
