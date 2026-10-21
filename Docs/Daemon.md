# Daemon hosts

`aelab-daemon` is an optional host executable. After pairing, commands and terminals use direct TLS without SSH. It runs as its own account, with the same operational adapters and authorization as local/SSH execution. No implicit sudo.

## Install on the host

Requires Git, Swift 6.2+ and OpenSSL; macOS requires 14+. No Node or frontend build is needed.

```sh
git clone https://github.com/tadija/aelab.git
cd aelab
./.ae daemon-install --endpoint https://HOST:1984 --service
```

This builds the native daemon, copies it to `~/.aelab/daemon/aelab-daemon`, and links `~/.local/bin/aelab-daemon`. Add `~/.local/bin` to PATH. The installed executable runs independently of the checkout. On Linux, keep the Swift runtime libraries installed.

`--service` installs and starts a user systemd service on Linux or LaunchAgent on macOS. Omit it for foreground operation with `aelab-daemon run`. Use `--home PATH`, `--prefix PATH` (for `PATH/bin`), or `--bind ADDRESS` as needed. Existing settings and credentials are preserved; changed endpoint/bind options and unrelated executable/service collisions are rejected.

The HTTPS endpoint must be reachable from the central instance and match its certificate hostname. A private network such as Tailscale works. Port defaults to 1984 and bind to `0.0.0.0`.

## Pair

On the daemon host:

```sh
aelab-daemon pairing --output pairing.json
```

Transfer this private file securely to the central machine, then run:

```sh
aelab daemon pair laptop --file pairing.json
```

For an existing host, use its URL ID. Pairing verifies TLS before selecting daemon execution; it cannot replace the explicit local host. Delete the exported file after importing it. Central credentials stay in private `state/daemons/UUID.json` files, outside configuration and browser responses.

## Services and updates

Service management belongs to the host's systemd/launchd. Linux needs a working user manager; macOS LaunchAgents need a GUI login session. Lingering and privileges are administrator choices.

Stop before installing an update. On Linux:

```sh
systemctl --user stop aelab-daemon.service
git pull
./.ae daemon-install --service
```

On macOS:

```sh
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/dev.aelab.daemon.plist"
git pull
./.ae daemon-install --service
```

For foreground operation, stop with Ctrl+C, run `git pull` and `./.ae daemon-install`, then `aelab-daemon run`. Installation refuses a running daemon and atomically replaces the stopped executable. Pairing and settings remain unchanged. Native terminals disconnect on restart; host-side tmux sessions survive. There is no remote deployment, self-update or rollback machinery.

For manual service setup, adapt the [systemd user unit](Packaging/aelab-daemon.service) or [LaunchAgent](Packaging/dev.aelab.daemon.plist). Linux logs: `journalctl --user -u aelab-daemon.service`. macOS logs: `~/.aelab/daemon/stdout.log` and `stderr.log`.

## Manual build

```sh
swift build -c release --product aelab-daemon
.build/release/aelab-daemon init --endpoint https://HOST:1984
.build/release/aelab-daemon run
```

You can also copy a matching binary yourself. Initialization refuses an existing daemon home; OpenSSL is needed only for initialization.

TLS verifies the pinned certificate and endpoint hostname; private tokens authenticate clients. Browser Origins and unsupported protocol messages are rejected, requests/output are bounded, and disconnects cancel commands and close native PTYs. The daemon is a trusted execution endpoint, not a sandbox. Certificates last one year; renewal/revocation currently requires a fresh private home and re-pairing. Outbound connections and persistent tasks remain follow-ups.
