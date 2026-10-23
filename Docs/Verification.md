# Verification

Tests use isolated runtime homes, temporary SSH identities and owned tmux sockets. They do not change production configuration or service lifecycles. Shared setup in `Scripts/fixtures.py` creates administrator credentials, chooses loopback ports and cleans up owned processes; scenario assertions stay in each script.

## Automated checks

Build Swift binaries and frontend assets before running integration scripts:

```sh
swift build -c release
swift test
swift test -c release
npm ci --prefix Frontend
npm run build --prefix Frontend
npm test --prefix Frontend
python3 Scripts/generate-api.py --check
python3 -m unittest discover -s Scripts -p 'test_api_docs.py'
```

| Check | Coverage |
| --- | --- |
| Swift tests | Name-derived identities/collisions, rename isolation, configuration validation/conflicts, authentication, host isolation, SSH policy, service adapters, concurrent host discovery, read-only Git branches/detached HEAD, PTYs, terminal ownership, safe paths, plugins and installation |
| Frontend tests | Routing, terminal input, discovery states, name-only payloads/references, config update ordering, editor folding/wrapping and row reordering |
| `python3 Scripts/smoke.py` | HTTP authentication, Origin/CSRF and distinct error codes across every host route, config persistence, host boundaries, startup asset consistency and grouped API reference |
| `python3 Scripts/run-smoke.py` | First-run setup, debug/release configuration, updates, installation and operation without the checkout; build commands are recorded stand-ins |
| `python3 Scripts/ssh-fixture-smoke.py` | Two disposable SSH endpoints plus local execution: CLI, browser, terminal clipboard/resize/pinning/tmux, configuration forms, theme, Git branches, directory picker, script deployment/editing and real example probes |
| `AELAB_TEST_DAEMON=1 python3 Scripts/ssh-fixture-smoke.py` | Manual host installation without OS service changes, then the full suite with one SSH host, one direct daemon and native localhost |
| `python3 Scripts/daemon-smoke.py` | Direct TLS without SSH: pairing, certificate/auth/Origin rejection, multiplexed commands, discovery/plugins, native PTY/resize, timeouts and protocol bounds |
| `python3 Scripts/daemon-install-smoke.py` | Native daemon-only build orchestration, checkout independence, install collisions, unchanged credentials, refusal while running and stopped executable replacement; builds are recorded stand-ins with real daemon binaries |
| `python3 Scripts/base-path-smoke.py` | Nested runtime prefix, browser assets/deep links, scoped auth cookies, Origin checks, API docs and real terminal WebSocket |
| `AELAB_TEST_BROWSER_SCRIPT=grid-browser-smoke.mjs python3 Scripts/base-path-smoke.py` | Responsive 1–8-column cards in all sections/discovery, centered host header, per-host theme, row badge alignment, footer centering, reordering, narrow-screen fallback and long-label wrapping |
| `AELAB_TEST_BROWSER_SCRIPT=program-status-browser-smoke.mjs python3 Scripts/base-path-smoke.py` | Real PTY capability replies, program progress/input requests, tab titles, validation, prompt/reset/exit lifetimes and pinned replay |
| API contract checks | HTTP route coverage, schema references, required path parameters, unique operations, sorted output and synchronized embedding |
| `git diff --check` | Whitespace |

The HTTP/browser scripts use debug binaries built by `swift test`. SSH/browser checks require OpenSSH, tmux and Chromium; set `AELAB_TEST_BROWSER` to a Chromium executable when needed. Automated browser coverage uses Chromium on macOS. Launchd lifecycle tests record commands against fixture files rather than starting or stopping real jobs.

## Manual acceptance

- Exercise lifecycle operations and logs on disposable systemd units, launchd jobs, Docker containers and Compose stacks. Verify native permissions, launchd domains and application logs.
- Verify native daemon installation and user services on disposable Linux/macOS hosts; test firewall/Tailscale reachability, certificate renewal and credential revocation manually.
- Check Linux installation/container packaging and independent physical hosts with different service stacks. Local SSH fixtures verify routing, not every target platform.
- Check Safari, Firefox and mobile clipboard permissions and terminal layout.
- Review packaging paths and the service account’s SSH identity or supervised agent socket before deploying.

See [Installation](Installation.md) for setup and [Specification](Specification.md) for supported behavior and planned work.
