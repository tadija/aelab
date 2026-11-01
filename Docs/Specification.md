# aelab specification

aelab is a self-hosted web interface and CLI for a personal lab. Manage local, SSH and optional paired TLS daemon hosts from one central instance. SSH hosts need no aelab installation. This document defines current product behavior and implementation constraints.

## Architecture

- One Swift executable provides the CLI, Hummingbird server and optional host daemon. Server and Daemon are modules compiled into that executable; Core shares operations and CPTY provides native terminal support. The web interface uses Svelte, TypeScript and xterm.js.
- JSON configuration and small state files; no database or required host installation for SSH.
- Snapshot compiled dashboard assets at server startup; checkout rebuilds take effect after a restart, keeping the running frontend/backend together.
- Keep typed entity forms and shared editor behavior in dedicated frontend components; centralize configuration writes.
- Keep authentication, configuration, host HTTP routes and terminal WebSocket handling in dedicated server components; `ServerRuntime` wires them together and owns application shutdown.
- Explicit host transport: `local` uses the server process identity; `ssh` or omitted transport uses SSH; `daemon` uses paired direct TLS. The name is unrestricted by transport; renaming a local host must not add a second default host. Never infer local execution from an address.
- Local, SSH and daemon transports share operational adapters, authorization, validation, limits and auditing. Never elevate privileges implicitly.
- SSH uses noninteractive key/SSH agent authentication and strict known-host verification, without agent forwarding. Use the configured destination, never the display name or derived ID, for SSH commands and terminals. Respect approved OpenSSH configuration and keys.

Scope is host operations and interactive terminals, not a general monitoring, deployment, Git-hosting or CI/CD platform. No plugin marketplace, arbitrary frontend injection, federation, self-update protocol, cross-platform builder or automatic rollback.

## Configuration

The source of truth is `$AELAB_HOME/config/aelab.json`, schema `version: 1`. Root collections are `hosts`, `tools`, `plugins`, `paths` and `ttyButtons`. Tools/plugins are defined once centrally. Hosts own projects/services and hold `tools`/`plugins` arrays of enabled IDs. Empty collections may be omitted. Reject unknown configuration keys, invalid references and unsupported versions; ship no compatibility aliases or automatic migrations.

- Hosts: name, transport, SSH destination/port where applicable and optional tint/background. Local hosts omit destination/port. New homes include an explicit local localhost host.
- Shared `paths`: up to 64 unique absolute directories, prepended literally to inherited PATH on every host for discovery, operations and terminals. Reject colons/control characters; never evaluate shell expressions. Set Homebrew paths first.
- Projects: name, absolute path under `dir`, optional stable tmux session.
- Services: name, provider (`systemd`, `launchd`, `docker`, `compose`), native target, with no terminal project/tool references. Compose adds absolute directory/files/environment-file paths; systemd may explicitly select user units or `sudo -n` for lifecycle actions.
- Tools: name, executable, argument array, optional ALT and YOLO argument presets, and directory. Treat configured commands as trusted administrator input.
- Discovery checks every central tool definition without running its executable. Keep separate presets even when they resolve to the same file. Per-host enablement never copies or edits definitions. Disabling prevents direct API/CLI launches as well as hiding project/menu shortcuts. Plugin availability checks interpreter/executable and configured script files without running probes.
- Persist only names for hosts, projects, services, tools and plugins. Derive URL IDs by Unicode compatibility decomposition, removing combining marks, lowercasing and joining ASCII letters/digits with hyphens. Require 1–64 URL characters and reject collisions within each collection; order never affects IDs. Renaming changes URLs. Forms update enabled selections in the same revision-checked save; direct file edits must update references too. Preserve configured paths and native tmux session names. A uniquely matched dashboard host rename with unchanged execution connection preserves owned pins and pending tickets; file saves also preserve section state; ambiguous or changed connections never transfer terminals. Browser theme/tint preferences follow form renames.
- Validate syntax, structure, IDs, paths, colors and references. Bound configuration size and entity counts.
- Forms, CLI and the file editor share atomic revision-checked writes. Refuse stale saves; preserve credentials and unrelated files.

## Dashboard

### Appearance and navigation

Show dashboard and host-connection errors above the host picker. Use clear offline/unreachable wording for failed server requests, preserve authentication during network failures, and use the dashboard double-circle brand on login. Keep the password input and Sign in button inline, with an accessible input name but no visible field label or setup footer. Give menu rows visible contrast; show platform before hostname and use subtle background chips for host labels, paths and counts in both themes.

On login, place the aelab brand and “central host instance” label on a single row with a vertical separator matching the dashboard host header. Preserve the single-row layout on narrow screens.

Use the established warm light/dark design, system UI fonts and SF Mono/Menlo terminal stack. Host tint and theme are remembered per host; terminal backgrounds are separate preferences. Overview tint matches the disabled gray tint button. Selected host names are bold white; unselected names are gray.

Use a double-circle tint control (20px outer diameter, 3px ring, 6px inner dot). Keep icons consistent, keyboard accessible and labeled/tooltipped, with one checkmark for enablement and pinning. Tool/plugin controls share the neutral styling of project/service actions. Titles use 1.2rem, subtitles calc(.97rem - 1pt), and project tool buttons .92rem, with monospaced path/count chips. Service action labels are 1pt smaller with padding that keeps actions on one row in two-column cards.

