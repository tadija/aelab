# Installation and configuration

## Start and install

`./.ae server` builds and starts aelab at <http://localhost:2108>, using `~/.aelab` by default. First run adds localhost and asks for an administrator password. Options: `--configuration debug|release`, `--home PATH`, `--port PORT`. Stop with Ctrl+C before pulling updates and running again. Existing configuration and credentials are preserved. Manual build commands are in [README](../README.md).

`./.ae install` installs `aelab-cli`, `aelab-server`, `aelab-daemon` and the dashboard, plus an `aelab` symlink to `aelab-cli`. Both macOS and Linux use `~/.local/bin` and `$XDG_DATA_HOME/aelab`, defaulting to `~/.local/share/aelab`. Only absolute XDG paths are honored. `--prefix PATH` overrides these with `PATH/bin` and `PATH/share/aelab`. Add the command directory to PATH, then use `aelab server`. Installed operation needs no checkout or build tools; updates require rebuilding and reinstalling. Installation always uses release builds and never edits shell files, enables services or elevates privileges.

Builds are incremental by default. Frontend dependency and output caches live under `Frontend/node_modules/.cache/aelab`; unchanged assets are checked before reuse, and matching installations keep their active release. Changing dependency inputs or the Node/npm toolchain reinstalls dependencies; changing frontend inputs, build mode or Vite environment rebuilds assets. Generated API source keeps its timestamp when unchanged so Swift can reuse its build cache.

Use `./.ae install --clean`, `./.ae server --clean` or `./.ae daemon --clean` to clear Swift build products and rebuild. Server/install also force `npm ci` and the frontend build. Swift dependency downloads and npm's package cache remain reusable; runtime homes, credentials and installed releases are preserved.

## Background services

Add `--service` to either launch command, from the checkout or installed CLI:

```sh
aelab server --service
aelab daemon --endpoint https://HOST:1984 --service
```

First use prepares configuration and credentials before starting the process; server password setup stays interactive. Subsequent calls preserve credentials, update the generated definition and restart that service. Omit `--endpoint` after daemon setup. `--home PATH` selects the runtime home; the daemon defaults to `$AELAB_HOME/daemon`. `--port PORT` applies to the server. Neither `install` nor pairing starts a service.

Services run as your user without sudo. Linux uses a systemd user manager; macOS uses a LaunchAgent in the current GUI login session. For operation without an interactive login, configure Linux lingering or a system-wide service yourself. The generated defaults follow [systemd's service model](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html) and [Apple's user-agent model](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html).

Server definitions save the effective home, port, origin, bind address, URL prefix, dashboard path, PATH, any supplied SSH agent socket and `AELAB_SSH_CONFIG` override. Set `AELAB_ORIGIN`, `AELAB_BIND`, `AELAB_BASE_PATH` and a stable `SSH_AUTH_SOCK` before invoking `--service` if needed. Do not rely on a GUI service inheriting your terminal environment. Installed services follow the active installed release; checkout services reference that checkout, so keep it in place.

On Linux (replace `server` with `daemon` for that process):

```sh
systemctl --user status aelab-server.service
journalctl --user -u aelab-server.service -f
systemctl --user stop aelab-server.service
# Disable future login startup too:
systemctl --user disable aelab-server.service
```

Definitions live in `$XDG_CONFIG_HOME/systemd/user` (default `~/.config/systemd/user`). On macOS:

```sh
launchctl print "gui/$(id -u)/dev.aelab.server"
tail -f "$HOME/.aelab/logs/server.stderr.log"
launchctl bootout "gui/$(id -u)/dev.aelab.server"
# Disable future login startup too:
launchctl disable "gui/$(id -u)/dev.aelab.server"
```

LaunchAgents live in `~/Library/LaunchAgents/dev.aelab.{server,daemon}.plist`. macOS logs live under the selected runtime home: `logs/server.{stdout,stderr}.log` or `logs/daemon.{stdout,stderr}.log` (default daemon home `~/.aelab/daemon`).

Stop the relevant service before updating with `git pull` and `./.ae install`, then repeat `aelab server --service` or `aelab daemon --service` with your original settings. For checkout operation, stop, pull and repeat `./.ae server --service` or `./.ae daemon --service`. Repeating `--service` restarts the selected service, disconnecting its terminals; tmux sessions survive. A service-manager start confirms launch, not application readiness: check its logs/status if the URL is unavailable.

Generated definitions are marked and may be replaced by later `--service` calls. Unrelated files and symlinks are refused.

Manual system-wide server, proxy and container examples remain under [Packaging](Packaging). The built-in service commands do not modify those installations.

## Configuration and hosts

`$AELAB_HOME/config/aelab.json` is the source of truth. Schema `version: 1` keeps tools, plugins, execution paths and terminal buttons central. Hosts own projects/services and select enabled tool/plugin IDs. See [Configuration](Config/README.md) and [the example](Config/aelab.example.json).

