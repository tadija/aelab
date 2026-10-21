#!/usr/bin/env python3
"""On-host installation with real daemon binaries and recorded builds; no OS services."""
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import time
import uuid

from fixtures import ROOT, free_port, stop_process, Wire
BIN = ROOT/'.build'/os.environ.get('AELAB_TEST_CONFIGURATION', 'debug')

def main():
    with tempfile.TemporaryDirectory(prefix='ae-install-', dir='/tmp') as temporary:
        root = Path(temporary); repo = root/'checkout'; (repo/'Scripts').mkdir(parents=True)
        build = repo/'.build/release'; build.mkdir(parents=True)
        shutil.copy2(ROOT/'.ae', repo/'.ae')
        shutil.copy2(BIN/'aelab-daemon', build/'aelab-daemon')
        fake = root/'commands'; fake.mkdir(); swift = fake/'swift'
        swift.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$AELAB_BUILD_LOG"\n'); swift.chmod(0o700)
        home = root/'private home'; prefix = root/'installed'; command = prefix/'bin/aelab-daemon'
        env = dict(os.environ, HOME=str(root/'user'), AELAB_HOME=str(root/'user/.aelab'), PATH=str(fake)+':'+os.environ['PATH'], AELAB_BUILD_LOG=str(root/'build.log'))
        endpoint = f'https://aelab-fixture.invalid:{free_port()}'
        def install(*args, success=True):
            result = subprocess.run([str(repo/'.ae'), 'daemon-install', '--home', str(home), '--prefix', str(prefix), *args], env=env, text=True, capture_output=True, timeout=180)
            assert (result.returncode == 0) == success, result.stderr + result.stdout
            return result
        install(success=False); assert not home.exists()
        command.parent.mkdir(parents=True); command.write_text('unrelated executable')
        install('--endpoint', endpoint, success=False); assert command.read_text() == 'unrelated executable' and not home.exists()
        command.unlink()
        install('--endpoint', endpoint, '--bind', '127.0.0.1')
        assert command.is_symlink() and command.resolve().is_file()
        pairing = json.loads((home/'pairing.json').read_text())
        preserved = {p:p.read_bytes() for p in [home/'daemon.json', home/'pairing.json', home/'certificate.pem', home/'key.pem']}
        # Installation is independent of both the checkout and the central dashboard.
        moved = root/'moved'; repo.rename(moved)
        subprocess.run([str(command), 'help'], check=True, capture_output=True, timeout=10)
        moved.rename(repo)
        install()
        launcher = home/'aelab-daemon'
        original_bytes = launcher.read_bytes(); launcher.unlink()
        sentinel = root/'unrelated'; sentinel.write_bytes(b'keep me')
        launcher.symlink_to(sentinel)
        install(success=False); assert sentinel.read_bytes() == b'keep me'
        launcher.unlink(); launcher.write_bytes(original_bytes); launcher.chmod(0o700)
        install('--endpoint', 'https://different.invalid:1984', success=False)
        install('--bind', '0.0.0.0', success=False)
        original = hashlib.sha256((build/'aelab-daemon').read_bytes()).hexdigest()
        candidate = build/'aelab-daemon'
        if platform.system() == 'Darwin':
            subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', '--identifier', 'dev.aelab.install-fixture-'+str(uuid.uuid4()), str(candidate)], check=True, capture_output=True, timeout=15)
        else:
            with candidate.open('ab') as file: file.write(os.urandom(32))
        updated = hashlib.sha256(candidate.read_bytes()).hexdigest(); assert updated != original
        log = open(root/'daemon.log', 'w')
        daemon = subprocess.Popen([str(command), '--home', str(home), 'run'], stdout=log, stderr=log, env=env)
        try:
            for _ in range(100):
                try: wire = Wire(pairing, hostname='aelab-fixture.invalid'); wire.close(); break
                except OSError: time.sleep(.1)
            # Installation never replaces a running daemon or stops it on the user's behalf.
            refused = install(success=False)
            assert 'stop it before installing' in refused.stderr and daemon.poll() is None
            assert hashlib.sha256(launcher.read_bytes()).hexdigest() == original
            duplicate = subprocess.run([str(command), '--home', str(home), 'run'], env=env, capture_output=True, timeout=10)
            assert duplicate.returncode != 0
            wire = Wire(pairing, hostname='aelab-fixture.invalid')
            wire.send(dict(id=str(uuid.uuid4()), operation='execute', script='printf alive', timeout=5))
            assert wire.receive()['result']['output'] == 'alive'; wire.close()
            for file, content in preserved.items(): assert file.read_bytes() == content
            assert (home/'key.pem').stat().st_mode & 0o077 == 0
            assert all('--product aelab-daemon' in line and '-c release' in line for line in (root/'build.log').read_text().splitlines())
            assert not list((root/'user/Library').glob('**/*.plist')) and not list((root/'user/.config').glob('**/*.service'))
        finally:
            stop_process(daemon, timeout=12)
            log.close()
            assert daemon.returncode in [0, -15], (root/'daemon.log').read_text()
        install()
        assert hashlib.sha256(launcher.read_bytes()).hexdigest() == updated
        for file, content in preserved.items(): assert file.read_bytes() == content
        assert not list(home.glob('.install-*')) and not (home/'releases').exists()
        try:
            wire = Wire(pairing, hostname='aelab-fixture.invalid'); wire.close()
        except OSError: pass
        else: raise AssertionError('Installation unexpectedly started a daemon')
        print('PASS: daemon-only local build/install, checkout independence, executable/symlink collision refusal, run lock, explicit stop requirement, stopped replacement and unchanged credentials')

if __name__ == '__main__': main()
