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
| `python3 Scripts/version-smoke.py` | Embedded version/build output from relocated executables and public alias without runtime setup; automatic HEAD/branch/worktree updates, unchanged-build caching, archive BUILD/unknown handling and malformed-metadata rejection in isolated packages |
| `python3 Scripts/server-launch-smoke.py` | Server foreground launch, first-run setup, debug/release configuration, updates, all-target installation and operation without the checkout; build commands are recorded stand-ins |
| `python3 Scripts/ssh-fixture-smoke.py` | Two disposable SSH endpoints plus local execution: CLI, browser, terminal clipboard/resize/pinning/tmux, configuration forms, theme, Git branches, directory picker, script deployment/editing and real example probes |
| `AELAB_TEST_DAEMON=1 python3 Scripts/ssh-fixture-smoke.py` | CLI daemon initialization/start without OS service changes, then the full suite with one SSH host, one direct daemon and native localhost |
| `python3 Scripts/daemon-smoke.py` | Direct TLS without SSH: pairing, certificate/auth/Origin rejection, multiplexed commands, discovery/plugins, native PTY/resize, timeouts and protocol bounds |
| `python3 Scripts/daemon-launch-smoke.py` | CLI/wrapper daemon-only builds, first setup, pairing export, duplicate-start refusal, preserved credentials, all-target installation without startup and installed TLS operation without checkout; builds are recorded stand-ins |
| `python3 Scripts/terminal-files-smoke.py` | Real local/SSH/daemon file dropping, screenshot pasting, native TUI image placeholders, binary integrity/private permissions, shell quoting, batch paths, authorization/size limits, cancellation, and partial-upload cleanup without production homes |
| `python3 Scripts/base-path-smoke.py` | Nested runtime prefix, browser assets/deep links, scoped auth cookies, Origin checks, API docs and real terminal WebSocket |
| `AELAB_TEST_BROWSER_SCRIPT=grid-browser-smoke.mjs python3 Scripts/base-path-smoke.py` | Stretching cards with a 384px minimum, unlimited columns (tested through ten) in all sections/discovery, left-aligned host header, inline pinned shortcuts, shell counts, discovery refresh, per-host theme, row badge alignment, footer centering, reordering, narrow-screen fallback and long-label wrapping |
| `AELAB_TEST_BROWSER_SCRIPT=program-status-browser-smoke.mjs python3 Scripts/base-path-smoke.py` | Real PTY capability replies, program progress/input requests, tab titles and pinned card badges, background status after tab close, validation, prompt/reset/exit lifetimes and pinned replay |
| `AELAB_TEST_BROWSER_SCRIPT=pin-responsiveness-browser-smoke.mjs python3 Scripts/base-path-smoke.py` | Pin/unpin/exit cross-tab updates during blocked host probes, immediate numeric launches and terminal startup without dashboard section reads |
| API contract checks | HTTP route coverage, schema references, required path parameters, unique operations, sorted output and synchronized embedding |
| `python3 -m unittest discover -s Scripts -p 'test_launcher.py'` | Wrapper service/build/clean flags, warm-cache reuse, source/lock/mode/environment invalidation, output integrity, failed-step retries, relative paths and pairing delegation |
| `git diff --check` | Whitespace |

The HTTP/browser scripts use debug binaries built by `swift test`. SSH/browser checks require OpenSSH, tmux and Chromium; set `AELAB_TEST_BROWSER` to a Chromium executable when needed. Automated browser coverage uses Chromium on macOS. User-service tests cover generated systemd/launchd definitions, literal paths/environment, owned-definition updates, collision refusal and recorded manager activation/restart/failure without changing real services. Linux systemd and macOS launchd lifecycle acceptance on a real user manager remains manual.

## Manual acceptance

- Exercise lifecycle operations and logs on disposable systemd units, launchd jobs, Docker containers and Compose stacks. Verify native permissions, launchd domains and application logs.
- Verify native daemon installation and user services on disposable Linux/macOS hosts; test firewall/Tailscale reachability, certificate renewal and credential revocation manually.
- Check Linux installation/container packaging and independent physical hosts with different service stacks. Local SSH fixtures verify routing, not every target platform.
- Check Safari, Firefox and mobile clipboard permissions and terminal layout.
- Review packaging paths and the service account’s SSH identity or supervised agent socket before deploying.

See [Installation](Installation.md) for setup and [Specification](Specification.md) for supported behavior and planned work.

Tmux pin acceptance: `python3 Scripts/tmux-pins-smoke.py` uses an isolated home and owned tmux socket to verify pinning from the tty header, one-card display, native session URLs, keyboard shortcuts, filters, CSRF, rename preservation, unpinning through an All-view terminal without ending tmux, and deletion cleanup.

Pin login lifetime: `AELAB_TEST_BROWSER_SCRIPT=pin-login-browser-smoke.mjs python3 Scripts/tmux-pins-smoke.py` verifies native and tmux pins retain IDs and numbers through logout, a signed-out reaper pass, and a fresh login. It checks immediate client disconnection, rejected old cookies, and resuming a shell variable from the same process. Unit tests also verify selective client disconnection and credential-reset invalidation.

Tmux restart acceptance: `AELAB_TEST_RESTART=1 AELAB_TEST_BROWSER_SCRIPT=tmux-restart-browser-smoke.mjs python3 Scripts/tmux-pins-smoke.py` restarts an isolated server while its owned tmux socket stays alive, then verifies shortcut IDs/numbers, keyboard attachment, native-pin removal and saved unpinning. Unit tests cover private file permissions, number reservations, persisted cleanup, duplicate-state rejection and failed-write atomicity.

Dialog Escape acceptance: with the frontend dev server running, `AELAB_TEST_ORIGIN=http://127.0.0.1:5173 node Scripts/dialog-escape-browser-smoke.mjs` checks create/edit forms, configuration and plugin editors, unsaved-change confirmation, busy editors and nested directory pickers using mocked APIs.

Matrix rain: with the frontend dev server running, `AELAB_TEST_ORIGIN=http://127.0.0.1:5173 node Scripts/matrix-rain-browser-smoke.mjs` verifies button placement, the exact alphabet, host/theme colors, live animation, keyboard font controls without visible chrome, glyph-cache reuse, 320–2560px viewport coverage, modal focus/isolation, password-field shortcuts, pause/resume, password-gated dismissal and cleanup and standalone renderer reuse. It writes dark/light preview screenshots to `/tmp/aelab-matrix-{dark,light}.png`. Unit tests cover stream timing, mutation, recycling, resize continuity, lane sizing and bounds. Manual acceptance still includes other browsers and physical mobile/large-display performance. Reuse examples and the component contract live in `Frontend/src/matrix-rain/README.md`.

Matrix lock acceptance: `AELAB_TEST_BROWSER_SCRIPT=matrix-lock-browser-smoke.mjs python3 Scripts/base-path-smoke.py` checks the real mounted server: unchanged cookie/session, continued API reads/mutations and background polling, the same unpinned shell PID and socket before/during/after the overlay, ongoing terminal input/output, password/rate-limit/CSRF checks, reload and tab UI state, mobile form layout, offline confirmation and separate Exit cleanup. It writes a mobile preview to `/tmp/aelab-lock-mobile.png`.