Place the selected host controls after the aelab brand, left-aligned with a small gap and separator, keeping theme/settings/sign-out actions at the right: detected platform (macos/linux/wsl), hostname button opening the host editor, then +. On narrow screens, place the host controls on a left-aligned second row. Leave one line of spacing before the Hosts row. Align the Hosts picker label to the leading edge. The menu offers Shell, explicit tmux, then configured YOLO tools. New host shells and tmux sessions start in the selected host user’s home directory. Close it on outside tap/click or Escape.

The host picker begins with `all`, followed by host names and add-host. Overview host cards support edit/delete. Confirm deletion of a host and its nested configuration, and enabled selections; do not stop its running programs.

### Host status and shells

Check host status immediately on entering All; keep the previous reachability label visible during refreshes, showing checking only before the first result. Prevent concurrent checks for a host, and skip automatic checks within ten seconds of the last completion. Retain the fifteen-second visible-page polling interval and allow explicit refresh regardless of result age; disable the overview refresh button while checks are active. Overview refreshes omit tool/plugin inventories.

Integrate Shells below the host picker, using the same panel background and small muted labels. The aligned chevron, active host button and row background toggle the panel; other host buttons select their host. Use the hostname menu for new shells, with no separate Shells + action or collapse control. Keep empty messages aligned with the panel heading. Show “No active tmux sessions” for an empty/missing server, while preserving permission, missing-executable and connection errors.

Tmux cards show the session name, a blue TMUX badge on the subtitle line, window/client counts, Rename and confirmed Delete. Rename validates names, refuses native collisions and preserves attachments; old links need updating. Delete ends that exact session and its programs. Shell filters, pin ownership and shortcuts are defined under Terminals. Omit redundant host detail cards and last-checked footers.

All shows Hosts followed by a collapsible Shells section with the administrator’s pins across configured hosts. Reuse host shell cards, replacing PINNED with a host-tinted badge linking to that host. Reconnect/delete through each card’s host. Apply the pin refresh policy to every host on entry, focus, terminal events and visible two-second polling. All assigns unique sequential shortcuts across the combined list; individual host views retain native pin numbers. No extra session storage is needed.

### Projects, tools and plugins

The main sections are Projects, Tools, Plugins and Services, in that order. Project titles attach to their configured tmux session, creating it in the project directory if absent; otherwise they open a temporary native shell. Native tool and YOLO launches start pinned, from project buttons or standalone tool cards.

Project cards have a title/actions row, a path/branch metadata row, and a footer with tool buttons and the trailing drag handle. Omit redundant shell/tmux buttons. Place the per-project YOLO toggle immediately before Edit; it filters to approved YOLO tools and launches their bypass preset without confirmation. Tool card actions are YOLO, Edit and the rightmost host toggle or local Delete; omit tmux actions. Standalone directory selection and ALT/YOLO arguments are defined under Terminals.

Pinned-shell, project and tool paths show their last two components by default. Click or use the keyboard to toggle the full path; always provide it in a tooltip. Keep the label to one line and scroll longer text horizontally so expansion never changes card height. Tools show the resolved executable path when available, independently of discovery filtering. Let the adjacent Git branch badge use its natural width and wrap to at most two lines, preserving room for a usable path field.

Refresh Git branches with host status through the selected transport, using read-only metadata and a short timeout. Omit branch badges for non-repositories, detached HEAD or unavailable Git. Preserve branch case and full-name tooltips. Project creation explicitly ensures the directory exists, reporting native permission failures without sudo.

Plugin rows show “Run on demand” until a result is available. Each plugin row has Script, Edit definition and a rightmost enable/disable or local-only Delete icon. Group Script with edit and delete controls on the right, aligning actions with the title’s top edge and wrapping controls or titles when needed in grid cards. Script opens that row's configured source directly, without a file picker; disable it when no readable supported source exists on the selected host. Plugin titles run the probe directly; omit separate Run buttons.

### Discovery and configuration updates

Tool availability comes only from the cached tool inventory, not periodic host status probes.

Tools and Plugins default to enabled definitions; the filter beside + reveals all central definitions, availability badges and per-host checkmarks. New definitions stay disabled. The UI enables only available entries; the backend validates enablement and executable/path availability on every launch. Refresh appears beside the filter only in discovery mode. Tools use a five-minute inventory cache; plugin availability refresh never runs probes. Omit checked/cache footers and automatic installation.

In enabled rows, the rightmost × deletes a shared definition from all hosts only on an explicit local host, with confirmation; on remote hosts it disables that host’s selection. Discovery checkmarks toggle selections. Deletion clears enabled IDs; neither operation deletes files or stops programs.

Serialize configuration reads/writes. Apply toggle intents to the latest snapshot, retry one genuine external revision conflict without overwriting unrelated edits, keep full-form saves revision-bound and block duplicate pending clicks per row. Enablement changes do not trigger rediscovery.

Services keep host-specific configured/discovered views, a native status filter defaulting to running, case-insensitive search across names/providers/states, one matching/total count, and refresh beside the active discovery filter.

