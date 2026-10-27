#!/usr/bin/env python3
"""Real daemon startup through both repository and installed CLIs; no OS services."""
import json
import os
import shutil
import subprocess
import tempfile
import time
import uuid

from fixtures import ROOT, free_port, stop_process, Wire
BIN = ROOT/'.build'/os.environ.get('AELAB_TEST_CONFIGURATION', 'debug')


def main():
    with tempfile.TemporaryDirectory(prefix='ae-daemon-launch-', dir='/tmp') as temporary:
        from pathlib import Path
        root = Path(temporary); repo = root/'checkout'; (repo/'Scripts').mkdir(parents=True)
        build = repo/'.build/release'; build.mkdir(parents=True)
        shutil.copy2(ROOT/'.ae', repo/'.ae')
        for name in ['aelab-cli', 'aelab-server', 'aelab-daemon']:
            shutil.copy2(BIN/name, build/name)
        (repo/'Scripts/generate-api.py').write_text('# Fixture has no HTTP API.\n')
        (repo/'Tools').mkdir()
        (repo/'Tools/build-frontend.py').write_text('# Recorded build fixture already contains frontend assets.\n')
        (repo/'Frontend/dist').mkdir(parents=True)
        (repo/'Frontend/dist/index.html').write_text('fixture dashboard')
        fake = root/'commands'; fake.mkdir()
        for name in ['swift', 'npm']:
            path = fake/name
            path.write_text('#!/bin/sh\nprintf "%s|%s\\n" "${0##*/}" "$*" >> "$AELAB_BUILD_LOG"\n')
            path.chmod(0o700)
        home = root/'private daemon'; prefix = root/'installed'; central = root/'unused-central'
        env = dict(os.environ, AELAB_HOME=str(central), PATH=str(fake)+':'+os.environ['PATH'], AELAB_BUILD_LOG=str(root/'build.log'))
        endpoint = f'https://aelab-fixture.invalid:{free_port()}'
        def cli(*args, success=True):
            result = subprocess.run([str(repo/'.ae'), *args], cwd=root, env=env, text=True, capture_output=True, timeout=30)
            assert (result.returncode == 0) == success, result.stderr + result.stdout
            return result
        cli('daemon', '--home', str(home), success=False)
        assert not home.exists() and not central.exists()
        for attempt in range(2):
            command = [str(repo/'.ae'), 'daemon', '--home', str(home)] if attempt == 0 else [str(prefix/'bin/aelab'), 'daemon', '--home', str(home)]
            if attempt == 0: command += ['--endpoint', endpoint, '--bind', '127.0.0.1']
            log = open(root/f'daemon-{attempt}.log', 'w')
            process = subprocess.Popen(command, cwd=root, stdout=log, stderr=log, env=env)
            try:
                ready = False
                for _ in range(150):
                    if process.poll() is not None: break
                    try:
                        pairing = json.loads((home/'pairing.json').read_text())
                        wire = Wire(pairing, hostname='aelab-fixture.invalid'); wire.close(); ready = True; break
                    except (OSError, json.JSONDecodeError): time.sleep(.1)
                assert ready, (root/f'daemon-{attempt}.log').read_text()
                preserved = {p:p.read_bytes() for p in [home/'daemon.json', home/'pairing.json', home/'certificate.pem', home/'key.pem']}
                duplicate = subprocess.run([str(repo/'.ae'), 'daemon', '--home', str(home)] if attempt == 0 else command, cwd=root, env=env, capture_output=True, timeout=30)
                assert duplicate.returncode != 0 and process.poll() is None
                wire = Wire(pairing, hostname='aelab-fixture.invalid')
                wire.send(dict(id=str(uuid.uuid4()), operation='execute', script='printf alive', timeout=5))
                assert wire.receive()['result']['output'] == 'alive'; wire.close()
                assert (home/'key.pem').stat().st_mode & 0o077 == 0
                for file, content in preserved.items(): assert file.read_bytes() == content
                assert not central.exists()
                if attempt == 0:
                    cli('daemon', 'pairing', '--home', str(home), '--output', 'pairing-export.json')
                    assert json.loads((root/'pairing-export.json').read_text()) == pairing
                    assert (root/'pairing-export.json').stat().st_mode & 0o077 == 0
                    assert all(line in ['swift|build -c release --product aelab-cli', 'swift|build -c release --product aelab-daemon'] for line in (root/'build.log').read_text().splitlines())
            finally:
                stop_process(process, timeout=12); log.close()
            if attempt == 0:
                cli('daemon', '--home', str(home), '--endpoint', 'https://different.invalid:1984', success=False)
                cli('daemon', '--home', str(home), '--bind', '0.0.0.0', success=False)
                cli('install', '--prefix', str(prefix))
                for name in ['aelab', 'aelab-cli', 'aelab-server', 'aelab-daemon']: assert (prefix/'bin'/name).is_file()
                for file, content in preserved.items(): assert file.read_bytes() == content
                try: wire = Wire(pairing, hostname='aelab-fixture.invalid'); wire.close()
                except OSError: pass
                else: raise AssertionError('Installation started a daemon')
                # Installed operation survives moving the checkout away.
                repo.rename(root/'moved-checkout')
        print('PASS: daemon-only builds without Node, explicit first setup, private pairing export, duplicate-start refusal, endpoint/bind preservation, all-target install without startup and installed TLS operation without checkout')


if __name__ == '__main__': main()
