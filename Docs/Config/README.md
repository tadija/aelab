# Configuration

Start with `aelab init` and use [aelab.example.json](aelab.example.json) as a reference. Configuration lives at `$AELAB_HOME/config/aelab.json`; credentials, audit records and dashboard section state live in `state/`.

Schema `version: 1` defines shared `tools`, `plugins`, `paths` and `ttyButtons`. Projects use `dir` for their absolute path, for example `{"name":"aelab","dir":"/srv/aelab"}`. Each host owns its projects/services and lists the tool/plugin IDs enabled there. Definitions contain only a name; URL IDs are derived from it. Renaming changes links and forms update references together. Both forms and file editors validate changes and reject stale saves.

Shared `paths` prepend literal absolute directories to PATH on every host. Tool discovery checks executable availability without running candidates. Project directories override tool working directories. Plugin scripts may use `~/` for each host user’s home; see [Plugins](../../Plugins/README.md) for paths, deployment and the probe contract.

Hosts select `local`, `ssh` or `daemon` explicitly. Daemon pairing adds a `daemon` connection UUID; private endpoint/certificate/token material stays in `state/daemons`, outside the main file. Use `aelab daemon pair` as described in [Daemon hosts](../Daemon.md).

Keep keys, passwords and environment secrets out of configuration and version control. See [Installation](../Installation.md) for runtime settings.