Installed badges on tools and plugins are hidden by default and appear in green only while that section’s discovery filter is active. Other states, including probe results and failures, retain their status colors.

Configured hosts, projects, tools, services and plugins support trailing drag handles, keyboard arrows and upward-opening move controls. Put handles on the metadata line, or beside project tool buttons. Persist ordered revision-checked config arrays without changing IDs, links or hidden definitions. Host order is central, tool/plugin order is global, and project/service order is host-specific. Live-session and native-discovery order stays unchanged.

Host forms omit the configuration-only `dockerContext` without dropping it on edit. Service forms label targets per provider: systemd unit, launchd target, container name/ID or Compose project name. Service titles show the same status result as Status; edit/delete sit at top right, the state badge beside the drag handle on the subtitle line. Explain user scope and noninteractive lifecycle sudo beside their checkboxes.

Main sections and the host-picker shell panel can collapse. Persist expansion per host, in `$AELAB_HOME/state/sections.json`, independently of the main configuration.

### Layout and feedback

Use dashboard cards with a 384px minimum that stretch evenly to fill each row, adding another column whenever it fits, without a maximum column count or dashboard width cap. Shrink cards to the available width on screens narrower than a card. Keep horizontal padding growing from 24px on phones to 48px on desktop. Apply this layout to hosts, shells, projects, tools, services/discovery and plugins. Keep card controls/design and DOM order. Forms, editors, directory trees and terminals retain their layouts.

Show a compact animated loader during initial loading, session checks, script loading and deployment; respect reduced-motion preferences.

Place uppercase semantic status badges left of the metadata-line drag handle, independently of host tint; project branch badges sit beside paths and wrap to at most two lines. Align titles/actions above them, with 16px gaps between content groups. OSC working status is yellow. Show unknown as “checking”; retain stale labels with yellow badges. Keep native errors visible, expire/refresh observations while visible, and never equate reachability or running with application health.

Center the dashboard footer on one line where space permits: `aelab · one central instance · local / SSH / daemon execution · files are the source of truth · API`, with aelab linking to `/` through dashboard navigation and API linking to the reference.

## Services

Support real status, bounded logs, start, stop and restart for curated systemd units, launchd jobs, Docker containers and Compose stacks. Compose start uses existing containers; never implicitly build, pull, create or remove stacks. Do not synthesize units or fake health when a provider is unavailable.

Detect the host platform before native service discovery: systemd on Linux/WSL, launchd on macOS; do not probe systemctl on macOS. Launchd discovery reads the caller’s bootstrap domain through documented `launchctl list` columns and uses full targets (`system/label`, `user/UID/label`, `gui/UID/label`). Jobs in other domains may be configured explicitly. Status exposes `launchctl print`; treat unrecognized diagnostic state text as unknown. Start/restart kickstart the exact job, bootstrapping its configured plist when unloaded; Stop bootouts the exact job and requires a readable matching plist so it can be loaded again. Verify the plist Label before mutations using it. Optional `plist` and `logFiles` accept absolute or `~/` host paths. Logs tail configured files (at most eight), otherwise show unified launchd lifecycle messages for that label. Read-only operations never use sudo; lifecycle sudo is explicit, noninteractive and scoped by the host. Never enable/disable whole domains or alter persistent launchd override state.

Hosts may set optional `dockerContext`, passed as an explicit Docker CLI flag consistently for discovery, curated container operations and Compose. Otherwise preserve the host user’s native context/environment. Do not guess sockets, switch saved contexts, launch a container runtime or modify Docker settings. Distinguish missing CLI from unavailable engine in the dashboard, retaining native details and permission/TLS/SSH failures.

## Terminals

Use the shared local/SSH/daemon PTY contract for temporary shells, project/tool launches and tmux attachment. Preserve ordinary shell line endings and job control so tmux can launch from a shell. Support binary terminal output, input, resize, interrupt, EOF, disconnect and cleanup through authenticated WebSockets. Preserve deep links, tmux windows/panes, clipboard controls and custom backgrounds. Create tmux sessions only for explicit tmux actions, configured project sessions or CLI --persistent. Saved-session links attach only and must fail rather than recreate a missing session. Canonical session URLs omit creation flags. Host-side tmux must survive browser disconnection and central restart; closing a browser session must clean up its owned transport processes without terminating tmux.

Dashboard browser tabs use `HOST@aelab` (overview uses `aelab`); terminal tabs use `tool@project.host` (or `shell@project.host` for plain shells), with the configured host display name as the suffix. Prefer the configured project display name; standalone launches use the launch directory’s last component, with the host name as a fallback. Tmux tabs use the session name before `@`.

Deep links include `/hosts/HOST/`, `/hosts/HOST/projects/ID/`, `/hosts/HOST/services/ID/`, `/hosts/HOST/tools/ID/`, and `/hosts/HOST/tty/tmux/SESSION/`. Launch parameters use `project`, `tool`, `persistent`, `alt`, `yolo` and standalone tool `directory`. CLI terminals use `--project`.

Standalone tools (normal and YOLO) use their default working directory immediately when configured; otherwise open the directory picker at host home. Never prompt for YOLO confirmation. Accept directory overrides only for enabled standalone tools; project tools always use the project directory.