Choose host transport explicitly: `local` executes as the server account; `ssh` uses keys/SSH agent authentication and verified host keys; `daemon` uses a paired direct TLS connection. See [Daemon hosts](Daemon.md) for on-host installation, pairing and service setup. Local hosts omit destination and port. Shared `paths` prepend literal absolute directories to PATH for discovery, commands and terminals. Project directories override tool working directories.

Names determine URL IDs. Renaming changes links; forms update enabled selections and service references together. The configuration icon opens the running instance’s main file with highlighting, line numbers, folding and wrapping. Writes are validated, atomic and revision-checked. Close and reopen an editor to load the latest file; closing unsaved edits asks for confirmation. Changes affect new operations immediately; reconnect terminals to apply host changes. Environment changes require a restart.

Drag handles, arrow keys and Move up/down controls reorder configured rows. Tool/plugin order is shared; project/service order belongs to each host. For shared tools and plugins, the rightmost × in enabled rows deletes the definition from all hosts only on an explicit local host, with confirmation. On remote hosts, × only disables that host’s selection. Discovery checkmarks toggle selections. Neither action deletes files or stops programs. Discovery filters show all candidates instead of enabled/configured entries. Tools and plugins must be available before enabling them; discovery never executes or installs them. Refresh appears within discovery views.

## Services

Linux/WSL uses systemd; macOS uses launchd. Service discovery combines a text search with the status filter; choose All statuses to search beyond running entries. Launchd discovery lists the caller’s bootstrap domain. Configure full targets such as `gui/502/com.example.agent` or `system/com.example.daemon`, using that host’s UID/domain. Set a `plist` path (absolute or `~/`) to allow Stop and reloading after unload. Start/restart uses kickstart; Stop unloads the job. Optional `logFiles` provides application logs; otherwise Logs shows launchd lifecycle messages. Privileged lifecycle actions require explicit, scoped `sudo -n` permission; reads never elevate.

Docker/Compose uses the host user’s default context unless the host’s configuration-only `dockerContext` selects another. aelab never starts the engine or changes saved contexts. Compose actions operate existing stacks; they do not build, deploy or recreate them. Running/reachable indicates native state, not application health.

### Services needing sudo

User unit selects the connected account’s systemd user manager (`systemctl --user`), rather than system services. Usually leave sudo off for these: sudo changes the account and can target root’s user manager instead.

Use sudo adds `sudo -n` only to Start, Stop and Restart. It never asks for or stores a password; Status and Logs keep the connected account’s permissions. For a Linux system service, an administrator can use `sudo visudo -f /etc/sudoers.d/aelab` on that host to grant just the required commands. For example, adapting the account, systemctl path and unit:

```sudoers
operator ALL=(root) NOPASSWD: /usr/bin/systemctl --no-ask-password start -- example.service
operator ALL=(root) NOPASSWD: /usr/bin/systemctl --no-ask-password stop -- example.service
operator ALL=(root) NOPASSWD: /usr/bin/systemctl --no-ask-password restart -- example.service
```

Then enable Use sudo for that service and use its dashboard actions. Without noninteractive permission, the action fails with the host’s error. aelab does not change sudoers or service permissions.

## Projects and terminals

Creating a project creates its directory when missing. Its title opens a shell, or creates/attaches its configured tmux session. Project tool buttons use that directory. An optional tool `altArguments` list replaces normal arguments when you hold Alt while clicking its launch option; eligible options display ALT while the key is held. For example, use `"arguments": []` and `"altArguments": ["resume"]` to choose between a new Codex session and resume. YOLO uses an explicitly configured bypass preset, appended to either argument list; standalone tools use their default directory or ask you to choose one from the host directory picker.

The hostname menu opens temporary shells/tools or explicit tmux sessions. Pinning retains the current native terminal through browser disconnects; numbered dashboard shortcuts reopen it. Native pins and tmux shortcuts survive logout and subsequent logins. Signing out disconnects that login’s tabs; sign back in to resume. A password reset clears pins. Native shell pins end on server shutdown; tmux pins keep their shortcuts across server restarts. tmux sessions survive server restarts. Session rows support rename and confirmed deletion; renaming changes their URLs.

Terminals inherit the host’s Terminal background. Click `cwd` to save a directory-specific override, or `host` to reset it. Theme/tint are remembered per host in the browser; section expansion lives separately in `state/sections.json`.

Ctrl+C copies selected text and otherwise interrupts. Cmd+C and Ctrl+Shift+C also copy. Hold Option on macOS or Shift elsewhere to select when tmux captures the mouse. Clipboard controls require browser permission.

The terminal key bar uses the shared `ttyButtons` array. For example: `[{"key":"ctrl-c","label":"Stop"},{"key":"reload-tty","label":"Redraw"}]`. First-run initialization seeds it from the example; omission or `[]` hides all buttons. See the example and specification for supported keys. Changes apply to newly opened terminal pages.

## Files in terminals

Drop files into a tty, or paste a screenshot with your normal paste shortcut. The Paste key-bar button also supports clipboard images where the browser permits it. Upload up to ten files at a time, each at most 20 MiB. A small progress indicator offers cancellation; ordinary terminal input and output continue during transfer.

