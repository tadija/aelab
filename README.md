# aelab

A self-hosted dashboard and CLI for your personal lab. Manage local, SSH and optional daemon hosts from one central instance. SSH hosts need no aelab installation.

Built with Swift/Hummingbird, Svelte 5 and xterm.js. The CLI works independently of the dashboard.

## Features

- Projects, shared tools and plugins, enabled per host; per-host themes and an adaptive 1–8-column grid.
- systemd, launchd, Docker and Compose status, logs and lifecycle controls.
- Browser shells, pinned terminals and persistent tmux sessions, with deep links, clipboard and custom colors.
- Configuration forms and a validated file editor; host directory picker and script editing/deployment.
- Administrator login, SSH keys/agent authentication, strict host verification, paired TLS daemons and audit records.

## Build and run

Bring Swift 6.4+, Node 26+, Python 3 and Git. Runs on macOS 14+ and Linux. Remote SSH hosts need SSH access; persistent sessions need tmux on the selected host.

### Clone, run, explore

```sh
git clone https://github.com/tadija/aelab.git
cd aelab
./.ae run
```

Open <http://localhost:2108> and sign in. On the first run, aelab builds everything, adds localhost and asks you to set an admin password. Your lab starts here—add a host, a project, or open a shell with **+**.

Configuration and credentials live in `~/.aelab` (`$AELAB_HOME`), separate from the checkout. Stop with Ctrl+C. Running `./.ae run` again rebuilds and starts the server while keeping your setup.

Release builds are the default. Use `./.ae run --configuration debug` for debug builds and frontend sourcemaps. Use `--home PATH` or `--port PORT` to choose a different home or port. Hosting under `/aelab/`? Set `AELAB_BASE_PATH=/aelab`; see [URL prefixes](Docs/Installation.md#url-prefix).

### Install once, run from anywhere

From the checkout:

```sh
./.ae install
export PATH="$HOME/.local/bin:$PATH"
aelab help
aelab run
```

Installation builds and copies the CLI, server and dashboard to `~/.local/bin` and `$XDG_DATA_HOME/aelab` (default `~/.local/share/aelab`). Add the PATH line to your shell configuration to keep it. For a custom destination, use `./.ae install --prefix PATH`, then add `PATH/bin` to PATH; assets go to `PATH/share/aelab`.

Stop any checkout-run server before starting the installed one. Both use the same configuration home by default. Installed aelab runs without the checkout or build tools; Linux still needs the Swift runtime libraries.

### Keep it fresh

Stop the running server, then return to your checkout:

```sh
cd aelab # or wherever you cloned it
git pull
./.ae run
```

For an installed copy, use these last two steps instead of `./.ae run`:

```sh
./.ae install
aelab run
```

Use the same `--prefix`, home and port options as before if you customized them. Your configuration and credentials stay put.

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

Browser terminals display [program status](Docs/ProgramStatus.md) from tools that emit OSC 7501, including progress and requests for input.

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