Tool ALT presets: an optional `altArguments` array replaces normal `arguments` for that launch. Holding Alt highlights eligible project tool buttons, tool titles, and YOLO launch options with an overlaid ALT indicator, without changing card dimensions. Capture Alt at click time, preserve the choice through directory selection, and carry it in terminal links and requests; tools without a preset retain normal behavior. YOLO remains independent and appends `yoloArguments` to whichever base list was selected. The CLI supports `tty --alt`. Never accept arbitrary arguments from a launch request; validate ALT arrays with the same limits as other tool arguments.

### Header and program status

Match the reference header: monospace aelab host-root link, circular collapse control, host and cwd labels, trailing colored status light/text, pin control for ordinary terminals and key-bar toggle. The host label resets the background to the selected host’s configured Terminal background; only the cwd label opens a color picker. Precede the aelab header link with its double-circle logo, colored with the same host tint as the dashboard, independent of terminal background or cwd overrides. On narrow screens, put host and cwd on separate lines. Store cwd overrides per host and actual cwd in the browser, without browser-owned host overrides. All fresh launches inherit the host background unless that cwd has an explicit override. Header collapse leaves a small floating brand/expand control. Hide the key bar initially; its toggle reveals the shared configured tty buttons. Keep pin/collapse/key-bar controls keyboard accessible and trigger actual terminal resizing as layout changes. Resolve initial cwd from project/tool configuration or the host's pwd, and accept shell OSC 7 cwd reports where available.

Support OSC 7501 program reports in browser terminals with a bounded validated record store, capability replies and replay-safe input handling. Show the highest-priority report and progress in the browser tab title and on pinned session cards, with the pin number before the card title and a status badge after it. Keep the tty page free of an extra status footer. Observe bounded validated OSC reports on the server for retained PTYs so cards update even without an attached browser. Keep connection status separate and render report text as plain text. See [Program status](ProgramStatus.md) for protocol reference, lifecycle and transport limits.

### Shell lists and shortcuts

The host Shells filters are all, pinned, tmux and open, with a count for the selected filter. Open lists live unpinned native terminals, excluding tmux attachments; all includes them once. Open cards show the terminal title, path and program status, allow reconnecting to the same PTY or ending it, and have no pin number. Reconnecting does not pin the shell: its final client disconnect still ends it. Listings and reconnects are scoped to the administrator and host.

Pinning explicitly retains the existing ordinary PTY through browser disconnection, without creating tmux or restarting its program. Reattach through an owner-bound `/hosts/HOST/tty/pinned/ID/` URL and show native pins in the host's Shells list. Name pinned/open rows without the host suffix used in terminal tabs (`TOOL@PROJECT` or `shell@PROJECT`), using display names and the same source-directory fallback. Unpinning leaves connected clients running but closes the PTY after the last disconnect. A confirmed delete ends a retained PTY. Give each native pin a stable positive number for its lifetime. Allocate the lowest unused number and release it when the terminal ends, so numbering returns to 1 after all terminals close; keep numbers reserved for live unpinned terminals so repinning preserves their shortcut. Place PINNED at the right of the subtitle line; keep its number beside the title. Show pin numbers as circular buttons with host-tinted text and a translucent tint background, immediately before the title, with any OSC program status following the title; when Shells is collapsed, show them on the right of the Hosts button row, before the expand/collapse button, keeping the panel’s heading and buttons at the same vertical position; typing an unambiguous number opens that pin immediately on the selected host; only prefixes of longer numbers wait briefly, with Enter launching an exact match. Support multi-digit numbers, ignore shortcuts in forms/editable controls/modals or with modifiers, and use the same number pool for native terminals and explicitly pinned tmux sessions.

Refresh pin lists independently of remote host probes. Pin/unpin confirmations and terminal exits notify other tabs to fetch their own authorized pin list; refresh on focus and poll the selected visible dashboard every two seconds as a fallback. Terminal pages skip loading dashboard-only section state.

The tmux tty header uses the same pin button as native shells to assign a shortcut to the existing host/session without creating or retaining a PTY. Keep pin toggles off dashboard cards. Keep exactly one card in the tmux list, show its number before its title, retain the TMUX badge and include it when filtering to pins. Include pinned tmux sessions in All and collapsed host shortcuts, attaching through their original tmux URL. Unpinning does not end the session. Successful renames preserve the number; deletion and successful session discovery remove vanished shortcuts, while failed discovery preserves them. Ignore discovery snapshots that predate a pin or rename. The terminal WebSocket pin/unpin controls also manage tmux shortcuts; metadata reflects their pin state while the URL remains a tmux URL. Tmux shortcuts share administrator ownership with native pins and persist privately in `state/tmux-pins.json`, preserving their IDs and numbers across central restarts. Save changes atomically with mode 0600; reserve restored numbers before allocating new pins. Persist unpinning, renames, discovery cleanup and credential invalidation, and discard entries for removed hosts. Failed writes must leave the in-memory shortcut state unchanged. Tmux sessions themselves survive unpinning, logout and central restart.

### Ownership and resource bounds

