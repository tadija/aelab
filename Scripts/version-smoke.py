#!/usr/bin/env python3
"""Embedded version/build identity, changing Git HEADs, worktrees and source archives."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from fixtures import ROOT


def git(root, *arguments):
    return subprocess.check_output(['git', '-C', str(root), '-c', 'user.name=Build fixture', '-c', 'user.email=fixture@example.invalid', '-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgsign=false', *arguments], text=True, stderr=subprocess.PIPE).strip()


def main():
    version = (ROOT/'VERSION').read_text().strip()
    revision = git(ROOT, 'rev-parse', 'HEAD')
    binaries = ROOT/'.build'/os.environ.get('AELAB_TEST_CONFIGURATION', 'debug')
    with tempfile.TemporaryDirectory(prefix='aelab-version-', dir='/tmp') as directory:
        root = Path(directory); home = root/'uninitialized'
        env = dict(os.environ, AELAB_HOME=str(home), AELAB_PORT='invalid', AELAB_ORIGIN='invalid', AELAB_PUBLIC=str(root/'missing-assets'))
        for name in ['aelab-cli', 'aelab-server', 'aelab-daemon']: shutil.copy2(binaries/name, root/name)
        (root/'aelab').symlink_to('aelab-cli')
        for command in [[str(ROOT/'.ae')], *[[str(root/name)] for name in ['aelab', 'aelab-cli', 'aelab-server', 'aelab-daemon']]]:
            for flag, expected in [('--version', f'{version} ({revision[:7]})'), ('--build', revision)]:
                result = subprocess.run([*command, flag], cwd=root, env=env, text=True, capture_output=True, timeout=10)
                assert result.returncode == 0 and result.stdout == expected+'\n', result.stderr+result.stdout
        assert not home.exists(), 'Metadata queries must not initialize runtime state'
        fixture = root/'fixture'; fixture.mkdir()
        for path in ['Plugins/BuildVersion', 'Tools']:
            shutil.copytree(ROOT/path, fixture/path)
        (fixture/'Sources/Core').mkdir(parents=True)
        (fixture/'Sources/Core/Empty.swift').write_text('public enum Empty {}\n')
        (fixture/'Sources/Example').mkdir()
        (fixture/'Sources/Example/main.swift').write_text('import Core\nprint(CommandLine.arguments.contains("--build") ? AelabVersion.build : AelabVersion.display)\n')
        (fixture/'Package.swift').write_text('''// swift-tools-version: 6.4
import PackageDescription
let package = Package(name: "VersionFixture", targets: [
    .plugin(name: "BuildVersion", capability: .buildTool()),
    .target(name: "Core", plugins: [.plugin(name: "BuildVersion")]),
    .executableTarget(name: "Example", dependencies: ["Core"])
])
''')
        (fixture/'VERSION').write_text('1.2.3\n')
        (fixture/'.gitignore').write_text('.build/\nBUILD\nsource-archive/\n')
        def build(package, value, identity, error=None):
            result = subprocess.run(['swift', 'build', '--package-path', str(package), '--product', 'Example'], capture_output=True, text=True, timeout=120)
            assert (result.returncode == 0) == (error is None), result.stdout+result.stderr
            if error:
                assert error in result.stdout+result.stderr
            else:
                command = str(package/'.build/debug/Example')
                assert subprocess.check_output([command], text=True, timeout=5).strip() == f'{value} ({identity[:7]})'
                assert subprocess.check_output([command, '--build'], text=True, timeout=5).strip() == identity
        build(fixture, '1.2.3', 'unknown')
        timestamp = (fixture/'.build/debug/Example').stat().st_mtime_ns
        build(fixture, '1.2.3', 'unknown')
        assert (fixture/'.build/debug/Example').stat().st_mtime_ns == timestamp, 'Unchanged metadata must not relink the executable'
        archive_hash = '0123456789abcdef0123456789abcdef01234567'
        (fixture/'BUILD').write_text(archive_hash+'\n')
        build(fixture, '1.2.3', archive_hash)
        (fixture/'BUILD').write_text('invalid\n')
        build(fixture, '', '', error='BUILD must contain a full Git commit hash')
        (fixture/'BUILD').write_text(archive_hash+'\n')
        git(fixture, 'init', '--template=')
        git(fixture, 'add', 'VERSION', 'Package.swift', 'Plugins', 'Tools', 'Sources', '.gitignore')
        git(fixture, 'commit', '-m', 'Initial fixture')
        first = git(fixture, 'rev-parse', 'HEAD')
        build(fixture, '1.2.3', first)
        git(fixture, 'commit', '--allow-empty', '-m', 'New build, same sources')
        second = git(fixture, 'rev-parse', 'HEAD'); assert second != first
        build(fixture, '1.2.3', second)
        git(fixture, 'checkout', '-b', 'another-branch')
        git(fixture, 'commit', '--allow-empty', '-m', 'Another branch build')
        build(fixture, '1.2.3', git(fixture, 'rev-parse', 'HEAD'))
        worktree = root/'worktree'
        git(fixture, 'worktree', 'add', '--detach', str(worktree), 'HEAD')
        git(worktree, 'commit', '--allow-empty', '-m', 'Worktree build')
        build(worktree, '1.2.3', git(worktree, 'rev-parse', 'HEAD'))
        archive = fixture/'source-archive'; archive.mkdir()
        for name in ['VERSION', 'Package.swift']: shutil.copy2(fixture/name, archive/name)
        for name in ['Plugins', 'Tools', 'Sources']: shutil.copytree(fixture/name, archive/name)
        build(archive, '1.2.3', 'unknown')  # Never borrow an enclosing repository's HEAD.
        (archive/'BUILD').write_text(archive_hash+'\n')
        build(archive, '1.2.3', archive_hash)
        (fixture/'VERSION').write_text('1.3.0-beta.1+fixture\n')
        build(fixture, '1.3.0-beta.1+fixture', git(fixture, 'rev-parse', 'HEAD'))
        for invalid in ['1.02.0', r'1.2.3\x2ddev']:
            (fixture/'VERSION').write_text(invalid+'\n')
            build(fixture, '', '', error='VERSION must contain a Semantic Version')
        print('PASS: embedded version/build output, relocated binaries, no runtime setup, incremental HEAD/branch/worktree changes, unchanged-build caching, archive BUILD/unknown handling and invalid metadata rejection')


if __name__ == '__main__': main()
