"""Validate repository delegation without compiling, opening ports or touching services."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RepositoryLauncherTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='aelab-launcher-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.repo = self.root/'checkout with spaces'
        self.repo.mkdir()
        shutil.copy2(ROOT/'.ae', self.repo/'.ae')
        shutil.copy2(ROOT/'VERSION', self.repo/'VERSION')
        (self.repo/'Tools').mkdir()
        shutil.copy2(ROOT/'Tools/build-frontend.py', self.repo/'Tools/build-frontend.py')
        shutil.copy2(ROOT/'Tools/build-metadata.sh', self.repo/'Tools/build-metadata.sh')
        (self.repo/'BUILD').write_text('0123456789abcdef0123456789abcdef01234567\n')
        (self.repo/'Scripts').mkdir()
        (self.repo/'Scripts/generate-api.py').write_text('')
        (self.repo/'Frontend/src').mkdir(parents=True)
        (self.repo/'Frontend/package.json').write_text('{"name":"fixture","private":true}')
        (self.repo/'Frontend/package-lock.json').write_text('{"lockfileVersion":3}')
        (self.repo/'Frontend/src/example.ts').write_text('export const example = 1;')
        for configuration in ['debug', 'release']:
            binary = self.repo/f'.build/{configuration}/aelab-cli'
            binary.parent.mkdir(parents=True)
            binary.write_text('#!/usr/bin/env python3\nimport json,os,sys\nprint(json.dumps(dict(args=sys.argv[1:],cwd=os.getcwd())))\n')
            binary.chmod(0o755)
        commands = self.root/'commands'; commands.mkdir()
        for name in ['swift', 'npm']:
            file = commands/name
            file.write_text("#!/usr/bin/env python3\nimport os,sys\nfrom pathlib import Path\nname=Path(sys.argv[0]).name\nargs=sys.argv[1:]\nif args == ['--version']:\n print(os.environ.get('FIXTURE_NPM_VERSION', 'fixture-'+name)); sys.exit(0)\nwith open(os.environ['BUILD_LOG'],'a') as log: log.write(name+'|'+' '.join(args)+'\\n')\nif name == 'npm' and os.environ.get('FAIL_NPM_STEP') == args[0]: sys.exit(2)\nif name == 'npm' and args[0] == 'ci':\n directory=Path('Frontend/node_modules/.bin'); directory.mkdir(parents=True,exist_ok=True)\n for tool in ['vite','svelte-check','tsc']:\n  (directory/tool).write_text('fixture'); (directory/tool).chmod(0o755)\nif name == 'npm' and args[0] == 'run':\n directory=Path('Frontend/dist'); directory.mkdir(parents=True,exist_ok=True)\n (directory/'index.html').write_text('fixture dashboard')\n (directory/'app.js').write_text('fixture bundle')\n")
            file.chmod(0o755)
        self.log = self.root/'build.log'
        self.env = dict(os.environ, PATH=str(commands)+':'+os.environ['PATH'], BUILD_LOG=str(self.log))

    def launch(self, *arguments, success=True):
        result = subprocess.run([str(self.repo/'.ae'), *arguments], cwd=self.root, env=self.env, text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode == 0, success, result.stderr)
        return json.loads(result.stdout.splitlines()[-1]) if success else None

    def test_service_and_configuration_flags_keep_caller_relative_paths(self):
        for role in ['server', 'daemon']:
            result = self.launch(role, '--service', '--configuration', 'debug', '--home', 'private home')
            self.assertEqual(result, dict(args=[role, '--service', '--home', 'private home'], cwd=str(self.root)))
        lines = self.log.read_text().splitlines()
        self.assertEqual(lines[-2:], ['swift|build -c debug --product aelab-cli', 'swift|build -c debug --product aelab-daemon'])
        self.assertEqual(sum(line.startswith('npm|') for line in lines), 2)
        result = self.launch('--home', 'relative home', 'server', '--port', '1234', '--service')
        self.assertEqual(result['args'], ['server', '--home', 'relative home', '--port', '1234', '--service'])

    def commands(self):
        return self.log.read_text().splitlines()

    def test_repeated_install_reuses_dependencies_and_frontend_output(self):
        self.launch('install')
        before = self.commands()
        self.launch('install')
        self.assertEqual(self.commands()[len(before):], ['swift|build -c release'])
        (self.repo/'Frontend/src/example.ts').write_text('export const example = 2;')
        before = self.commands(); self.launch('install')
        self.assertEqual(self.commands()[len(before):], ['swift|build -c release', 'npm|run build --prefix Frontend'])
        (self.repo/'Frontend/dist/app.js').unlink()
        before = self.commands(); self.launch('install')
        self.assertEqual(self.commands()[len(before):], ['swift|build -c release', 'npm|run build --prefix Frontend'])
        (self.repo/'Frontend/package-lock.json').write_text('{"lockfileVersion":3,"changed":true}')
        before = self.commands(); self.launch('install')
        self.assertEqual(self.commands()[len(before):], ['swift|build -c release', 'npm|ci --include=dev --prefix Frontend', 'npm|run build --prefix Frontend'])

    def test_clean_forces_both_builds_and_is_not_forwarded_to_the_cli(self):
        self.launch('install')
        before = self.commands()
        result = self.launch('install', '--clean', '--prefix', 'local prefix')
        self.assertEqual(result['args'], ['install', '--source', str(self.repo), '--prefix', 'local prefix'])
        self.assertEqual(self.commands()[len(before):], ['swift|package clean', 'swift|build -c release', 'npm|ci --include=dev --prefix Frontend', 'npm|run build --prefix Frontend'])
        before = self.commands(); self.launch('daemon', '--clean', '--service')
        self.assertEqual(self.commands()[len(before):], ['swift|package clean', 'swift|build -c release --product aelab-cli', 'swift|build -c release --product aelab-daemon'])

    def test_cache_tracks_mode_environment_and_missing_tools(self):
        self.launch('server', '--configuration', 'debug')
        before = self.commands(); self.launch('install')
        self.assertEqual(self.commands()[len(before):], ['swift|build -c release', 'npm|run build --prefix Frontend'])
        self.env['VITE_TEST_VALUE'] = 'changed'
        before = self.commands(); self.launch('install')
        self.assertEqual(self.commands()[len(before):], ['swift|build -c release', 'npm|run build --prefix Frontend'])
        (self.repo/'Frontend/node_modules/.bin/vite').unlink()
        before = self.commands(); self.launch('install')
        self.assertIn('npm|ci --include=dev --prefix Frontend', self.commands()[len(before):])
        (self.repo/'Frontend/node_modules/.cache/aelab/frontend.json').write_text('[]')
        before = self.commands(); self.launch('install')
        self.assertIn('npm|run build --prefix Frontend', self.commands()[len(before):])

    def test_failed_steps_never_publish_valid_cache_entries(self):
        self.launch('install')
        (self.repo/'Frontend/src/example.ts').write_text('export const example = 3;')
        self.env['FAIL_NPM_STEP'] = 'run'
        self.launch('install', success=False)
        self.assertFalse((self.repo/'Frontend/node_modules/.cache/aelab/frontend.json').exists())
        del self.env['FAIL_NPM_STEP']
        before = self.commands(); self.launch('install')
        self.assertEqual(self.commands()[len(before):], ['swift|build -c release', 'npm|run build --prefix Frontend'])
        self.env['FIXTURE_NPM_VERSION'] = 'changed-toolchain'
        self.env['FAIL_NPM_STEP'] = 'ci'
        self.launch('install', success=False)
        self.assertFalse((self.repo/'Frontend/node_modules/.cache/aelab/dependencies.json').exists())
        del self.env['FAIL_NPM_STEP']
        before = self.commands(); self.launch('install')
        self.assertEqual(self.commands()[len(before):], ['swift|build -c release', 'npm|ci --include=dev --prefix Frontend', 'npm|run build --prefix Frontend'])

    def test_version_needs_no_build_or_compiled_cli(self):
        shutil.rmtree(self.repo/'.build')
        result = subprocess.run([str(self.repo/'.ae'), '--version'], cwd=self.root, env=self.env, text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), (ROOT/'VERSION').read_text().strip()+' (0123456)')
        result = subprocess.run([str(self.repo/'.ae'), '--build'], cwd=self.root, env=self.env, text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), (self.repo/'BUILD').read_text().strip())
        self.assertFalse(self.log.exists())

    def test_invalid_options_fail_before_building_or_starting(self):
        for args in [('server', '--unknown', 'value'), ('server', '--port', '0'), ('server', '--port', '65536'), ('server', '--configuration', 'fast'), ('daemon', '--port', '1984'), ('daemon', '--service', '--service'), ('install', '--service'), ('server', '--home', '--service'), ('install', '--clean', '--clean'), ('server', '--clean', '--port', 'invalid')]:
            self.launch(*args, success=False)
        self.assertFalse(self.log.exists())

    def test_pairing_delegates_to_the_cli_and_install_starts_nothing_itself(self):
        result = self.launch('daemon', 'pairing', '--home', 'private home', '--output', 'pairing.json')
        self.assertEqual(result['args'], ['daemon', 'pairing', '--home', 'private home', '--output', 'pairing.json'])
        result = self.launch('daemon', 'pair', 'host', '--file', 'pairing.json')
        self.assertEqual(result['args'], ['daemon', 'pair', 'host', '--file', 'pairing.json'])
        result = self.launch('install', '--prefix', 'local prefix')
        self.assertEqual(result['args'], ['install', '--source', str(self.repo), '--prefix', 'local prefix'])


if __name__ == '__main__': unittest.main()