Pins belong to the current administrator credentials and survive browser logout, login expiry and subsequent logins. Logout immediately disconnects only that login’s terminal clients and revokes its pending tickets; native pinned PTYs and tmux shortcuts remain. Reattaching always requires a current authenticated login. A local password reset invalidates the previous pin owner, and the reaper closes those native PTYs and removes its shortcuts. Native pins end on central shutdown. Native shell pins are memory-only; tmux shortcut metadata survives central restarts. Never convert an existing process silently into tmux.

Use one reader per PTY, at most 16 live PTYs/16 connected clients, a 256 KiB replay tail and bounded per-client queues (64 chunks); disconnect slow subscribers instead of growing memory. Mark replay frames and suppress terminal query replies while replaying history. Reauthorize active clients and reap pins when administrator credentials change. Never expose terminal output, pinned IDs or control paths without a current login. Audit pin/unpin/delete operations without terminal contents. Native pins keep their central administrator ownership across every transport; daemons reuse the same PTY contract.

### Key bar

The root `ttyButtons` is an ordered array of `{ "key": "ctrl-c", "label": "C-c" }` shared across all hosts. Button layouts come only from configuration, never Swift defaults. Keep each ttyButtons object on one line in example/generated configuration. Omission or an empty list means no buttons. Fresh CLI initialization seeds the local host and shared button list from the shipped example config; existing configurations are never overwritten. The example includes the reference navigation/control keys plus clipboard, reconnect, scrolling and tmux window/pane controls. Validate unique supported keys, short nonempty labels and at most 64 entries. Alt/Shift latch; Shift clears after input. Reload redraws the existing PTY without reconnecting. Tmux controls use the actual host prefix; Mouse sends its configured prefix binding. Optional controls include copy/paste/reconnect, scrolling, copy mode, tmux window/splits and ctrl-a through ctrl-z. Never evaluate button labels or arbitrary commands. Reserve bottom padding inside the terminal fit area so the last row remains fully visible.

### File transfer

Support file drops and screenshot pastes in every browser terminal, using authenticated raw uploads bound to the live terminal's administrator owner and original execution host. Stream browser data into a private bounded central spool, then save on local, SSH or daemon hosts; never treat image bytes as PTY input. Use one SSH stdin stream and bounded daemon file-begin/write/finish/abort messages, with offsets, size checks and disconnect cleanup. Restrict destinations to private unique directories under the host home .aelab/uploads; reject path components, control characters, symlink roots, overwrites, and files larger than 20 MiB. Admit at most four central uploads and four unfinished daemon uploads per connection; limit a UI batch to ten files. Recheck authorization and terminal liveness after receiving the body. Preserve completed user files across terminal, pin, tmux and server lifetimes; clean partial transfers and central spools automatically.

After each upload succeeds, paste one shell-quoted path as its own native paste, followed by a separate space, never Enter. Respect the application's bracketed-paste mode, bypass sticky key modifiers for file paths, and leave native attachment labels to the application. Preserve text paste and normal terminal traffic. Show a temporary drop target and upload progress/cancel control. Abort browser transfers on terminal unmount and do not paste results into a disconnected or replaced terminal. Keep bytes out of command arguments and logs; audit upload metadata only.

## Plugins

Plugins are trusted administrator-managed host executables, not a sandbox or remote daemon. Plugins provide on-demand probes. A central `plugins` definition contains name, executable, arguments, and timeout (default 10, range 1–30 seconds). Optional `source` identifies a file for editing/deployment; execution always uses the executable and arguments. Keep form helper text minimal. Name-derived IDs are global and change on rename. Use Plugins for configuration and explicit execution, and `aelab plugins HOST` / `aelab probe HOST PLUGIN` in the CLI. Never run plugins during discovery or background status polling.

Run the approved command plus `--aelab-probe` through the shared execution transport. Pass only `AELAB_HOST_ID` and `AELAB_PLUGIN_ID` as explicit context; never send credentials/config as input. Commands inherit their selected execution identity's permissions/environment. Script/interpreter paths belong to that host; no automatic upload, install or elevation. Authors must keep probes read-only.

Require zero exit and one JSON report: `version: 1`, `status` (`ok`, `warning`, `critical`, `unknown`), nonempty `summary` and `details` label/value pairs. Limit stdout reports to 64 KiB, summary to 512 bytes, details to 32 entries, labels to 128 bytes and values to 4096 bytes. Apply shared concurrency/output bounds, timeout and cancellation. Protocol/transport/exit failures remain visible and never become healthy status. Show escaped text and timestamps, never HTML or frontend code. Audit execution metadata, excluding reports, arguments and diagnostics. The probe API is authenticated and CSRF/Origin-protected; requests cannot supply executable commands or override arguments.

Ship working Bash (disk usage), Ruby (process count) and Swift (system uptime) examples with setup and protocol documentation. Examples must inspect real host data without mutating host state. Disk usage preserves Linux df capacity; on macOS calculate the rounded-up unavailable share from total minus available blocks, since APFS per-volume Used omits other volumes. Include the measurement scope in report details. Interpreter execution and compiled Swift binaries are both supported. Plugins are not enabled by default. See [Plugins](../Plugins/README.md).

## Daemon transport

