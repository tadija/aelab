import Core
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
        var homePath = ProcessInfo.processInfo.environment["AELAB_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".aelab").path
        if args.first == "--home" { guard args.count > 2 else { throw AEError("--home requires path and command") }; homePath = args[1]; args.removeFirst(2) }
        guard let action = args.first else { usage(); return }; args.removeFirst()
        if ["help", "--help", "-h"].contains(action) { usage(); return }
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
            try location.install(source: source)
            print("Installed CLI: \(location.bin.appendingPathComponent("aelab").path)")
            print("Installed daemon: \(location.bin.appendingPathComponent("aelab-daemon").path)")
            print("Installed server: \(location.bin.appendingPathComponent("aelab-server").path)")
            print("Dashboard assets: \(location.application.appendingPathComponent("current/public").path)")
            print("Add \(location.bin.path) to PATH if needed; then use aelab help or aelab run. The checkout is only needed for source updates.")
            return
        }
        var runPort = ProcessInfo.processInfo.environment["AELAB_PORT"] ?? "2108"
        if action == "run" {
            while !args.isEmpty {
                guard args.count >= 2 else { throw AEError("Use run [--home PATH] [--port PORT]") }
                let flag = args.removeFirst(); let value = args.removeFirst()
                if flag == "--home" { homePath = value }
                else if flag == "--port" { runPort = value }
                else { throw AEError("Unknown run option: \(flag)") }
            }
            guard !homePath.isEmpty, let port = Int(runPort), (1...65535).contains(port) else { throw AEError("Invalid run home or port") }
            runPort = String(port)
        }
        let home = URL(fileURLWithPath: homePath); let store = try ConfigStore(home: home); let ops = Operations(store: store, initiator: "local-cli")
        func require(_ count: Int) throws { guard args.count >= count else { throw AEError("Missing arguments; see aelab help") } }
        func printJSON<T: Encodable>(_ value: T) throws { print(String(decoding: try jsonEncoder.encode(value), as: UTF8.self)) }
        switch action {
        case "run":
            let server = RuntimePaths.executable.deletingLastPathComponent().appendingPathComponent("aelab-server")
            let assets = ProcessInfo.processInfo.environment["AELAB_PUBLIC"] ?? RuntimePaths.publicDirectory
            guard FileManager.default.isExecutableFile(atPath: server.path), FileManager.default.fileExists(atPath: URL(fileURLWithPath: assets).appendingPathComponent("index.html").path) else { throw AEError("Server or dashboard assets missing; use ./.ae run or ./.ae install") }
            try await store.initializeIfNeeded(template: RuntimePaths.initialConfiguration())
            if !FileManager.default.fileExists(atPath: home.appendingPathComponent("state/admin.json").path) {
                try await Authentication(home: home).bootstrap(password())
            }
            let base = try WebBasePath(ProcessInfo.processInfo.environment["AELAB_BASE_PATH"] ?? "")
            let origin = ProcessInfo.processInfo.environment["AELAB_ORIGIN"] ?? "http://localhost:\(runPort)"
            setenv("AELAB_HOME", home.path, 1); setenv("AELAB_PORT", runPort, 1)
            setenv("AELAB_ORIGIN", origin, 1); setenv("AELAB_PUBLIC", assets, 1)
            print("Starting aelab at \(origin)\(base.value.isEmpty ? "" : base.root) (Ctrl+C to stop)"); fflush(nil)
            var mask = sigset_t(); sigemptyset(&mask); _ = pthread_sigmask(SIG_SETMASK, &mask, nil)
            // getpass/runtime signal dispositions must not make the foreground server ignore Ctrl+C.
            _ = signal(SIGINT, SIG_DFL); _ = signal(SIGTERM, SIG_DFL)
            _ = signal(SIGHUP, SIG_DFL); _ = signal(SIGQUIT, SIG_DFL)
            let pointer = strdup(server.path); defer { free(pointer) }
            var argv = [pointer, nil]
            _ = argv.withUnsafeMutableBufferPointer { execv(server.path, $0.baseAddress!) }
            throw AEError("Cannot execute aelab-server")
        case "init":
            if args == ["--if-needed"] { try await store.initializeIfNeeded(template: RuntimePaths.initialConfiguration()) }
            else { guard args.isEmpty else { throw AEError("Use init [--if-needed]") }; try await store.initialize(template: RuntimePaths.initialConfiguration()) }
            print("Configuration ready at \(homePath)/config/aelab.json; execution transport is explicitly configured; use aelab admin bootstrap if needed")
        case "admin":
            try require(1); guard ["bootstrap", "reset"].contains(args[0]) else { throw AEError("Use admin bootstrap or reset") }
            let entered = try password(); let auth = Authentication(home: home)
            if args[0] == "bootstrap" { try await auth.bootstrap(entered) } else { try await auth.reset(entered) }
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
        case "daemon":
            try await DaemonCommands.run(args, store: store)
        case "plugins":
            try require(1); let config = try await store.read().config; try printJSON(config.enabledPlugins(config.host(args[0])))
        case "probe":
            guard args.count == 2 else { throw AEError("Use probe HOST PLUGIN") }
            let observation = try await ops.probePlugin(host: args[0], plugin: args[1]); try printJSON(observation)
            if observation.error != nil { exit(1) }
        case "hosts": try printJSON(await store.read().config.hosts)
        case "ssh-candidates":
            let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
            let lines = try String(contentsOf: path, encoding: .utf8).split(separator: "\n")
            for line in lines { let fields = line.split(whereSeparator: { $0.isWhitespace }); if fields.first?.lowercased() == "host" { for alias in fields.dropFirst() where !alias.contains("*") && !alias.contains("?") && !alias.hasPrefix("!") { print(alias) } } }
            print("Candidates only; approve destinations in config before use. Include files may contain additional aliases.")
        case "tools":
            try require(1); try printJSON(await ops.discoverTools(args[0]))
        case "status", "services", "sessions":
            try require(1); let observation = try await ops.observe(args[0])
            if action == "sessions" { try printJSON(observation.tmux) }
            else if action == "services" { try printJSON(observation.discovered) }
            else { try printJSON(observation) }
            if !observation.reachable { exit(1) }
        case "start", "stop", "restart", "logs", "service-status":
            try require(2); let result = try await ops.service(args[0], id: args[1], operation: action == "service-status" ? "status" : action)
            print(result.output); if !result.error.isEmpty { FileHandle.standardError.write(Data(result.error.utf8)) }; if result.status != 0 { exit(1) }
        case "tty":
            try require(1); var launch = TerminalLaunch(host: args[0]); var i = 1
            while i < args.count {
                switch args[i] {
                case "--persistent": launch.persistent = true
                case "--yolo": launch.yolo = true
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
    static func usage() {
        print("""
        aelab [--home PATH] COMMAND
          run [--home PATH] [--port PORT]   start installed/built server without rebuilding
          install --source REPOSITORY [--prefix PATH]
          init [--if-needed]            initialize with localhost (never replaces existing entries)
          admin bootstrap|reset        local administrator credentials/recovery
          config show|validate|apply FILE
          hosts | ssh-candidates       approved hosts / unapproved SSH aliases
          status|services|sessions|tools HOST
          service-status|logs HOST SERVICE
          start|stop|restart HOST SERVICE   explicit remote mutation
          plugins HOST | probe HOST PLUGIN
          Names determine URL IDs (for example, Dev Server → dev-server).
          tty HOST [--project ID] [--tool ID] [--session NAME] [--persistent] [--yolo]
          daemon pair HOST --file PAIRING.json
          doctor                       configuration and read-only host diagnostics
        Repository build/start/update: ./.ae run [--debug | --configuration debug|release] [--home PATH] [--port PORT]
        Install release binaries and assets: ./.ae install [--prefix PATH]
        Install only this host’s daemon: ./.ae daemon-install --endpoint https://HOST:1984 [--service]
        Uses shared core and explicit local/SSH/daemon execution; no running dashboard required.
        """)
    }
}
