# Daemon hosts

The optional daemon runs commands and terminals over direct TLS after pairing with your central instance. It executes as its own user, with the same adapters as local/SSH execution and no implicit sudo. SSH hosts do not need it.

## Start on the host

Requires Git, Swift 6.4+ and OpenSSL; macOS requires 14+. No Node or frontend build is needed for this path:

```sh
git clone https://github.com/tadija/aelab.git
cd aelab
./.ae daemon --endpoint https://HOST:1984
```

The first start creates private settings, a TLS certificate and pairing credentials in `~/.aelab/daemon` (or `$AELAB_HOME/daemon`). Use `--home PATH` to select an exact daemon directory and `--bind ADDRESS` to change the default `0.0.0.0` bind. The endpoint defaults to port 1984 and must be reachable from the central instance with a matching certificate hostname. A private network such as Tailscale works.

Stop with Ctrl+C. Later starts need only `./.ae daemon`; existing settings and credentials are preserved. Conflicting endpoint/bind options are rejected. Use `--configuration debug` for native debug builds. Builds reuse Swift caches; add `--clean` for a fresh native rebuild.

For a background user service, add `--service`:

```sh
./.ae daemon --endpoint https://HOST:1984 --service
```

This uses systemd on Linux or a LaunchAgent on macOS. It references the checkout binaries, so keep the checkout in place. Repeating `--service` updates and restarts the service. See [background services](Installation.md#background-services) for requirements, settings, stop/status/log commands.

## Install for checkout-independent operation

If you want all commands available from PATH, install the complete application (this also requires Node 26+ and Python 3):

```sh
./.ae install
export PATH="$HOME/.local/bin:$PATH"
aelab daemon --endpoint https://HOST:1984 --service
```

Installation copies `aelab-cli`, `aelab-server`, `aelab-daemon` and the dashboard; it starts nothing and leaves runtime credentials untouched. `--prefix PATH` changes the install destination. Installed daemon operation needs neither the checkout nor build tools; Linux still needs Swift runtime libraries. Omit `--service` to run in the foreground.

## Pair

From the checkout on the daemon host:

```sh
./.ae daemon pairing --output pairing.json
# Installed alternative:
# aelab daemon pairing --output pairing.json
```

For a custom daemon directory: `aelab daemon pairing --home PATH --output pairing.json`. Transfer this private file securely to the central machine, then run:

```sh
aelab daemon pair laptop --file pairing.json
```

For an existing host, use its URL ID. Pairing verifies TLS before selecting daemon execution; it cannot replace the explicit local host. Delete the exported file after importing it. Central credentials stay in private `state/daemons/UUID.json` files, outside configuration and browser responses.

## Updates

Stop the daemon before building/installing an update. For a user service:

```sh
# Linux:
systemctl --user stop aelab-daemon.service
# macOS alternative:
# launchctl bootout "gui/$(id -u)/dev.aelab.daemon"
git pull
./.ae daemon --service
```

For an installed copy, use `./.ae install` then `aelab daemon --service` instead of the last line. For foreground operation, stop with Ctrl+C, pull, then use `./.ae daemon` (or install and `aelab daemon`). Repeat your custom home and other settings when applicable. Pairing and settings remain unchanged. Native terminals disconnect on restart; host-side tmux sessions survive.

Linux logs: `journalctl --user -u aelab-daemon.service`. macOS logs: `~/.aelab/daemon/logs/daemon.stdout.log` and `daemon.stderr.log`. Linux requires a working user manager; macOS requires a GUI login session. Lingering/system-wide privileges are administrator choices.

## Manual binary setup

```sh
swift build -c release --product aelab-daemon
.build/release/aelab-daemon init --endpoint https://HOST:1984
.build/release/aelab-daemon
```

The raw binary starts directly after initialization. Use `aelab daemon` for CLI-managed setup and launch. You can copy a matching binary yourself; OpenSSL is needed only for initialization. Manual service examples are in [Packaging](Packaging).

TLS verifies the pinned certificate and endpoint hostname; private tokens authenticate clients. Browser Origins and unsupported protocol messages are rejected, requests/output are bounded, and disconnects cancel commands and close native PTYs. The daemon is a trusted execution endpoint, not a sandbox. Certificates last one year; renewal/revocation currently requires a fresh private home and re-pairing. Outbound connections and persistent tasks remain follow-ups.