Files are saved privately under `~/.aelab/uploads` on the terminal's execution host, including SSH and daemon hosts. Aelab pastes each quoted absolute path separately without pressing Enter. The running program decides how to use it: supporting AI tools can create native image attachments, while shells receive ordinary file paths. Uploaded bytes never go into the PTY.

Completed files remain available across tab closure, pinning, tmux and server restarts. Remove them from the host when no longer needed. Failed or cancelled incomplete transfers and the central temporary spool are cleaned up. Directory dropping is not supported.

## Plugins

Define probes centrally, then enable them per host. Click a title to run its probe or the Script icon to edit its configured Bash/Ruby/Swift source. Editors share a remembered wrapping preference, validate syntax and detect conflicting saves. Compiled plugins need rebuilding after source edits.

Use `~/` for portable per-user paths. Absolute local script paths resolve on SSH hosts to `~/.aelab/plugins/SCRIPT_NAME/FILENAME`. The Deploy icon beside an unavailable remote plugin previews and copies its configured source from an explicit local host. It never copies binaries, installs interpreters, builds or runs a plugin. Close and reopen the dialog for a fresh preview. See [Plugins](../Plugins/README.md) for examples and the contract.

## Version

`aelab --version`, `aelab-server --version` and `aelab-daemon --version` print the release and a short commit ID, such as `0.2.0 (abc123d)`. Use `--build` for the full commit hash. Both flags also work with `./.ae` without building. The dashboard footer shows the server's release and build; hover for the full hash.

To prepare a release, edit root `VERSION`, rebuild/install, and tag it as `vX.Y.Z`. Builds embed VERSION and the checkout's Git HEAD, including direct `swift build` builds. Installed programs never need Git or the checkout. Configuration-schema and daemon-protocol versions are separate.

For source archives without Git metadata, provide an optional `BUILD` file containing the full commit hash. This file is ignored by Git. Without either source, the build ID is `unknown`. Docker builds accept the hash explicitly:

```sh
docker build --build-arg AELAB_BUILD="$(git rev-parse HEAD)" -f Docs/Packaging/Dockerfile .
```

## Security and packaging

Keep runtime files private. Passwords use salted PBKDF2 hashing; `aelab admin reset` revokes sessions. Mutations require exact Origin and CSRF checks. Terminal tickets are owner-bound and single-use; audit excludes secrets and terminal contents.

Environment options: `AELAB_HOME`, `AELAB_PORT`, `AELAB_BIND`, `AELAB_ORIGIN`, `AELAB_PUBLIC` and optional `AELAB_SSH_CONFIG`. The default bind is 127.0.0.1. Use an exact HTTPS origin behind a reverse proxy for remote browser access.

`Docs/Packaging/` provides opt-in systemd, proxy and container templates. The service template assumes a `--prefix /usr/local` installation. Use a dedicated account with protected SSH keys or a supervised agent socket; services do not inherit an interactive agent. Run `aelab doctor` under that identity. Container-local execution targets the container; use SSH for other hosts and avoid mounting the Docker socket by default.

Authenticated API documentation is at `/api/docs`. Its contract lives in `Docs/openapi.json`; embed updates with `python3 Scripts/generate-api.py`. `--check` verifies route coverage and synchronization. See [Verification](Verification.md) for test coverage and manual acceptance.

## URL prefix

To serve `https://lab.example.com/aelab/`, set these on the server:

```sh
AELAB_ORIGIN=https://lab.example.com
AELAB_BASE_PATH=/aelab
```

The origin excludes the path. The base path defaults to `/`; nested prefixes work, and no frontend rebuild is needed. All HTTP and terminal WebSocket routes, assets, API docs and cookie paths use the prefix. Restart after changing it. The reverse proxy must preserve the path—use Caddy `handle`, not `handle_path`:

```caddy
lab.example.com {
    @aelab path /aelab /aelab/*
    handle @aelab {
        reverse_proxy 127.0.0.1:2108
    }
}
```

The backend redirects `/aelab` to `/aelab/`. Its health endpoint becomes `/aelab/health`. Authentication keeps exact Origin and CSRF checks; the base path does not change daemon endpoints.

A server keeps its dashboard assets for its lifetime. After backend or frontend changes, stop it and run `./.ae server` again so both use the same build.

Click the logo circles on login, dashboard or terminal pages for Matrix rain that dismisses immediately with Escape or a rain click. Host colors can be edited in the host form. The dashboard’s **Lock** button shows a UI-only Matrix rain privacy overlay. Press Escape or click the rain to toggle the password form. The key button opens password changing: enter the current password and confirm a new one (12+ characters). Changing the password invalidates existing logins and pins, like a local password reset. All open terminals, background polling and API/WebSocket traffic continue unchanged; password confirmation only dismisses the overlay. The existing login cookie and session expiry remain unchanged. **Exit** performs the normal sign-out and temporary-terminal cleanup.
