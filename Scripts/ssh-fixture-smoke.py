#!/usr/bin/env python3
"""Two real disposable SSH endpoints. No system sshd, known_hosts or production config changes."""
import getpass
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time

from fixtures import ROOT, free_port, browser_environment, stop_process

def main():
    sshd = shutil.which('sshd') or '/usr/sbin/sshd'
    children = []
    logs = []
    # Use the protected OS temp directory; StrictModes stays enabled.
    with tempfile.TemporaryDirectory(prefix='aelab-ssh-') as folder:
        root = Path(folder)
        try:
            subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(root/'identity')], check=True)
            (root/'authorized_keys').write_text((root/'identity.pub').read_text()); os.chmod(root/'authorized_keys', 0o600)
            aliases = []; known = []
            for number in [1, 2]:
                directory = root / str(number); directory.mkdir(mode=0o700)
                (directory/'.tmux.conf').write_text(f'set -g prefix C-{"a" if number == 1 else "b"}\nset -g mouse on\n')
                subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(directory/'host_key')], check=True)
                port = free_port(); alias = f'endpoint-{number}'
                public = (directory/'host_key.pub').read_text().split()
                known.append(f'[127.0.0.1]:{port} {public[0]} {public[1]}\n')
                aliases.append(f'Host {alias}\n HostName 127.0.0.1\n Port {port}\n User {getpass.getuser()}\n IdentityFile {root}/identity\n UserKnownHostsFile {root}/known_hosts\n IdentitiesOnly yes\n')
                config = directory/'sshd_config'
                config.write_text(f'''Port {port}
ListenAddress 127.0.0.1
HostKey {directory}/host_key
PidFile {directory}/sshd.pid
AuthorizedKeysFile {root}/authorized_keys
StrictModes yes
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
AllowUsers {getpass.getuser()}
SetEnv PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin TMUX_TMPDIR={directory} HOME={directory}
LogLevel VERBOSE
''')
                logfile = open(directory/'log', 'w'); logs.append(logfile)
                children.append(subprocess.Popen([sshd, '-D', '-e', '-f', str(config)], stdout=logfile, stderr=logfile))
            (root/'known_hosts').write_text(''.join(known)); (root/'ssh_config').write_text(''.join(aliases))
            time.sleep(.3)
            for number in [1, 2]:
                result = subprocess.run(['ssh', '-F', str(root/'ssh_config'), '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=3', f'endpoint-{number}', 'uname -sn'], text=True, capture_output=True, timeout=5)
                if result.returncode:
                    raise RuntimeError(result.stderr + '\n' + (root/str(number)/'log').read_text())
            home = root/'home'; (home/'config').mkdir(parents=True); (home/'state').mkdir()
            local = root/'local'; local.mkdir(mode=0o700)
            for number, directory in [(1, root/'1'), (2, root/'2'), (3, local)]:
                subprocess.run(['git', 'init', '--template=', str(directory)], check=True, capture_output=True)
                subprocess.run(['git', '-C', str(directory), 'symbolic-ref', 'HEAD', f'refs/heads/fixture/host-{number}'], check=True)
            (local/'.tmux.conf').write_text('set -g prefix C-b\nset -g mouse on\n')
            config = dict(version=1, tools=[dict(name=f'Tool {n}', executable='/usr/bin/printf', arguments=[f'HOST-{n}']) for n in [1,2,3]], plugins=[], paths=['/opt/homebrew/bin','/usr/local/bin'], hosts=[dict(name=f'Fixture {n}', background='#223344', **(dict(transport='local') if n == 3 else dict(destination=f'endpoint-{n}')), projects=[dict(name=f'Project {n}', directory=str(local if n == 3 else root/str(n)))], services=[], tools=[f'tool-{n}'], plugins=[]) for n in [1,2,3]])
            config['tools'][0]['yoloArguments'] = []
            config['tools'].append(dict(name='Project tool', executable='/bin/sh', arguments=['-c', 'printf "PROJECT_TOOL_OK\\n"; pwd; exec /bin/sh']))
            config['hosts'][0]['tools'].append('project-tool')
            config['ttyButtons'] = json.loads((ROOT/'Docs/Config/aelab.example.json').read_text())['ttyButtons']
            # Real Bash/Ruby scripts on disposable SSH endpoints, compiled Swift on native local.
            swift_probe = root/'uptime'
            shutil.copy2(ROOT/'Plugins/uptime.swift', local/'uptime.swift')
            shutil.copy2(ROOT/'Plugins/disk-space.sh', root/'1/disk-space.sh')
            shutil.copy2(ROOT/'Plugins/process-count.rb', root/'2/process-count.rb')
            subprocess.run(['swiftc', str(local/'uptime.swift'), '-o', str(swift_probe)], check=True, timeout=60)
            definitions = [('/bin/bash', ['~/disk-space.sh']), (shutil.which('ruby') or '/usr/bin/ruby', ['~/process-count.rb']), (str(swift_probe), [])]
            for number, (host, (executable, arguments)) in enumerate(zip(config['hosts'], definitions), 1):
                host['plugins'] = [f'example-{number}']
                config['plugins'].append(dict(name=f'Example {number}', executable=executable, arguments=arguments, **(dict(source='~/uptime.swift') if number == 3 else {})))
            portable = local/'.aelab/plugins'
            portable.mkdir(parents=True)
            shutil.copy2(ROOT/'Plugins/disk-space.sh', portable/'portable.sh')
            config['plugins'].append(dict(name='Portable probe', executable='/bin/bash', arguments=[str(portable/'portable.sh')]))
            for directory in [local, root/'1', root/'2']:
                (directory/'directory picker'/'nested').mkdir(parents=True)
                (directory/'directory picker'/'private-file.txt').write_text('not a directory')
                (directory/'directory picker'/'loop').symlink_to(directory/'directory picker')
            (home/'config/aelab.json').write_text(json.dumps(config))
            env = dict(os.environ, AELAB_HOME=str(home), AELAB_SSH_CONFIG=str(root/'ssh_config'), TMUX_TMPDIR=str(local), SHELL='/bin/sh', HOME=str(local))
            # Never inherit a parent tmux socket: every fixture owns its socket root.
            env.pop('TMUX', None); env.pop('TMUX_PANE', None)
            local_tmux = shutil.which('tmux')
            if not local_tmux: raise RuntimeError('tmux is required for terminal integration tests')
            # Prestart only the isolated local socket with our fixture config, not user bindings/hooks.
            subprocess.run([local_tmux, '-f', str(local/'.tmux.conf'), 'new-session', '-d', '-s', 'fixture-bootstrap', '/bin/sh'], env=env, check=True, timeout=10)
            cli = ROOT/'.build/debug/aelab'
            if os.environ.get('AELAB_TEST_DAEMON') == '1':
                # Install directly in an owned host home, without any OS service.
                daemon_port = free_port(); endpoint = f'https://localhost:{daemon_port}'
                daemon_home = root/'2/.aelab/daemon'
                daemon_env = dict(env, HOME=str(root/'2'), TMUX_TMPDIR=str(root/'2'))
                installed = subprocess.run([str(ROOT/'.build/debug/aelab-daemon'), 'install', '--home', str(daemon_home), '--prefix', str(root/'2/installed'), '--endpoint', endpoint, '--bind', '127.0.0.1'], env=daemon_env, text=True, capture_output=True, timeout=45)
                assert installed.returncode == 0, installed.stderr
                daemon_log = open(root/'daemon.log', 'w'); logs.append(daemon_log)
                children.append(subprocess.Popen([str(daemon_home/'aelab-daemon'), '--home', str(daemon_home), 'run'], env=daemon_env, stdout=daemon_log, stderr=daemon_log))
                for _ in range(100):
                    try:
                        probe = socket.create_connection(('127.0.0.1', daemon_port), timeout=.2); probe.close(); break
                    except OSError: time.sleep(.05)
                paired = subprocess.run([str(cli), 'daemon', 'pair', 'fixture-2', '--file', str(daemon_home/'pairing.json')], env=env, text=True, capture_output=True, timeout=30)
                assert paired.returncode == 0, paired.stderr
                updated = json.loads((home/'config/aelab.json').read_text())['hosts'][1]
                assert updated['transport'] == 'daemon' and updated['destination'] == 'endpoint-2'
            for number in [1, 2, 3]:
                result = subprocess.run([str(cli), 'status', f'fixture-{number}'], env=env, text=True, capture_output=True, timeout=30)
                assert result.returncode == 0, result.stderr
                observation = json.loads(result.stdout)
                assert observation['host'] == f'fixture-{number}' and observation['reachable']
                if observation.get('platform') == 'macos':
                    assert observation.get('systemd') is None
                    assert observation['launchd']['status'] == 0 and observation['launchd']['output'].startswith('@aelab-domain:')
                    assert not any(item['provider'] == 'systemd' for item in observation['discovered'])
                probe = subprocess.run([str(cli), 'probe', f'fixture-{number}', f'example-{number}'], env=env, text=True, capture_output=True, timeout=30)
                assert probe.returncode == 0, probe.stderr + probe.stdout
                report = json.loads(probe.stdout)
                assert report['host'] == f'fixture-{number}' and report['report']['version'] == 1 and report['report']['summary']
                terminal = subprocess.run([str(cli), 'tty', f'fixture-{number}', '--project', f'project-{number}', '--tool', f'tool-{number}'], env=env, stdin=subprocess.DEVNULL, text=True, capture_output=True, timeout=10)
                assert terminal.returncode == 0 and f'HOST-{number}' in terminal.stdout, terminal.stderr
            if os.environ.get('AELAB_TEST_BOOTSTRAP_ONLY') == '1':
                print('PASS: isolated manual daemon installation/pairing and direct CLI')
                return
            # Feed the same approved fixtures to real browser + WebSocket tests.
            env['AELAB_TEST_CONFIG'] = str(home/'config/aelab.json')
            env['AELAB_TEST_SSH'] = '1'
            env['AELAB_TEST_UID'] = str(os.getuid())
            env['AELAB_TEST_HOSTNAME'] = subprocess.check_output(['uname', '-n'], text=True).strip()
            env['AELAB_TEST_PLATFORM'] = 'macos' if subprocess.check_output(['uname', '-s'], text=True).strip() == 'Darwin' else 'linux'
            env = browser_environment(env)
            subprocess.run(['python3', str(ROOT/'Scripts/smoke.py')], env=env, check=True, timeout=180)
            copied = root/'1/.aelab/plugins/portable/portable.sh'
            assert copied.read_bytes() == (portable/'portable.sh').read_bytes()
            assert copied.stat().st_mode & 0o777 == 0o700
            print('PASS: Manually installed daemon plus SSH/native local transport and browser/PTY integration' if os.environ.get('AELAB_TEST_DAEMON') == '1' else 'PASS: two real SSH endpoints and native local transport, strict host verification, CLI host-context and WebSocket PTY integration')
        finally:
            # Only fixture-owned tmux sockets, never the user's default server.
            tmux = shutil.which('tmux')
            if tmux:
                for directory in [root/'1', root/'2', root/'local']:
                    for socket_path in directory.glob('tmux-*/default'):
                        subprocess.run([tmux, '-S', str(socket_path), 'kill-server'], capture_output=True, timeout=5)
            for child in children:
                stop_process(child, timeout=3)
            for log in logs: log.close()

if __name__ == '__main__': main()
