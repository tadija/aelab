# aelab

A self-hosted dashboard and CLI for your personal lab. Manage local, SSH and optional daemon hosts from one central instance. SSH hosts need no aelab installation.

Built with Swift/Hummingbird, Svelte 5 and xterm.js. The CLI works independently of the dashboard.

## Features

- Projects, shared tools and plugins, enabled per host; per-host themes and a responsive grid of cards.
- systemd, launchd, Docker and Compose status, logs and lifecycle controls.
- Browser shells, pinned terminals and persistent tmux sessions, with deep links, clipboard, custom colors, file dropping and screenshot pasting.
- [Matrix rain](Frontend/src/matrix-rain/README.md) from the logo, or a password-gated privacy screen from Lock.
- Configuration forms and a validated file editor; host directory picker and script editing/deployment.
- Admin login, SSH keys/agent authentication, strict host verification, paired TLS daemons and audit records.

## Build and run

Bring Swift, Node, Python and Git. Runs on macOS and Linux. SSH hosts need SSH access; persistent sessions need tmux on the selected host.

### Clone, start, explore

```sh
git clone https://github.com/tadija/aelab.git
cd aelab
./.ae server
```

First start builds everything, adds localhost and asks you to set an admin password. Open <http://localhost:2108> and sign in. Your lab starts here: add a host, a project, or open a shell with **+**.

Stop with Ctrl+C. Configuration and credentials live in `~/.aelab` (`$AELAB_HOME`), outside the checkout. Run `./.ae server` again to rebuild and start with your setup intact. Release is the default; `--configuration debug` adds debug builds and frontend sourcemaps. Use `--home PATH` and `--port PORT` to make yourself at home.

### Install once, launch from anywhere

```sh
./.ae install
export PATH="$HOME/.local/bin:$PATH"
aelab server
```

`install` copies **all three executables** (`aelab-cli`, `aelab-server`, `aelab-daemon`) and deploys the frontend. It starts nothing. Add the PATH line to your shell configuration to keep it. Files go to `~/.local/bin` and  `~/.local/share/aelab`; `--prefix PATH` uses `PATH/bin` and `PATH/share/aelab` instead.

Repeat runs reuse Swift's incremental build cache, installed frontend dependencies and unchanged frontend output. Dependency manifests/toolchain changes reinstall npm packages; frontend source, mode or environment changes rebuild the dashboard. Identical installations reuse the current release.

For a fresh rebuild, use `./.ae install --clean` (also available on `server` and `daemon`). It clears Swift build products and forces frontend dependency installation/build where applicable; configuration, credentials and installed runtime files stay intact.

Installed aelab needs no checkout or build tools; Linux still needs the Swift runtime libraries. Stop a checkout-run server before starting the installed one: they share the same runtime home by default.

### Run in the background, always on

```sh
aelab server --service
# Or, directly from the checkout:
./.ae server --service
```

This sets up and starts a user service: systemd on Linux, launchd on macOS. First-time password entry happens in your terminal before the service starts. Rerunning the command updates its settings and restarts it. No sudo, no custom supervisor. See [service management and logs](Docs/Installation.md#background-services).

The two launch commands work the same way from `.ae` and the installed CLI:

| Command | Foreground | Background |
| --- | --- | --- |
| Dashboard server | `aelab server` | `aelab server --service` |
| Optional host daemon | `aelab daemon --endpoint https://HOST:1984` | `aelab daemon --endpoint https://HOST:1984 --service` |

Daemon setup needs OpenSSL; its first start requires `--endpoint`. Later starts reuse its credentials in `~/.aelab/daemon`. `./.ae daemon` builds only native executables, so daemon-only hosts need no Node. See [pairing and daemon hosts](Docs/Daemon.md).

### Keep it fresh

Stop the foreground process or [its service](Docs/Installation.md#background-services), then return to your checkout:

```sh
cd aelab # wherever you cloned it
git pull
./.ae server
```

For an installed copy, replace the last line with:

```sh
./.ae install
aelab server # add --service to restart the background service
```

Use `daemon` instead of `server` on daemon hosts, and repeat your custom prefix, home, port and environment settings when applicable. Credentials and configuration stay put. `install` never starts or restarts either process.

### Manual build and run

```sh
python3 Scripts/generate-api.py
swift build -c release
npm ci --prefix Frontend
npm run build --prefix Frontend
export AELAB_HOME="$HOME/.aelab"
.build/release/aelab-cli server
```

Hosting under `/aelab/`? Set `AELAB_BASE_PATH=/aelab`; see [URL prefixes](Docs/Installation.md#url-prefix).

## CLI

```sh
aelab hosts
aelab status dev
aelab tty dev --project aelab
```

Browser terminals display [program status](Docs/ProgramStatus.md) from tools that emit OSC 7501, including progress and requests for input.

Before installation, use `./.ae` in place of `aelab`. See `aelab help` for configuration, diagnostics, pairing and service actions.

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

---

`done for fun`
