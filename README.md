# aelab

A self-hosted dashboard and CLI for your personal lab. Manage local, SSH and optional daemon hosts from one central instance. SSH hosts need no aelab installation.

Built with Swift/Hummingbird, Svelte 5 and xterm.js. The CLI works independently of the dashboard.

## Features

- Projects, shared tools and plugins, enabled per host; per-host themes and responsive normal/compact layouts.
- systemd, launchd, Docker and Compose status, logs and lifecycle controls.
- Browser shells, pinned terminals and persistent tmux sessions, with deep links, clipboard and custom colors.
- Configuration forms and a validated file editor; host directory picker and script editing/deployment.
- Administrator login, SSH keys/agent authentication, strict host verification, paired TLS daemons and audit records.

## Build and run

Requires Swift 6.2+, Node 24+, Python 3 and SSH access to remote hosts. macOS requires 14+. Persistent tmux sessions require tmux on the selected host.

```sh
./.ae run
```

This builds aelab, prepares `$AELAB_HOME` (default `~/.aelab`), asks for an admin password on first setup, and starts at <http://localhost:2108>. Existing configuration and credentials are preserved; new configurations include localhost.

Hosting under `/aelab/`? Set `AELAB_BASE_PATH=/aelab`; see [URL prefixes](Docs/Installation.md#url-prefix).

Use `--debug` (or `--configuration debug`) for debug builds and frontend sourcemaps; release is the default. Use `--home PATH` or `--port PORT` for custom settings.

### Install

```sh
./.ae install
aelab help
aelab run
```

Installs the CLI, server and dashboard assets to `~/.local/bin` and `$XDG_DATA_HOME/aelab` (default `~/.local/share/aelab`). Add `~/.local/bin` to PATH, or use `--prefix PATH` for `PATH/bin` and `PATH/share/aelab`.

Installed aelab needs no source checkout, Swift or Node. To update, stop the server, pull changes and run `./.ae install` again.

### Manual build and run

```sh
python3 Scripts/generate-api.py
swift build -c release
npm ci --prefix Frontend
npm run build --prefix Frontend
export AELAB_HOME="$HOME/.aelab"
.build/release/aelab init --if-needed
[ -e "$AELAB_HOME/state/admin.json" ] || .build/release/aelab admin bootstrap
.build/release/aelab-server
```

## CLI

```sh
aelab hosts
aelab status dev
aelab tty dev --project aelab
```

Hosts can build their own daemon with `./.ae daemon-install --endpoint https://HOST:1984 --service` (Swift and OpenSSL only). For pairing, manual updates and service templates, see [Daemon hosts](Docs/Daemon.md).

Before installation, use `./.ae` in place of `aelab`. See `aelab help` for configuration, diagnostics and service actions.

## Tests

```sh
swift test
npm test --prefix Frontend
python3 Scripts/generate-api.py --check
python3 -m unittest discover -s Scripts -p 'test_api_docs.py'
```

See [Verification](Docs/Verification.md) for HTTP, installation and SSH/browser checks.

## Documentation

- [Installation and configuration](Docs/Installation.md)
- [Configuration example](Docs/Config/aelab.example.json)
- [Script plugins](Plugins/README.md)
- [Daemon hosts](Docs/Daemon.md)
- [Specification and roadmap](Docs/Specification.md)
- API reference: `/api/docs` on your running instance
