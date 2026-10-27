import Core
import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

struct LaunchOptions {
    let kind: UserService.Kind
    var home: URL
    var port: String
    var endpoint: String?
    var bind: String?
    var service = false
    init(kind: UserService.Kind, arguments: [String], home: String?, environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        self.kind = kind
        guard home != "" else { throw AEError("Home path must not be empty") }
        let central = environment["AELAB_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".aelab").path
        self.home = URL(fileURLWithPath: home ?? (kind == .server ? central : URL(fileURLWithPath: central).appendingPathComponent("daemon").path)).standardizedFileURL
        port = environment["AELAB_PORT"] ?? "2108"
        var index = 0; var seen: Set<String> = []
        while index < arguments.count {
            let flag = arguments[index]
            guard seen.insert(flag).inserted else { throw AEError("Duplicate launch option: " + flag) }
            index += 1
            if flag == "--service" { service = true; continue }
            guard index < arguments.count, !arguments[index].isEmpty, !arguments[index].hasPrefix("--") else { throw AEError("Missing value for " + flag) }
            let value = arguments[index]; index += 1
            switch flag {
            case "--home": self.home = URL(fileURLWithPath: value).standardizedFileURL
            case "--port" where kind == .server: port = value
            case "--endpoint" where kind == .daemon: endpoint = value
            case "--bind" where kind == .daemon: bind = value
            default: throw AEError("Unknown \(kind.rawValue) option: \(flag)")
            }
        }
        if kind == .server {
            guard let number = Int(port), (1...65535).contains(number) else { throw AEError("Invalid server port") }
            port = String(number)
        }
    }
}

enum LaunchCommand {
    /// Installed services follow current/bin across release activation rather than pinning a UUID release.
    static func binary(_ name: String, cli: URL = RuntimePaths.executable) -> URL {
        let directory = cli.deletingLastPathComponent()
        let release = directory.deletingLastPathComponent()
        if release.deletingLastPathComponent().lastPathComponent == "releases" {
            return release.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("current/bin/" + name)
        }
        return directory.appendingPathComponent(name)
    }
    static func start(_ options: LaunchOptions) async throws {
        let env = ProcessInfo.processInfo.environment
        let executable = binary("aelab-" + options.kind.rawValue)
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw AEError("Executable missing; use ./.ae \(options.kind.rawValue) or ./.ae install") }
        var environment = ["PATH": env["PATH"] ?? "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin", "HOME": env["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path]
        var arguments: [String] = []
        if options.kind == .server {
            let installedAssets = executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("public")
            let defaultAssets = FileManager.default.fileExists(atPath: installedAssets.appendingPathComponent("index.html").path) ? installedAssets.path : RuntimePaths.publicDirectory
            let assets = URL(fileURLWithPath: env["AELAB_PUBLIC"] ?? defaultAssets).standardizedFileURL.path
            guard FileManager.default.fileExists(atPath: URL(fileURLWithPath: assets).appendingPathComponent("index.html").path) else { throw AEError("Dashboard assets missing; use ./.ae server or ./.ae install (or set AELAB_PUBLIC)") }
            let base = try WebBasePath(env["AELAB_BASE_PATH"] ?? "")
            let origin = env["AELAB_ORIGIN"] ?? "http://localhost:\(options.port)"
            let bind = env["AELAB_BIND"] ?? "127.0.0.1"
            guard let url = URL(string: origin), ["http", "https"].contains(url.scheme), url.host != nil, url.path.isEmpty,
                  url.scheme == "https" || (["localhost", "127.0.0.1", "::1"].contains(url.host!) && ["localhost", "127.0.0.1", "::1"].contains(bind)) else { throw AEError("Use an exact HTTP(S) AELAB_ORIGIN; non-loopback servers require HTTPS") }
            let store = try ConfigStore(home: options.home)
            try await store.initializeIfNeeded(template: RuntimePaths.initialConfiguration())
            if !FileManager.default.fileExists(atPath: options.home.appendingPathComponent("state/admin.json").path) { try await Authentication(home: options.home).bootstrap(CLI.password()) }
            environment.merge(["AELAB_HOME": options.home.path, "AELAB_PORT": options.port, "AELAB_ORIGIN": origin, "AELAB_PUBLIC": assets, "AELAB_BIND": bind, "AELAB_BASE_PATH": base.value]) { _, new in new }
            if let socket = env["SSH_AUTH_SOCK"] { environment["SSH_AUTH_SOCK"] = socket }
            if let config = env["AELAB_SSH_CONFIG"] { environment["AELAB_SSH_CONFIG"] = URL(fileURLWithPath: config).standardizedFileURL.path }
            print("Starting aelab at \(origin)\(base.value.isEmpty ? "" : base.root)\(options.service ? " as a user service" : " (Ctrl+C to stop)")")
        } else {
            if !FileManager.default.fileExists(atPath: options.home.path) {
                guard let endpoint = options.endpoint else { throw AEError("First daemon start requires --endpoint https://HOST:1984") }
                try await DaemonSetup.initialize(home: options.home, endpoint: endpoint, bind: options.bind ?? "0.0.0.0")
            } else {
                let settings = try DaemonSetup.settings(home: options.home); _ = try DaemonSetup.pairing(home: options.home)
                if let endpoint = options.endpoint {
                    var url = URLComponents(string: endpoint); if url?.port == nil { url?.port = 1984 }
                    guard url?.url?.absoluteString == settings.endpoint else { throw AEError("Endpoint differs from existing daemon settings; credentials were preserved") }
                }
                if let bind = options.bind, bind != settings.bind { throw AEError("Bind differs from existing daemon settings; credentials were preserved") }
            }
            arguments = ["--home", options.home.path]
            print("Starting aelab daemon at \(try DaemonSetup.settings(home: options.home).endpoint)\(options.service ? " as a user service" : " (Ctrl+C to stop)")")
        }
        fflush(nil)
        if options.service {
            try await UserService(kind: options.kind, executable: executable, arguments: arguments, environment: environment, home: options.home).start()
            return
        }
        for (key, value) in environment { setenv(key, value, 1) }
        var mask = sigset_t(); sigemptyset(&mask); _ = pthread_sigmask(SIG_SETMASK, &mask, nil)
        _ = signal(SIGINT, SIG_DFL); _ = signal(SIGTERM, SIG_DFL); _ = signal(SIGHUP, SIG_DFL); _ = signal(SIGQUIT, SIG_DFL)
        let pointers = ([executable.path] + arguments).map { strdup($0) }; defer { pointers.forEach { free($0) } }
        var argv = pointers + [nil]
        _ = argv.withUnsafeMutableBufferPointer { execv(executable.path, $0.baseAddress!) }
        throw AEError("Cannot execute " + executable.lastPathComponent)
    }
}