The daemon runtime module shares Core and runs through `aelab daemon`. Hosts explicitly select `daemon` and reference private pairing state by UUID; keep credentials out of configuration/API responses. Persistent direct TLS WebSockets multiplex bounded command and PTY messages. Validate pinned certificates and endpoint hostnames; require private 256-bit tokens, refuse browser Origins and unsupported protocol versions. No SSH fallback or automatic mutation retries. Commands and terminals execute as the daemon account, through existing adapters and authorization, without implicit elevation.

The CLI pairs manually installed hosts after verifying direct TLS readiness, preserving host identity and selections. Limit concurrent clients/commands/PTYS, input/output and replay; cancel work and close native PTYs on disconnect. Keep tmux persistence, resizing, clipboard, background colors and deep links. Source editing/deployment and directory picking share the transport.

Preserve daemon settings and credentials after first setup; reject conflicting endpoint/bind options. Hold a process lock to reject duplicate foreground starts. The daemon shares the server’s explicit installation, update and user-service lifecycle. See [Daemon hosts](Daemon.md) for setup and current transport limitations.

## Authentication and safety

One administrator account, salted PBKDF2 password hashing, HttpOnly/SameSite cookies, expiring sessions, exact Origin and CSRF checks for mutations. Require TLS outside loopback. Terminal tickets are short-lived, owner-bound and single-use. Reauthorize active terminal connections; cap concurrency/output and enforce timeouts/cancellation.

Keep config, credentials, section state and audit files private; use atomic writes. Audit configuration changes, lifecycle actions, terminal opens and tmux deletion without recording secrets or terminal contents. Local reset revokes sessions. The editor and generated API documentation require authentication.

## Editors, directories and deployment

### Editors

The authenticated configuration editor opens only the running instance’s main file, never credentials. Both configuration and script editors use numbered, syntax-colored monospaced text, validation, save, useful errors and confirmed discard. Reopening loads current contents; omit reload buttons. Put Close last at the right with an exit icon distinct from deletion. Folding is a read-only preview; expand before editing and preserve raw formatting. Share a browser-persisted Wrap lines preference across editors/reloads, preserving source bytes, highlighting, line numbers, folds and scroll alignment. Configuration changes affect new operations without restart; existing terminals retain their context. Environment changes require restart.

Plugin script editing is authenticated and admin-only. Open only the selected plugin’s existing configured Bash/Ruby/Swift source file on the selected host: a script executable, a whole script argument, or an explicit `source` path for compiled plugins. The editor accepts only configured files and never creates them; explicit deployment is separate. Use the same numbered, syntax-colored editor with minimal chrome; use JSON folding only for JSON. Validate scripts with bash -n, ruby -c or swiftc -frontend -parse without executing them. Limit UTF-8 source to 64 KiB, reject symlinks, preserve permissions, serialize aelab writers, compare revisions/current contents, and atomically replace files. Expose useful syntax/save/conflict errors; compiled sources still need rebuilding. Audit metadata without source contents. Keep the main configuration editor to title, filename, editor and icon controls, with errors/status only when relevant.

Escape dismisses create/edit forms and the configuration/plugin source editors using their existing Cancel/Close behavior. Editors retain unsaved-change confirmation and remain open while busy; nested directory pickers close first without dismissing their parent form.

### Directory picker

The authenticated directory picker lists one level lazily through the existing execution transport under that identity, without sudo. Use it for project, Compose and default tool directories and standalone tool directory selection. Keep manual directory fields for new paths. Provide Home/Root/Up and expandable tree nodes, loading/errors/retry and an explicit Select directory action. Hide dot-prefixed folders by default and provide a Hidden folders toggle with a browser-persisted preference, applied at every tree depth. Clicking a folder name selects it and expands/collapses its children; show connecting tree lines and open/closed folder icons instead of separate arrow buttons. Return canonical absolute paths, include hidden directories, omit files and symlink entries, enforce a 256-directory cap and transport limits. An explicitly requested symlink path may resolve to its physical directory. Browsing is admin-only and limited to names of directories readable by the host account; no file-content browser or filesystem write endpoint.

### Plugin paths and deployment

Plugin executable/source paths and whole path arguments may use `~/...`, resolved from the selected host execution user’s HOME. Absolute local script paths resolve on SSH hosts to `~/.aelab/plugins/SCRIPT_NAME/FILENAME`; compiled plugins with an explicit source use the same remote directory for their absolute executable. Home-relative paths retain their configured layout. Bare PATH executable names remain supported. Reject ambiguous working-directory-relative executable/source paths and `..` in home-relative paths. Do not expand shell variables, other users’ tildes, globs or embedded argument expressions. Discovery, probes, source editing and deployment share these rules. Ship the three example definitions with home-relative script paths, disabled by default.

Offer explicit configured-source deployment from a local host to a remote host. Show its button beside the plugin title only for an unavailable plugin on an SSH or daemon host; keep script editing with the right-side row actions. Load the source/target preview automatically and when the source host changes, with no separate reload button. Reopen the dialog for a fresh preview. Show whether an existing file will be replaced. POST the preview with config/source/target revisions; reject stale plans and symlink targets, use a private temporary sibling plus atomic publication, and share the source editor’s writer lock. Keep existing file permissions; create new scripts as 0700 and new directories privately. Copy at most 64 KiB from configured Bash/Ruby/Swift sources; never accept arbitrary upload content/paths, copy binaries, install interpreters, enable/run plugins or build compiled sources automatically. Audit host/plugin/outcome without script contents.

