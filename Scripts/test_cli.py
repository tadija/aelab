"""CLI help, command routing and rejection of removed spellings in isolated homes."""
import json
import os
import pty
import select
import time
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / '.build' / os.environ.get('AELAB_TEST_CONFIGURATION', 'debug') / 'aelab'


class CLICommandsTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='aelab-cli-')
        self.addCleanup(self.directory.cleanup)
        self.home = Path(self.directory.name) / 'runtime'
        self.env = dict(os.environ, AELAB_HOME=str(self.home))

    def cli(self, *args, success=True):
        result = subprocess.run([str(BINARY), *args], env=self.env, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def test_help_never_initializes_runtime_or_starts_commands(self):
        overview = self.cli().stdout
        self.assertEqual(overview, self.cli('--help').stdout)
        self.assertEqual(overview, self.cli('help').stdout)
        for command in ['server', 'daemon', 'tty', 'hosts', 'status', 'services', 'tmux', 'tools',
                        'plugins', 'probe', 'doctor', 'service', 'pairing', 'pair',
                        'init', 'bootstrap', 'reset', 'config', 'install', 'cleanup']:
            with self.subTest(command=command):
                help_text = self.cli('help', command).stdout
                self.assertEqual(help_text, self.cli(command, '--help').stdout)
                self.assertIn('Usage: aelab ' + command, help_text)
        self.cli('service', 'restart', 'local', 'web', '--help')
        self.cli('help', 'unknown', success=False)
        self.assertFalse(self.home.exists())

    def test_removed_commands_are_rejected_without_runtime_setup(self):
        for args in [('sessions', 'local'), ('ssh-candidates',), ('admin', 'bootstrap'), ('admin', 'reset'),
                     ('daemon', 'pairing', '--output', 'file.json'),
                     ('daemon', 'pair', 'host', '--file', 'file.json'),
                     *[(action, 'local', 'web') for action in ['service-status', 'logs', 'start', 'stop', 'restart']]]:
            with self.subTest(args=args):
                self.cli(*args, success=False)
        self.assertFalse(self.home.exists())

    def test_service_actions_reach_configured_service_lookup(self):
        self.cli('init')
        config = json.loads((self.home / 'config/aelab.json').read_text())
        host = config['hosts'][0]['name'].lower()
        for action in ['status', 'logs', 'start', 'stop', 'restart']:
            with self.subTest(action=action):
                result = self.cli('service', action, host, 'missing', success=False)
                self.assertIn('Unknown curated service', result.stderr)
        result = self.cli('service', 'invalid', host, 'missing', success=False)
        self.assertIn('Use service', result.stderr)

    def test_bootstrap_and_reset_update_credentials_interactively(self):
        def enter_password(command, password):
            master, slave = pty.openpty()
            process = subprocess.Popen([str(BINARY), command], env=self.env, stdin=slave,
                                       stdout=slave, stderr=slave, start_new_session=True)
            os.close(slave)
            output = b''; entered = False; deadline = time.monotonic() + 10
            try:
                while process.poll() is None and time.monotonic() < deadline:
                    if select.select([master], [], [], .1)[0]:
                        try:
                            chunk = os.read(master, 65536)
                        except OSError:
                            break
                        if not chunk: break
                        output += chunk
                        if not entered and b'Administrator password' in output:
                            os.write(master, password.encode() + b'\n'); entered = True
                self.assertEqual(process.wait(timeout=2), 0, output.decode(errors='replace'))
                self.assertTrue(entered)
            finally:
                if process.poll() is None: process.kill(); process.wait()
                os.close(master)
        enter_password('bootstrap', 'fixture-initial-password')
        credentials = self.home / 'state/admin.json'
        first = credentials.read_bytes()
        enter_password('reset', 'fixture-replacement-password')
        self.assertNotEqual(credentials.read_bytes(), first)

    def test_invalid_pairing_options_do_not_create_runtime_files(self):
        for args in [(), ('--output',), ('--output', ''), ('--unknown', 'value'),
                     ('--output', 'a', '--output', 'b')]:
            self.assertIn('Use pairing', self.cli('pairing', *args, success=False).stderr)
        self.assertFalse(self.home.exists())


if __name__ == '__main__':
    unittest.main()
