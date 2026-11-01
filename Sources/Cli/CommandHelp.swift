import Core

/// Keep the overview brief; command help carries syntax and options.
enum CommandHelp {
    static let overview = """
    Usage: aelab [--home PATH] COMMAND

    Run
      server                    Start the dashboard
      daemon                    Start a host daemon
      tty HOST                  Open a terminal

    Inspect
      hosts                     List configured hosts
      status HOST               Show host status
      services HOST             Discover services
      tmux HOST                 List tmux sessions
      tools HOST                Discover tools
      plugins HOST              List enabled plugins
      probe HOST PLUGIN         Run a plugin
      doctor                    Check configuration and connections

    Manage
      service ACTION HOST ID    Inspect or control a service
      pairing --output FILE     Export this daemon's pairing credentials
      pair HOST --file FILE     Connect a daemon host

    Setup
      init                      Create configuration
      bootstrap                 Set the initial admin password
      reset                     Reset the admin password
      config                    View or update configuration
      install --source PATH     Install a built checkout
      cleanup                   Remove obsolete releases

    Options
      --home PATH               Use a custom runtime home
      --help                    Show help
      --version                 Show version
      --build                   Show build ID

    Use aelab help COMMAND for options and examples.
    """

    static let details: [String: String] = [
        "server": """
        Usage: aelab server [--home PATH] [--port PORT] [--service]

        Start the dashboard. First launch creates configuration and asks for an admin password.
          --home PATH    Runtime home
          --port PORT    Listen port (default: 2108)
          --service      Install or update a user service and restart it

        Example: aelab server --service
        """,
        "daemon": """
        Usage: aelab daemon [--home PATH] [--endpoint URL] [--bind ADDRESS] [--service]
               aelab daemon init --endpoint URL [--bind ADDRESS]

        Start a host daemon. First launch requires an HTTPS endpoint; later launches reuse it.
          --home PATH       Daemon runtime home
          --endpoint URL    Public HTTPS endpoint (default port: 1984)
          --bind ADDRESS    Listen address (default: 0.0.0.0)
          --service         Install or update a user service and restart it

        Example: aelab daemon --endpoint https://lab.example:1984 --service
        Export credentials with: aelab pairing --output pairing.json
        """,
        "tty": """
        Usage: aelab tty HOST [--project ID] [--tool ID] [--session NAME]
                             [--persistent] [--yolo] [--alt]

        Open a terminal on a configured host.
          --project ID      Start in a project
          --tool ID         Launch a configured tool
          --session NAME    Attach to a tmux session
          --persistent      Use tmux for a persistent session
          --yolo            Use the tool's YOLO arguments
          --alt             Use the tool's alternate arguments

        Example: aelab tty lab --project website --persistent
        """,
        "service": """
        Usage: aelab service ACTION HOST ID

        Actions: status, logs, start, stop, restart

        Example: aelab service restart lab web
        """,
        "pairing": """
        Usage: aelab pairing [--home PATH] --output FILE

        Export this daemon's private pairing credentials. Use --home for a custom daemon home.
        Transfer the file securely to the central machine, then use aelab pair.

        Example: aelab pairing --output pairing.json
        """,
        "pair": """
        Usage: aelab pair HOST --file FILE

        Verify a daemon connection and add or update its host configuration.

        Example: aelab pair lab --file pairing.json
        """,
        "init": "Usage: aelab init [--if-needed]\n\nCreate configuration with localhost. --if-needed reuses existing configuration.",
        "bootstrap": "Usage: aelab bootstrap\n\nSet the initial admin password interactively.",
        "reset": "Usage: aelab reset\n\nReset the admin password interactively and revoke existing sessions.",
        "config": "Usage: aelab config show|validate\n       aelab config apply FILE\n\nShow, validate or replace the configuration.",
        "install": "Usage: aelab install --source PATH [--prefix PATH]\n\nInstall a built checkout without starting services.\nFrom a checkout, use ./.ae install to build and install.",
        "cleanup": "Usage: aelab cleanup [--prefix PATH]\n\nRemove obsolete installed releases. Keep current, previous and active releases.",
        "hosts": "Usage: aelab hosts\n\nList configured hosts.",
        "status": "Usage: aelab status HOST\n\nShow host status.",
        "services": "Usage: aelab services HOST\n\nDiscover services on a host.",
        "tmux": "Usage: aelab tmux HOST\n\nList tmux sessions on a host.",
        "tools": "Usage: aelab tools HOST\n\nDiscover tools on a host.",
        "plugins": "Usage: aelab plugins HOST\n\nList enabled plugins on a host.",
        "probe": "Usage: aelab probe HOST PLUGIN\n\nRun a plugin and show its result.",
        "doctor": "Usage: aelab doctor\n\nCheck configuration and connections to configured hosts.",
    ]

    static func text(for command: String?) throws -> String {
        guard let command else { return overview }
        guard let text = details[command] else { throw AEError("Unknown command: \(command). See aelab help.") }
        return text
    }
}