## Build and installation

### CLI and launching

The CLI works independently of the web interface. Keep its overview grouped and concise; `aelab help COMMAND` and `COMMAND --help` provide syntax and examples without runtime initialization. Use `tmux HOST` for session listing, `service ACTION HOST ID` for status/logs/start/stop/restart, and top-level `bootstrap`/`reset` for administrator credentials. Do not retain removed command aliases.

`./.ae server [--configuration debug|release] [--home PATH] [--port PORT] [--service]` builds binaries and frontend, initializes a missing home/account, then launches the server. Default home: `~/.aelab`; port: 2108. `./.ae daemon` builds the unified executable and needs no frontend toolchain. First daemon start requires `--endpoint https://HOST:1984`; optional `--bind` defaults to `0.0.0.0`. Its default home is `$AELAB_HOME/daemon`. Installed `aelab server` and `aelab daemon` launch without rebuilding. Use `aelab pair HOST --file FILE` for central pairing and `aelab pairing --output FILE` for host-side export.

### Installation and services

`./.ae install` builds and copies one `aelab` executable and dashboard assets without starting processes or installing services. Both macOS and Linux use `~/.local/bin` and `$XDG_DATA_HOME/aelab` (default `~/.local/share/aelab`). Ignore empty or relative XDG values. `--prefix PATH` uses `PATH/bin` and `PATH/share/aelab`. Activate complete versioned releases atomically and refuse unrelated executable collisions. Preserve configuration/credentials. Installed operation needs no checkout or build tools; Linux still requires Swift runtime libraries. Keep the current release, one fallback and releases with open files; prune other releases after installation or with `aelab cleanup`. Skip pruning when process inspection is unavailable.

`server --service` and `daemon --service` share user-service generation and lifecycle code: systemd on Linux and launchd on macOS, no implicit sudo. Initialize credentials interactively before starting services. Capture effective launch settings and PATH, use absolute paths, escape provider syntax, write definitions privately and reject unrelated definitions/symlinks. Repeated calls update owned definitions and restart that service. Installed definitions follow the active current release. Preserve separate service identities, user-manager requirements and native stop/status/logging commands. Do not install services during `install`, pair or ordinary foreground launch.

Release is the wrapper default; debug builds use Swift debug and frontend development mode with sourcemaps. Keep build/install/service/update examples in README and platform details in Installation. Updates are explicit stop, pull, build/install, launch operations. Configuration and packaging templates remain under Docs/Config and Docs/Packaging.

### Version and build reuse

Track one Semantic Version in root `VERSION`. A build plugin generates Core metadata from VERSION and the checkout’s Git HEAD, preserving the generated file when values are unchanged. Support commits, branches and linked worktrees; never borrow an enclosing repository’s identity for a source archive. Without Git, use an optional Git-ignored `BUILD` file containing a full commit hash, or report unknown. Installed binaries never read the checkout or invoke Git.

`aelab --version` reports the release and seven-character build ID; `--build` reports the full hash. Both work before runtime initialization. The wrapper reads the same metadata without building. Session responses, the footer and served OpenAPI metadata report the compiled release/build, with the full hash on hover. Resolve OpenAPI VERSION/BUILD placeholders from Core. Keep protocol and configuration-schema versions independent; do not maintain another frontend application version.

Reuse Swift’s dependency/build caches and preserve unchanged generated API timestamps. Cache frontend dependencies by package/lock manifests, npm configuration, Node/npm versions, platform and relevant environment; cache verified assets by source content, build mode and Vite environment. Missing/changed inputs, tools, assets or cache metadata trigger the required work. Publish stamps only after success, serialize frontend builders and preserve caller-relative paths. Reuse matching binaries/assets/templates and repair a missing command link without republishing. `--clean` clears Swift products and forces applicable frontend dependency/build steps, preserving runtime homes and installed releases. Daemon builds need no Node/Python.

## HTTP API

The central server supports a runtime `AELAB_BASE_PATH` (default `/`), separate from the exact authentication origin. Mount HTTP/WebSocket routes, assets, deep links, API docs and cookie paths consistently; redirect the bare prefix to its trailing-slash root. Validate literal path segments and reject ambiguous prefixes. Preserve the prefix through the reverse proxy; no frontend rebuild is required.

Use resource-based URLs with direct JSON responses and no compatibility aliases. Configuration HTTP routes live in ConfigurationAPI and host HTTP routes in HostsAPI, each with a common authorization/error wrapper. Shared authorization and response helpers live in API.swift; terminal WebSocket handling stays separate.

