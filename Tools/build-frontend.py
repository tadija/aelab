#!/usr/bin/env python3
"""Reuse matching frontend dependencies and verified build output; --clean rebuilds both."""
import argparse
import hashlib
import fcntl
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FRONTEND = ROOT/'Frontend'
CACHE = FRONTEND/'node_modules/.cache/aelab'


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=True).encode()).hexdigest()


def tree_digest(root, excluded=()):
    digest = hashlib.sha256()
    seen = set()
    for directory, folders, files in os.walk(root, followlinks=True):
        digest.update(str(Path(directory).relative_to(root)).encode()+b'\0')
        real = os.path.realpath(directory)
        if real in seen:
            folders[:] = []; continue
        seen.add(real)
        folders[:] = sorted(name for name in folders if name not in excluded)
        for name in sorted(files):
            if name in excluded or name == '.DS_Store': continue
            path = Path(directory)/name
            digest.update(str(path.relative_to(root)).encode()+b'\0')
            with path.open('rb') as source:
                while chunk := source.read(1024 * 1024): digest.update(chunk)
            digest.update(b'\0')
    return digest.hexdigest()


def read_stamp(path):
    try: return json.loads(path.read_text())
    except (OSError, ValueError): return None


def write_stamp(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as file:
        temporary = Path(file.name)
        json.dump(value, file, sort_keys=True)
    try: temporary.replace(path)
    finally: temporary.unlink(missing_ok=True)


def tool_version(tool):
    return subprocess.check_output([tool, '--version'], cwd=ROOT, text=True).strip()


def run(*arguments):
    subprocess.run(arguments, cwd=ROOT, check=True)


def build():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--configuration', choices=['debug', 'release'], default='release')
    parser.add_argument('--clean', action='store_true')
    args = parser.parse_args()
    configs = [ROOT/'.npmrc', FRONTEND/'.npmrc', Path(os.environ.get('npm_config_userconfig') or os.environ.get('NPM_CONFIG_USERCONFIG') or Path.home()/'.npmrc')]
    dependency_key = fingerprint(dict(
        package=(FRONTEND/'package.json').read_text(), lock=(FRONTEND/'package-lock.json').read_text(),
        node=tool_version('node'), npm=tool_version('npm'), platform=platform.system(), architecture=platform.machine(),
        npmrc=[path.read_text() if path.is_file() else None for path in configs],
        environment={key: value for key, value in os.environ.items() if key.lower().startswith('npm_config_') or key in ['NODE_ENV', 'NODE_OPTIONS']}
    ))
    dependency_stamp = CACHE/'dependencies.json'
    tools = [FRONTEND/'node_modules/.bin'/name for name in ['vite', 'svelte-check', 'tsc']]
    install = args.clean or read_stamp(dependency_stamp) != dependency_key or not all(path.is_file() and os.access(path, os.X_OK) for path in tools)
    if install:
        dependency_stamp.unlink(missing_ok=True)
        run('npm', 'ci', '--include=dev', '--prefix', 'Frontend')
        if not all(path.is_file() and os.access(path, os.X_OK) for path in tools): raise SystemExit('Frontend dependency installation is incomplete')
        write_stamp(dependency_stamp, dependency_key)
    else: print('Frontend dependencies unchanged; reusing node_modules.', flush=True)
    build_key = fingerprint(dict(
        dependencies=dependency_key, configuration=args.configuration, root=str(ROOT),
        sources=tree_digest(FRONTEND, excluded=['node_modules', 'dist', '.git', '.svelte-kit']),
        environment={key: value for key, value in os.environ.items() if key.startswith('VITE_') or key in ['NODE_ENV', 'NODE_OPTIONS']},
        helper=Path(__file__).read_text()
    ))
    build_stamp = CACHE/'frontend.json'
    previous = read_stamp(build_stamp)
    assets = FRONTEND/'dist'
    if not install and isinstance(previous, dict) and previous.get('inputs') == build_key and (assets/'index.html').is_file() and previous.get('output') == tree_digest(assets):
        print('Frontend sources unchanged; reusing dist.', flush=True)
        return
    build_stamp.unlink(missing_ok=True)
    arguments = ['npm', 'run', 'build', '--prefix', 'Frontend']
    if args.configuration == 'debug': arguments += ['--', '--mode', 'development', '--sourcemap']
    run(*arguments)
    if not (assets/'index.html').is_file(): raise SystemExit('Frontend build did not produce index.html')
    write_stamp(build_stamp, dict(inputs=build_key, output=tree_digest(assets)))


def main():
    lock_path = ROOT/'.swiftpm/aelab-frontend.lock'
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        build()


if __name__ == '__main__':
    try: main()
    except subprocess.CalledProcessError as error: raise SystemExit(error.returncode if error.returncode >= 0 else 128 - error.returncode)
    except OSError as error: raise SystemExit('Frontend build failed: ' + str(error))
