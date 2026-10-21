#!/usr/bin/env python3
"""Real HTTP/auth/config smoke test against an isolated server; never touches managed hosts."""
import base64
import json
import os
from pathlib import Path
import secrets
import shutil
import uuid
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

from fixtures import ROOT, free_port, create_admin, stop_process
binary = ROOT / '.build/debug/aelab-server'

def main():
    with tempfile.TemporaryDirectory(prefix='aelab-smoke-') as folder:
        home = Path(folder)
        (home / 'config').mkdir(mode=0o700)
        (home / 'state').mkdir(mode=0o700)
        config = json.loads(Path(os.environ['AELAB_TEST_CONFIG']).read_text()) if os.environ.get('AELAB_TEST_CONFIG') else dict(version=1, hosts=[])
        (home / 'config/aelab.json').write_text(json.dumps(config))
        # Explicit fixture configurations may reference private daemon pairings.
        if os.environ.get('AELAB_TEST_CONFIG'):
            source_home = Path(os.environ['AELAB_TEST_CONFIG']).parent.parent
            for host in config['hosts']:
                if host.get('transport') == 'daemon':
                    connection = str(uuid.UUID(host['daemon'])).lower()
                    target = home/'state/daemons'/f'{connection}.json'
                    target.parent.mkdir(mode=0o700, exist_ok=True)
                    shutil.copy2(source_home/'state/daemons'/target.name, target)
        password = create_admin(home)
        port = free_port()
        origin = f'http://localhost:{port}'
        public = home/'public'; shutil.copytree(ROOT/'Frontend/dist', public)
        env = dict(os.environ, AELAB_HOME=folder, AELAB_PORT=str(port), AELAB_ORIGIN=origin, AELAB_PUBLIC=str(public))
        logfile = open(home / 'server.log', 'w')
        server = subprocess.Popen([str(binary)], env=env, stdout=logfile, stderr=logfile)
        cookie = ''
        def request(path, method='GET', payload=None, csrf=None, request_origin=origin, use_cookie=True):
            headers = {'Origin': request_origin}
            if cookie and use_cookie: headers['Cookie'] = cookie
            if csrf: headers['X-CSRF-Token'] = csrf
            data = None if payload is None else json.dumps(payload).encode()
            if data: headers['Content-Type'] = 'application/json'
            req = urllib.request.Request(origin + path, data=data, headers=headers, method=method)
            try:
                response = urllib.request.urlopen(req, timeout=5)
                return response.status, response.read(), response.headers
            except urllib.error.HTTPError as error:
                return error.code, error.read(), error.headers
        try:
            for _ in range(100):
                if server.poll() is not None: raise RuntimeError((home / 'server.log').read_text())
                try:
                    if request('/health')[0] == 200: break
                except (OSError, urllib.error.URLError): time.sleep(.05)
            else: raise RuntimeError('Server did not start')
            # Rebuilding dist must not serve a new UI against the still-running backend.
            index = public/'index.html'; original = index.read_bytes()
            asset = next((public/'assets').glob('*.js')); original_asset = asset.read_bytes()
            try:
                index.write_text('different frontend build'); asset.unlink()
                status, body, _ = request('/')
                assert status == 200 and body == original, (status, body[:300], original[:300])
                assert request('/assets/' + asset.name)[1] == original_asset
            finally:
                index.write_bytes(original); asset.write_bytes(original_asset)
            assert request('/api/config', use_cookie=False)[0] == 401
            assert request('/api/hosts/test/directories', use_cookie=False)[0] == 401
            assert request('/api/hosts/test/plugins/probe/source/deployment?from=local', use_cookie=False)[0] == 401
            assert request('/api/hosts/test/plugins/probe/source/deployment', 'POST', {}, use_cookie=False)[0] == 401
            def api_error(path, method='GET', body=None, token=None, code=None, status=None, **kwargs):
                actual, data, _ = request(path, method, body, token, **kwargs)
                error = json.loads(data)['error']
                assert actual == status and error['code'] == code and error['message'], (actual, error)
            api_error('/api/config', use_cookie=False, status=401, code='authentication_required')
            assert request('/api/config?format=source', use_cookie=False)[0] == 401
            # Upgrade handshake must fail without auth; native HTTP client supplies real WS headers.
            def ws_denied(request_origin, session_cookie=''):
                req = urllib.request.Request(origin + '/ws/terminals/not-a-ticket', headers={'Origin': request_origin, 'Cookie': session_cookie, 'Connection': 'Upgrade', 'Upgrade': 'websocket', 'Sec-WebSocket-Version': '13', 'Sec-WebSocket-Key': base64.b64encode(secrets.token_bytes(16)).decode()})
                try:
                    with urllib.request.urlopen(req, timeout=5) as response: return response.status != 101
                except urllib.error.HTTPError as e: return e.code != 101
            assert request('/api/openapi.json', use_cookie=False)[0] == 401
            assert request('/api/docs', use_cookie=False)[0] == 401
            assert request('/api/state/sections', use_cookie=False)[0] == 401
            assert request('/api/hosts/test/plugins/example/runs', 'POST', {}, use_cookie=False)[0] == 401
            assert request('/api/hosts/test/terminals', use_cookie=False)[0] != 200
            assert request('/api/hosts/test/plugins', use_cookie=False)[0] != 200
            assert request('/api/hosts/test/plugins/example/source', 'PUT', {}, use_cookie=False)[0] != 200
            assert request('/api/hosts/test/tmux/sessions/safe', 'PATCH', {'name': 'new'}, use_cookie=False)[0] != 200
            assert ws_denied(origin)
            assert request('/api/hosts/nope/terminal-tickets', 'POST', {}, use_cookie=False)[0] != 200
            assert request('/api/auth/session', 'POST', {'password': password}, request_origin='https://evil.example')[0] == 403
            status, data, headers = request('/api/auth/session', 'POST', {'password': password})
            assert status == 200, data
            assert 'HttpOnly' in headers['Set-Cookie'] and 'SameSite=Strict' in headers['Set-Cookie']
            cookie = headers['Set-Cookie'].split(';')[0]; csrf = json.loads(data)['csrf']
            assert ws_denied('https://evil.example', cookie)
            status, data, _ = request('/api/config'); assert status == 200
            snapshot = json.loads(data)
            assert request('/api/config', 'PUT', snapshot)[0] == 403
            api_error('/api/config', 'PUT', snapshot, status=403, code='csrf_required')
            api_error('/api/config', 'PUT', snapshot, csrf, status=403, code='origin_rejected', request_origin='https://evil.example')
            api_error('/api/config?format=unknown', status=400, code='invalid_request')
            assert request('/api/auth/session', 'POST', {})[0] == 400
            assert request('/api/config', 'PUT', snapshot, csrf, request_origin='https://evil.example')[0] != 200
            new_config = dict(snapshot['config'], hosts=snapshot['config']['hosts'] + [dict(name='Test', destination='test-host', projects=[], services=[], tools=[], plugins=[])])
            snapshot['config'] = new_config
            assert request('/api/config', 'PUT', snapshot, csrf)[0] == 200
            api_error('/api/config', 'PUT', snapshot, csrf, status=409, code='revision_conflict')
            assert json.loads((home / 'config/aelab.json').read_text()) == new_config
            status, data, _ = request('/api/config'); current = json.loads(data)
            current['config']['hosts'][0]['destination'] = 'host; touch /tmp/evil'
            assert request('/api/config', 'PUT', current, csrf)[0] == 400
            status, data, _ = request('/api/config?format=source'); document = json.loads(data); assert status == 200
            assert document['content'] == (home/'config/aelab.json').read_text()
            assert request('/api/config/validation', 'POST', {'content': document['content']})[0] != 200
            assert request('/api/config/validation', 'POST', {'content': '{bad'}, csrf)[0] != 200
            assert request('/api/config/validation', 'POST', {'content': document['content']}, csrf)[0] == 200
            assert request('/api/config/validation', 'POST', {'content': (ROOT/'Docs/Config/aelab.example.json').read_text()}, csrf)[0] == 200
            edited = dict(document, content=document['content'] + '\n  ')
            assert request('/api/config?format=source', 'PUT', edited, csrf)[0] == 200
            assert request('/api/config?format=source', 'PUT', document, csrf)[0] == 409
            assert (home/'config/aelab.json').read_text() == edited['content']
            assert request('/api/config/state/admin.json')[0] == 404
            assert password not in edited['content'] and 'iterations' not in edited['content']
            assert request('/api/state/sections', 'PUT', {'host': 'test', 'sections': {'projects': False}})[0] != 200
            assert request('/api/state/sections', 'PUT', {'host': 'test', 'sections': {'projects': False}}, csrf)[0] == 200
            assert json.loads(request('/api/state/sections')[1])['test']['projects'] is False
            assert request('/api/state/sections', 'PUT', {'host': '../escape', 'sections': {}}, csrf)[0] != 200
            assert request('/api/hosts/test/tmux/sessions/safe', 'DELETE', {}, request_origin='https://evil.example')[0] != 200
            assert request('/api/hosts/unknown/tmux/sessions/safe', 'DELETE', {}, csrf)[0] != 200
            status, api, _ = request('/api/openapi.json'); api = json.loads(api)
            assert status == 200 and api['openapi'] == '3.1.0'
            assert list(api['paths']) == sorted(api['paths'])
            assert all(list(methods) == sorted(methods) for methods in api['paths'].values())
            assert '/api/hosts/{host}/tmux/sessions/{session}' in api['paths']
            assert api['components']['schemas']['Host']['properties']['projects']
            assert 'host' not in api['components']['schemas']['Tool']['properties']
            assert '/api/hosts/{host}/projects' in api['paths'] and '/api/hosts/{host}/project-directories' not in api['paths']
            for model in ['Host','Project','Service','Tool','Plugin']: assert 'id' not in api['components']['schemas'][model]['properties']
            # Every host route rejects requests before executing any host operation.
            for template, methods in api['paths'].items():
                if not template.startswith('/api/hosts/'):
                    continue
                path = template
                for parameter in ['host', 'plugin', 'service', 'session', 'terminal']:
                    path = path.replace('{' + parameter + '}', 'unauthorized-fixture')
                for method in methods:
                    verb = method.upper()
                    body = None if verb == 'GET' else {}
                    api_error(path, verb, body, use_cookie=False, status=401, code='authentication_required')
                    if verb != 'GET':
                        api_error(path, verb, body, status=403, code='csrf_required')
                        api_error(path, verb, body, csrf, request_origin='https://evil.example', status=403, code='origin_rejected')
            assert request('/api/docs')[0] == 200
            status, palette, headers = request('/theme.css'); assert status == 200 and b'--panel:' in palette
            assert headers['Cache-Control'] == 'no-store'
            if os.environ.get('AELAB_TEST_SSH'):
                # Request fields cannot override an approved executable or its arguments.
                status, report, _ = request('/api/hosts/fixture-1/plugins/example-1/runs', 'POST', {'executable': '/bin/false', 'arguments': ['ignored']}, csrf)
                assert status == 200 and json.loads(report)['report']['summary'].startswith('Root filesystem:')
                deploy_url = '/api/hosts/fixture-1/plugins/portable-probe/source/deployment'
                plan = json.loads(request(deploy_url + '?from=fixture-3')[1])
                local_url = '/api/hosts/fixture-3/plugins/portable-probe/source'
                local_document = json.loads(request(local_url)[1])
                changed = dict(local_document, content=local_document['content'] + '\n# source changed after preview\n')
                status, edited, _ = request(local_url, 'PUT', changed, csrf); assert status == 200
                assert request(deploy_url, 'POST', plan, csrf)[0] == 409
                restored = dict(json.loads(edited), content=local_document['content'])
                assert request(local_url, 'PUT', restored, csrf)[0] == 200
                plan = json.loads(request(deploy_url + '?from=fixture-3')[1])
                current_config = json.loads(request('/api/config')[1])
                current_config['config']['hosts'][-1]['name'] += ' updated'
                assert request('/api/config', 'PUT', current_config, csrf)[0] == 200
                assert request(deploy_url, 'POST', plan, csrf)[0] == 409
                target = Path(plan['targetPath'])
                # Only fixture-owned paths: reject a symlink target without reading/copying its contents.
                assert 'aelab-ssh-' in str(target) and target.parent.name == 'portable' and target.parent.parent.name == 'plugins'
                target.parent.mkdir(parents=True, mode=0o700)
                target.symlink_to(config['hosts'][0]['projects'][0]['directory'] + '/disk-space.sh')
                try: assert request(deploy_url + '?from=fixture-3')[0] == 400
                finally:
                    target.unlink()
                    target.parent.rmdir()
                    target.parent.parent.rmdir()

            assert request('/api/hosts/test/plugins/example/runs', 'GET')[0] != 200
            assert request('/api/hosts/test/plugins/example/runs', 'POST', {})[0] == 403
            assert request('/api/hosts/test/plugins/example/runs', 'POST', {}, csrf, request_origin='https://evil.example')[0] == 403
            assert request('/api/hosts/unknown/plugins/example/runs', 'POST', {}, csrf)[0] != 200
            assert request('/api/hosts/test/plugins/example/runs', 'POST', {}, csrf)[0] != 200
            assert request('/api/hosts/test/tmux/sessions/safe', 'PATCH', {'name': 'new'})[0] != 200
            assert request('/api/hosts/test/tmux/sessions/safe', 'PATCH', {'name': 'bad:target'}, csrf)[0] != 200
            assert request('/api/hosts/test/terminal-tickets', 'POST', {'pinned': 'unknown'}, csrf)[0] != 200
            assert request('/api/hosts/test/terminals/unknown', 'DELETE', {}, csrf)[0] != 200
            assert request('/api/hosts/test/plugins/example/source', 'PUT', {})[0] != 200
            assert request('/api/hosts/test/plugins/example/source', 'PUT', {}, csrf, request_origin='https://evil.example')[0] != 200
            assert request('/api/hosts/unknown/plugins')[0] != 200
            assert request('/api/hosts/test/projects', 'POST', {})[0] != 200
            assert request('/api/hosts/unknown/status')[0] != 200
            assert request('/api/hosts/test/services/unknown/actions', 'POST', {'action': 'restart'}, csrf)[0] != 200
            status, data, _ = request('/hosts/test/projects/aelab/')
            assert status == 200 and b'<div id="app">' in data

            assert request('/api/hosts/test/services/unknown/actions', 'POST', {'action':'destroy'}, csrf)[0] == 400
            assert request('/api/hosts/test/terminal-tickets', 'POST', {'host':'another-host'}, csrf)[0] == 400
            assert request('/api/hosts/test/tmux/sessions/safe/windows', 'POST', {'session':'another-session'}, csrf)[0] == 400
            for obsolete in ['/api/login', '/api/logout', '/api/session', '/api/config/file', '/api/hosts/test/plugin-sources', '/api/hosts/test/tools/discovery', '/api/hosts/test/project-directories']:
                assert request(obsolete)[0] == 404
            assert request('/api/hosts/test/directories?path=relative')[0] == 400
            assert request('/api/hosts/unknown/directories')[0] == 400
            assert request('/api/hosts/test/plugins/probe/source/deployment', 'POST', {})[0] == 403
            assert request('/api/hosts/test/plugins/probe/source/deployment', 'POST', {}, csrf, request_origin='https://evil.example')[0] == 403
            assert request('/api/nonexistent')[0] == 404
            assert request('/api/auth/session', 'DELETE', {}, csrf)[0] == 200
            assert request('/api/config')[0] == 401
            audit = (home / 'state/audit.log').read_text()
            assert password not in audit and 'saved' in audit
            if os.environ.get('AELAB_TEST_BROWSER') or os.environ.get('AELAB_TEST_SSH'):
                browser_env = dict(env, AELAB_TEST_ORIGIN=origin, AELAB_TEST_PASSWORD=password, AELAB_TEST_SERVER_PID=str(server.pid), AELAB_TEST_SERVER_BINARY=str(binary))
                subprocess.run(['node', str(ROOT / 'Scripts/browser-smoke.mjs')], env=browser_env, check=True, timeout=120)
            print('PASS: isolated server startup/static deep links/auth/origin/CSRF/config persistence/conflicts/host scoping/logout/audit')
        finally:
            stop_process(server, timeout=5)
            logfile.close()

if __name__ == '__main__': main()
