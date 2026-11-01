# aelab

A self-hosted web interface and CLI for your personal lab. Manage hosts, projects, services and browser terminals across local, SSH and optional daemon connections from one central instance. SSH hosts need no aelab installation.

A single [Swift](https://www.swift.org/) executable provides the CLI, [Hummingbird](https://hummingbird.codes) server and optional host daemon, with a web interface built using [Svelte](https://svelte.dev), [TypeScript](https://www.typescriptlang.org) and [xterm.js](https://xtermjs.org). The CLI works independently of the web interface and launches the server or daemon in the foreground or as a background service.

## Features

- Projects, shared tools and plugins, enabled per host; per-host themes and a responsive grid of cards.
- systemd, launchd, Docker and Compose status, logs and lifecycle controls.
- Browser shells, pinned terminals and persistent tmux sessions, with deep links, clipboard, custom colors, file dropping and screenshot pasting.
- [Matrix rain](Frontend/src/matrix-rain/README.md) from the logo, or a password-gated privacy screen from Lock.
- Configuration forms and a validated file editor; host directory picker and script editing/deployment.
- Admin login, SSH keys/agent authentication, strict host verification, paired TLS daemons and audit records.

## UI

<details>
  <summary>watch the video</summary>
  <video src="https://github.com/user-attachments/assets/b16ed74d-02a5-4e45-8e5a-23d031b1b5df" controls width="100%"></video>
</details>

<table>
  <tr>
    <td width="25%"><a href="https://github.com/user-attachments/assets/e7b377ad-67da-48f8-b26b-eebb986f0a4f"><img src="https://github.com/user-attachments/assets/e7b377ad-67da-48f8-b26b-eebb986f0a4f" width="200" alt="Screenshot 1"></a></td>
    <td width="25%"><a href="https://github.com/user-attachments/assets/56cb961f-8b4d-4bff-be71-809eac0f3efe"><img src="https://github.com/user-attachments/assets/56cb961f-8b4d-4bff-be71-809eac0f3efe" width="200" alt="Screenshot 2"></a></td>
    <td width="25%"><a href="https://github.com/user-attachments/assets/177dfa62-983c-477a-bd53-75742c047853"><img src="https://github.com/user-attachments/assets/177dfa62-983c-477a-bd53-75742c047853" width="200" alt="Screenshot 3"></a></td>
    <td width="25%"><a href="https://github.com/user-attachments/assets/20db665b-b115-4d9b-902a-5a59af08a0fa"><img src="https://github.com/user-attachments/assets/20db665b-b115-4d9b-902a-5a59af08a0fa" width="200" alt="Screenshot 4"></a></td>
  </tr>
  <tr>
    <td width="25%"><a href="https://github.com/user-attachments/assets/906149df-3dfe-4d5e-a0dc-df518dadecfc"><img src="https://github.com/user-attachments/assets/906149df-3dfe-4d5e-a0dc-df518dadecfc" width="200" alt="Screenshot 5"></a></td>
    <td width="25%"><a href="https://github.com/user-attachments/assets/38f016c8-af35-4058-8ea7-255fab488fba"><img src="https://github.com/user-attachments/assets/38f016c8-af35-4058-8ea7-255fab488fba" width="200" alt="Screenshot 6"></a></td>
    <td width="25%"><a href="https://github.com/user-attachments/assets/b997d200-5a3a-4557-8ed0-8a30e963db07"><img src="https://github.com/user-attachments/assets/b997d200-5a3a-4557-8ed0-8a30e963db07" width="200" alt="Screenshot 7"></a></td>
    <td width="25%"><a href="https://github.com/user-attachments/assets/d63970fd-e512-4737-b8f9-2dbd268a5d90"><img src="https://github.com/user-attachments/assets/d63970fd-e512-4737-b8f9-2dbd268a5d90" width="200" alt="Screenshot 8"></a></td>
  </tr>
</table>

## Build and run

Bring Swift, Node, Python and Git. Runs on macOS and Linux. SSH hosts need SSH access; persistent sessions need tmux on the selected host.

### Clone, start, explore

```sh
git clone https://github.com/tadija/aelab.git
cd aelab
./.ae server
```

First start builds everything, adds localhost and asks you to set an admin password. Open <http://localhost:2108> and sign in. Your lab starts here: add a host, a project, or open a shell with **+**.

Stop with Ctrl+C. Run `./.ae server` again to rebuild and start with your setup intact. Release is the default; `--configuration debug` adds debug builds and frontend sourcemaps. Use `--home PATH` and `--port PORT` to make yourself at home.

### Install once, launch from anywhere

```sh
./.ae install
export PATH="$HOME/.local/bin:$PATH"
aelab server
```

`install` copies the `aelab` executable and dashboard. It starts nothing. Add the PATH line to your shell configuration to keep it.

Repeat runs reuse Swift's incremental build cache, installed frontend dependencies and unchanged frontend output. Dependency manifests/toolchain changes reinstall npm packages; frontend source, mode or environment changes rebuild the dashboard. Identical installations reuse the current release. Installations prune obsolete releases, keeping current, one fallback and releases with open files (including running services). Run `aelab cleanup` to clean an existing installation; add `--prefix PATH` for a custom prefix. Cleanup conservatively skips removal when `lsof` is unavailable.

For a fresh rebuild, use `./.ae install --clean` (also available on `server` and `daemon`). It clears Swift build products and forces frontend dependency installation/build where applicable; configuration, credentials and installed runtime files stay intact.

Installed aelab needs no checkout or build tools; Linux still needs the Swift runtime libraries. Stop a checkout-run server before starting the installed one: they share the same runtime home by default.

### Run in the background, always on

```sh
aelab server --service
# or, directly from the checkout:
./.ae server --service
```

This sets up and starts a user service: systemd on Linux, launchd on macOS. First-time password entry happens in your terminal before the service starts. Rerunning the command updates its settings and restarts it. No sudo, no custom supervisor. See [service management and logs](Docs/Installation.md#background-services).

The two launch commands work the same way from `.ae` and the installed CLI:

| Command | Foreground | Background |
| --- | --- | --- |
| Dashboard server | `aelab server` | `aelab server --service` |
| Optional host daemon | `aelab daemon --endpoint https://HOST:1984` | `aelab daemon --endpoint https://HOST:1984 --service` |

Daemon setup needs OpenSSL; its first start requires `--endpoint`. Later starts reuse its saved credentials. `./.ae daemon` builds only native executables, so daemon-only hosts need no Node. See [pairing and daemon hosts](Docs/Daemon.md).

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
.build/release/aelab server
```

Hosting under `/aelab/`? Set `AELAB_BASE_PATH=/aelab`; see [URL prefixes](Docs/Installation.md#url-prefix).

### Where files live

Runtime data stays outside the checkout and survives rebuilds and reinstalls.

| Purpose | Default root | Override / notes |
| --- | --- | --- |
| Command | `~/.local/bin/aelab` | Add its directory to your shell's PATH; `install --prefix PATH` uses `PATH/bin/aelab` |
| Installed releases and dashboard | `~/.local/share/aelab` | Absolute `$XDG_DATA_HOME` uses `$XDG_DATA_HOME/aelab`; `--prefix PATH` uses `PATH/share/aelab` |
| Runtime data | `~/.aelab` | Configuration, credentials, state, daemon data, terminal uploads, deployed plugins and service logs. `$AELAB_HOME` or `--home PATH` changes the runtime home |

## CLI

```sh
aelab hosts
aelab status dev
aelab tmux dev
aelab tty dev --project aelab
aelab service status dev web
aelab help tty
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
