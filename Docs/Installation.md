# Installation and configuration

## Run and install

`./.ae run` builds and starts aelab at <http://localhost:2108>, using `~/.aelab` by default. First run adds localhost and asks for an administrator password. Options: `--debug`, `--home PATH`, `--port PORT`. Stop with Ctrl+C before pulling updates and running again. Existing configuration and credentials are preserved. Manual build commands are in [README](../README.md).

`./.ae install` installs the CLI, server and dashboard. Both macOS and Linux use `~/.local/bin` and `$XDG_DATA_HOME/aelab`, defaulting to `~/.local/share/aelab`. Only absolute XDG paths are honored. `--prefix PATH` overrides these with `PATH/bin` and `PATH/share/aelab`. Add the command directory to PATH, then use `aelab run`. Installed operation needs no checkout or build tools; updates require rebuilding and reinstalling. Installation always uses release builds and never edits shell files, enables services or elevates privileges.

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

Creating a project creates its directory when missing. Its title opens a shell, or creates/attaches its configured tmux session. Project tool buttons use that directory. YOLO uses an explicitly configured bypass preset; standalone tools use their default directory or ask you to choose one from the host directory picker.

The hostname menu opens temporary shells/tools or explicit tmux sessions. Pinning retains the current native terminal through browser disconnects; numbered dashboard shortcuts reopen it. Native pins belong to the current login and end on logout, expiry or server shutdown. tmux sessions survive server restarts. Session rows support rename and confirmed deletion; renaming changes their URLs.

Terminals inherit the host’s Terminal background. Click `cwd` to save a directory-specific override, or `host` to reset it. Theme/tint are remembered per host in the browser; section expansion lives separately in `state/sections.json`.

Ctrl+C copies selected text and otherwise interrupts. Cmd+C and Ctrl+Shift+C also copy. Hold Option on macOS or Shift elsewhere to select when tmux captures the mouse. Clipboard controls require browser permission.

The terminal key bar uses the shared `ttyButtons` array. For example: `[{"key":"ctrl-c","label":"Stop"},{"key":"reload-tty","label":"Redraw"}]`. First-run initialization seeds it from the example; omission or `[]` hides all buttons. See the example and specification for supported keys. Changes apply to newly opened terminal pages.

## Plugins

Define probes centrally, then enable them per host. Click a title to run its probe or the Script icon to edit its configured Bash/Ruby/Swift source. Editors share a remembered wrapping preference, validate syntax and detect conflicting saves. Compiled plugins need rebuilding after source edits.

Use `~/` for portable per-user paths. Absolute local script paths resolve on SSH hosts to `~/.aelab/plugins/SCRIPT_NAME/FILENAME`. The Deploy icon beside an unavailable remote plugin previews and copies its configured source from an explicit local host. It never copies binaries, installs interpreters, builds or runs a plugin. Close and reopen the dialog for a fresh preview. See [Plugins](../Plugins/README.md) for examples and the contract.

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

A server keeps its dashboard assets for its lifetime. After backend or frontend changes, stop it and run `./.ae run` again so both use the same build.
