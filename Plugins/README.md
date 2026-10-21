# Host probes

Plugins are trusted administrator-managed executables. The first hook is an **on-demand probe**, available under Plugins and through `aelab probe HOST PLUGIN`. No automatic polling or privilege elevation happens. Explicit script deployment copies a reviewed configured source to an SSH host.

## Try an example

Copy the examples to a stable directory on the host you want to probe. For the central local host:

```sh
mkdir -p "$HOME/.aelab/plugins"
cp Plugins/disk-space.sh Plugins/process-count.rb Plugins/uptime.swift "$HOME/.aelab/plugins/"
```

Add definitions with the dashboard's **Add plugin** form, or add the root `plugins` array in the configuration editor:

```json
[
  {"name":"Disk space","executable":"/bin/bash","arguments":["~/.aelab/plugins/disk-space.sh"]},
  {"name":"Process count","executable":"ruby","arguments":["~/.aelab/plugins/process-count.rb"]},
  {"name":"Uptime","executable":"swift","arguments":["~/.aelab/plugins/uptime.swift"],"timeout":30}
]
```

Enable it on each host with its row checkmark, or set the host’s `"plugins": ["disk-space", "process-count", "uptime"]` IDs. The filter shows all central definitions or only enabled ones. For shared tools and plugins, the rightmost × in enabled rows deletes the definition from all hosts only on an explicit local host, with confirmation. On remote hosts, × only disables that host’s selection. Discovery checkmarks toggle selections. Neither action deletes files or stops programs. Definitions are shared; script/executable files must exist at their resolved paths on each enabled host. `~/` resolves against each selected host user’s home for the executable, whole script arguments and optional source path. Plain relative paths, `~otheruser`, parent traversal in home-relative paths and shell-variable expansion are unsupported. Other argument text stays literal. Bash reports root-filesystem capacity on Linux and shared APFS space unavailable on macOS (including other volumes/snapshots, without estimating purgeable space); Ruby counts visible processes, and Swift reports system uptime. Bash, Ruby or Swift must be available in that host's execution PATH; use absolute interpreter paths when needed. For Swift without a host-side compiler, build `swiftc Plugins/uptime.swift -o uptime` for that host's OS/architecture, then configure its executable with empty arguments. Installing a standalone script or binary is optional host setup, not an aelab daemon.

```sh
aelab plugins localhost
aelab probe localhost disk-space
```

## Contract

The core runs `EXECUTABLE ARGUMENTS --aelab-probe` using the configured local or strict SSH transport. Arguments remain separate and shell-quoted remotely. `AELAB_HOST_ID` and `AELAB_PLUGIN_ID` identify the approved configuration; no credentials or configuration document are sent as plugin input. The process still inherits its execution identity's environment and permissions: **this is not a sandbox**. Review scripts before approving them. Probe authors must keep the hook read-only.

Successful execution exits zero and writes one UTF-8 JSON object to stdout:

```json
{"version":1,"status":"ok","summary":"Everything observed","details":[{"label":"Metric","value":"42"}]}
```

- `status`: `ok`, `warning`, `critical` or `unknown`. These are plugin observations, independent of service state.
- `summary`: 1–512 UTF-8 bytes. `details` is an array of up to 32 plain-text label/value pairs (label 1–128 bytes, value up to 4096 bytes).
- Report limit: 64 KiB. Timeout defaults to 10 seconds, configurable from 1–30 seconds. Shared transport concurrency and capture limits also apply.
- Nonzero exit, timeout, truncated/oversized output or invalid protocol is a failed probe, never an OK result. Returned errors include category/exit status without raw stdout/stderr. Run the approved command manually under the same identity for private diagnostics.
- Dashboard renders escaped text only and shows the observation timestamp. Results are kept only in the current page; configuration persists. CLI prints the same observation and exits nonzero for execution/protocol failure; a valid warning/critical report is still a successful probe execution.

The authenticated `POST /api/hosts/HOST/plugins/PLUGIN/runs` requires Origin and CSRF. Clients choose only centrally configured IDs enabled on that host, not commands or arguments. Probes are audited by host/plugin/outcome without command arguments, reports or diagnostics. API models are documented at `/api/docs`.

Actions, log sources, specialized integrations and richer metadata remain future hooks; no marketplace or frontend code injection is supported.

Use a plugin row’s Script icon to open its existing configured `.sh`, `.bash`, `.rb` or `.swift` source. Script paths may be absolute or start with `~/`. On SSH hosts, absolute script paths use `~/.aelab/plugins/SCRIPT_NAME/FILENAME`. SCRIPT_NAME follows the script filename, so renaming a plugin leaves its files in place. Compiled executables use the same directory; local paths remain unchanged. For compiled executables, add `"source": "~/.aelab/plugins/uptime.swift"` to the plugin entry. The host needs the matching syntax checker (`bash`, `ruby` or `swiftc`) and `sha256sum` or `shasum` for saves. The editor checks syntax without running scripts, detects concurrent changes, and preserves file permissions on atomic saves. Editing compiled Swift source does not rebuild its executable. Clicking a plugin title runs its configured probe.

## Deploy a script

On an SSH host, open Plugins → Discovery and click the Deploy icon beside an unavailable plugin’s title. Installed plugins and local hosts hide this button. Choose an explicitly local source host, review the resolved paths, then Deploy script. Close and reopen for a fresh preview. The API also supports reviewed replacements. The same definition resolves `~` independently on each host. Only that configured Bash/Ruby/Swift source is copied (64 KiB maximum); no arbitrary upload path, interpreter installation, binary copying or automatic build. Existing permissions are preserved; new files are private and executable by their owner. Config/source/target revision checks reject stale previews and symlink targets. Deployment does not enable or run the plugin. Refresh availability, then enable it when ready. Compiled plugins still need a host-side build.
