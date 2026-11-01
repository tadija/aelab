import Core
import Server
import Daemon
import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

@main struct CLI {
    static func main() async {
        do { try await run() } catch { FileHandle.standardError.write(Data("aelab: \(error)\n".utf8)); exit(1) }
    }
    static func run() async throws {
        var args = Array(CommandLine.arguments.dropFirst())
        if args == ["--version"] { print(AelabVersion.display); return }
        if args == ["--build"] { print(AelabVersion.build); return }
        if args.first == "__run-server" {
            try await ServerRuntime.run(); return
        }
        if args.first == "__run-daemon" {
            args.removeFirst()
            try await DaemonRuntime.run(arguments: args); return
        }
        var explicitHome: String?
        var homePath = ProcessInfo.processInfo.environment["AELAB_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".aelab").path
        if args.first == "--home" { guard args.count > 2 else { throw AEError("--home requires path and command") }; homePath = args[1]; explicitHome = homePath; args.removeFirst(2) }
        guard let action = args.first else { usage(); return }; args.removeFirst()
        if ["help", "--help", "-h"].contains(action) {
            guard args.count <= 1 else { throw AEError("Use aelab help [COMMAND]") }
            print(try CommandHelp.text(for: args.first)); return
        }
        if args.contains("--help") || args.contains("-h") {
            print(try CommandHelp.text(for: action)); return
        }
        guard CommandHelp.details[action] != nil else { throw AEError("Unknown command: \(action). See aelab help.") }
        if action == "cleanup" {
            var prefix: URL?
            if !args.isEmpty {
                guard args.count == 2, args[0] == "--prefix" else { throw AEError("Use cleanup [--prefix PATH]") }
                prefix = URL(fileURLWithPath: args[1])
            }
            print("Removed \(try Installation.location(prefix: prefix).cleanup()) obsolete releases; current, previous and active releases are retained.")
            return
        }
        if action == "install" {
            var source: URL?; var prefix: URL?
            while !args.isEmpty {
                guard args.count >= 2 else { throw AEError("Use install --source REPOSITORY [--prefix PATH]") }
                let flag = args.removeFirst(); let value = URL(fileURLWithPath: args.removeFirst())
                switch flag {
                case "--source": source = value
                case "--prefix": prefix = value
                default: throw AEError("Unknown install option: \(flag)")
                }
            }
            guard let source else { throw AEError("Use ./.ae install, or install --source REPOSITORY [--prefix PATH]") }
            let location = Installation.location(prefix: prefix)
            if try !location.install(source: source) { print("Installation unchanged; reusing the current release.") }
            print("CLI command: \(location.bin.appendingPathComponent("aelab").path)")
            print("Dashboard assets: \(location.application.appendingPathComponent("current/public").path)")
            return
        }
        if action == "daemon", args.first == "init" {
            args.removeFirst()
            try await DaemonRuntime.run(arguments: (explicitHome.map { ["--home", $0] } ?? []) + ["init"] + args); return
        }
        if action == "server" || action == "daemon" {
            try await LaunchCommand.start(LaunchOptions(kind: action == "server" ? .server : .daemon, arguments: args, home: explicitHome))
            return
        }
        if action == "pairing" {
            var daemonHome = explicitHome.map { URL(fileURLWithPath: $0) } ?? DaemonSetup.defaultHome
            var output: String?; var seen: Set<String> = []
            while !args.isEmpty {
                guard args.count >= 2, ["--home", "--output"].contains(args[0]),
                      !args[1].isEmpty, !args[1].hasPrefix("--"), seen.insert(args[0]).inserted else {
                    throw AEError("Use pairing [--home PATH] --output FILE")
                }
                let flag = args.removeFirst(); let value = args.removeFirst()
                if flag == "--home" { daemonHome = URL(fileURLWithPath: value) } else { output = value }
            }
            guard let output else { throw AEError("Use pairing [--home PATH] --output FILE") }
            let pairing = try DaemonSetup.pairing(home: daemonHome)
            try DaemonSetup.privateWrite(JSONEncoder().encode(pairing), to: URL(fileURLWithPath: output)); return
        }
        let home = URL(fileURLWithPath: homePath); let store = try ConfigStore(home: home); let ops = Operations(store: store, initiator: "local-cli")
        func require(_ count: Int) throws { guard args.count >= count else { throw AEError("Missing arguments; see aelab help") } }
        func printJSON<T: Encodable>(_ value: T) throws { print(String(decoding: try jsonEncoder.encode(value), as: UTF8.self)) }
        switch action {
        case "init":
            if args == ["--if-needed"] { try await store.initializeIfNeeded(template: RuntimePaths.initialConfiguration()) }
            else { guard args.isEmpty else { throw AEError("Use init [--if-needed]") }; try await store.initialize(template: RuntimePaths.initialConfiguration()) }
            print("Configuration ready at \(homePath)/config/aelab.json")
        case "bootstrap", "reset":
            guard args.isEmpty else { throw AEError("Use aelab \(action)") }
            let entered = try password(); let auth = Authentication(home: home)
            if action == "bootstrap" { try await auth.bootstrap(entered) } else { try await auth.reset(entered) }
            print("Administrator password saved")
        case "config":
            try require(1)
            switch args[0] {
            case "show": try printJSON(await store.read())
            case "validate": _ = try await store.read(); print("Configuration valid")
            case "apply":
                try require(2); let snapshot = try await store.readDocument()
                let config = try ConfigStore.validateDocument(String(contentsOfFile: args[1], encoding: .utf8))
                try await store.audit("config", host: "central", target: "aelab.json", outcome: "requested", initiator: "local-cli")
                try await store.write(config, expected: snapshot.revision)
                try await store.audit("config", host: "central", target: "aelab.json", outcome: "saved", initiator: "local-cli"); print("Configuration saved")
            default: throw AEError("Use config show|validate|apply FILE")
            }
        case "pair":
            try await DaemonCommands.run(args, store: store)
        case "plugins":
            try require(1); let config = try await store.read().config; try printJSON(config.enabledPlugins(config.host(args[0])))
        case "probe":
            guard args.count == 2 else { throw AEError("Use probe HOST PLUGIN") }
            let observation = try await ops.probePlugin(host: args[0], plugin: args[1]); try printJSON(observation)
            if observation.error != nil { exit(1) }
        case "hosts": try printJSON(await store.read().config.hosts)
        case "tools":
            try require(1); try printJSON(await ops.discoverTools(args[0]))
        case "status", "services", "tmux":
            try require(1); let observation = try await ops.observe(args[0])
            if action == "tmux" { try printJSON(observation.tmux) }
            else if action == "services" { try printJSON(observation.discovered) }
            else { try printJSON(observation) }
            if !observation.reachable { exit(1) }
        case "service":
            guard args.count == 3, ["status", "logs", "start", "stop", "restart"].contains(args[0]) else {
                throw AEError("Use service status|logs|start|stop|restart HOST ID")
            }
            let result = try await ops.service(args[1], id: args[2], operation: args[0])
            print(result.output); if !result.error.isEmpty { FileHandle.standardError.write(Data(result.error.utf8)) }; if result.status != 0 { exit(1) }
        case "tty":
            try require(1); var launch = TerminalLaunch(host: args[0]); var i = 1
            while i < args.count {
                switch args[i] {
                case "--persistent": launch.persistent = true
                case "--yolo": launch.yolo = true
                case "--alt": launch.alt = true
                case "--project", "--tool", "--session":
                    guard i + 1 < args.count else { throw AEError("Missing terminal option value") }
                    let flag = args[i]; i += 1
                    if flag == "--project" { launch.project = args[i] }; if flag == "--tool" { launch.tool = args[i] }; if flag == "--session" { launch.session = args[i] }
                default: throw AEError("Unknown terminal option")
                }; i += 1
            }
            let config = try await store.read().config
            try await ops.validateLaunch(launch, config: config)
            let (host, script, session) = try launch.resolve(config)
            try await store.audit("terminal", host: host.id, target: session ?? "temporary", outcome: "opened", initiator: "local-cli")
            // Replace the CLI with the selected transport to retain the invoking terminal's foreground group.
            if host.transport == .daemon { try await DaemonConsole.run(host: host, script: script, execution: ops.execution); return }
            let launchCommand = try ops.execution.terminalCommand(host, script: script)
            let pointers = ([launchCommand.executable] + launchCommand.arguments).map { strdup($0) }
            defer { pointers.forEach { free($0) } }
            var argv = pointers + [nil]
            var mask = sigset_t(); sigemptyset(&mask); _ = pthread_sigmask(SIG_SETMASK, &mask, nil)
            _ = argv.withUnsafeMutableBufferPointer { execv(launchCommand.executable, $0.baseAddress!) }
            throw AEError("Cannot execute terminal transport")
        case "doctor":
            let config = try await store.read().config
            print("Config valid: \(config.hosts.count) approved hosts. SSH verifies host keys; daemon connections verify pinned TLS certificates.")
            print("SSH agent socket: \(ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] == nil ? "not supplied (use protected key or stable agent socket)" : "supplied")")
            var failed = false
            for host in config.hosts { let result = try await ops.observe(host.id); print("\(host.id): \(result.connection.category)"); failed = failed || !result.reachable }
            if failed { exit(1) }
        default: throw AEError("Unknown command; see aelab help")
        }
    }
    static func password() throws -> String {
        // Password never appears in argv/environment/logs.
        guard isatty(STDIN_FILENO) == 1, let pointer = getpass("Administrator password (12+ characters): ") else { throw AEError("Password entry requires an interactive terminal") }
        return String(cString: pointer)
    }
    static func usage() { print(CommandHelp.overview) }
}