- `GET/POST/DELETE /api/auth/session`: inspect login, sign in and sign out.
- `GET/PUT /api/config`: `{config, revision}`; `?format=source` selects `{content, revision}` for lossless editing. Both representations share revision checks. `POST /api/config/validation` checks `{content}` without saving.
- Host resources use `/api/hosts/{host}`. `GET/POST /tools` returns cached/refreshed inventory. `GET /plugins` includes availability and optional editable-source metadata; `POST /plugins/{plugin}/runs` executes an enabled definition. `/plugins/{plugin}/source` supports GET/PUT; its `/validation` accepts a source document and returns `{valid:true}`.
- `GET /services/{service}` reads status; `GET .../logs` reads logs; `POST .../actions` accepts `{action: "start"|"stop"|"restart"}`. No wildcard operation route.
- `PATCH/DELETE /tmux/sessions/{session}` renames/ends a session; `POST .../windows` creates a window. `GET /terminals` lists administrator-owned pins; DELETE addresses a specific pin. `POST /terminal-tickets` accepts launch options without a host field; the URL determines the host. Replies contain `ticket`, `prefix` and optional `session`, never an empty session sentinel. Connect to `/ws/terminals/{ticket}`. Browser deep links stay independent of HTTP API paths.
- `GET /directories?path=...` lists host directories (default home). `GET /plugins/{plugin}/source/deployment?from={localHost}` previews a script copy; POST to the same path submits that preview with revision preconditions.
- `POST /projects` prepares a supplied project directory; `/api/state/sections` reads/writes dashboard collapse state outside the main configuration.

Errors use `{error: {code, message}}`: missing/expired login is `401 authentication_required`, failed login `401 login_failed`, rejected Origin `403 origin_rejected`, missing/invalid CSRF `403 csrf_required`, invalid requests `400 invalid_request`, and stale saves `409 revision_conflict`. Syntax and configuration validation always precede persistence. Terminal request bodies cannot override URL host identity; window requests cannot override the session in the URL.

Maintain the explicit OpenAPI contract in `Docs/openapi.json`. Embed it with `Scripts/generate-api.py`; `--check` verifies route coverage, schema references, path parameters and synchronized output. Serve authenticated documentation at `/api/docs` and the schema at `/api/docs/openapi.json`, including request/response models, authentication, Origin/CSRF and conflict handling. Describe the terminal WebSocket protocol alongside HTTP endpoints. Generate paths and each path’s methods in alphabetical order. The reference page shares the dashboard palette stylesheet, system fonts and panel styling, with an overview-theme preference and light/dark toggle. Group host endpoints under one collapsed `/api/hosts/{host}` item, with Host & discovery, Plugins, Services and Shells subsections. Keep each operation independently expandable. Do not add a documentation framework.

## Matrix rain

A Lock icon sits between Configuration and Exit and opens a UI-only Matrix rain privacy overlay. Keep the dashboard and terminal components mounted. Background polling, API calls, WebSocket connections, terminal input/output protocols and running processes continue unchanged. Escape or clicking the rain reveals the same login form used on the ordinary login page; repeated Escape/clicks keep the overlay open. Dismiss it only after the server confirms the administrator password via `POST /api/auth/session/verify`. This confirmation shares password rate limiting but never rotates/revokes the cookie, extends session expiry or disconnects terminals. A wrong password returns `403 password_rejected` while the existing authenticated session remains valid. Exit retains its existing sign-out cleanup.

Store only the overlay’s colors, theme and initial font size in browser storage, scoped to the app URL prefix, and synchronize this UI state across tabs. Restore the overlay on reload while continuing the normal authenticated app underneath. The overlay does not restrict API/WS access or change authentication; normal login expiry still applies. If the session has actually expired, use ordinary sign-in to dismiss the overlay. Failed/offline password confirmation leaves it visible.

Use the selected host tint for the foreground (the default theme accent for All) and the current theme background. Default to 20px glyphs; plain +/− keys adjust by 2px within 8–64px, and 0 resets. Preserve browser zoom shortcuts and remember the chosen size while the app is mounted. Password input consumes its own characters, including +, − and 0; never treat typing in the form as rain shortcuts. Suppress dashboard pin shortcuts while the screensaver is active.

Keep the implementation portable in `Frontend/src/matrix-rain/`: a DOM-independent simulation, a canvas renderer usable without Svelte, a container-filling decorative component, and an optional fullscreen modal wrapper. Expose foreground/background CSS colors and font size as parameters, plus optional overlay content and accessible labels in the modal wrapper. Keep authentication in the embedding app, with no aelab, routing or backend dependencies inside the rain components. Use the original half-width katakana/numeral alphabet, independent stream lengths/speeds/acceleration/pauses and glyph changes, fading tails and contrasting leading glyphs. Adapt columns to available width and font size. Cache glyphs and trail opacity, preserve existing streams on viewport resize, reuse the glyph atlas when its font/palette/scale is unchanged, target 30 fps, bound the high-DPI backing buffer, pause when hidden and release every frame/observer/listener on unmount.

## Verification

Build the executable and frontend; run Swift and frontend tests. Use isolated homes, temporary SSH keys, disposable sshd endpoints and owned tmux sockets for integration. Test authorization boundaries, host scoping, literal arguments, persistence/conflicts, state isolation, PTY behavior, clipboard, resize, session deletion and tmux survival across central restart. Verify documentation generation stays synchronized. Never exercise lifecycle changes on production hosts or replace the running installation. Record unverified platform/provider acceptance in Verification.md.
