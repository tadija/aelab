import Foundation

public struct HostIdentity: Codable, Sendable {
    public var hostname: String
    public var platform: String
    public static func parse(_ output: String) -> HostIdentity {
        let words = output.split(whereSeparator: \.isWhitespace).map(String.init)
        let kernel = words.first ?? ""
        let platform = kernel == "Darwin" ? "macos" : kernel == "Linux" ? (output.lowercased().contains("microsoft") || output.lowercased().contains("wsl") ? "wsl" : "linux") : "unknown"
        return HostIdentity(hostname: words.count > 1 ? words[1] : "unknown", platform: platform)
    }
}

public struct DiscoveryItem: Codable, Sendable {
    public var provider: Provider
    public var target: String
    public var state: String
    public var composeProject: String?
    public var image: String?
}
public struct Observation: Codable, Sendable {
    public var host: String
    public var hostname: String?
    public var platform: String?
    public var home: String?
    public var checked: String
    public var reachable: Bool
    public var staleAfterSeconds: Int = 30
    public var connection: CommandResult
    public var launchd: CommandResult?
    public var systemd: CommandResult?
    public var docker: CommandResult?
    public var tmux: CommandResult?
    public var discovered: [DiscoveryItem]
    public var curated: [String: CommandResult] = [:]
    public var projectBranches: [String: String] = [:]
}
public struct TerminalLaunch: Codable, Sendable {
    public var host: String
    public var project: String?
    public var tool: String?
    public var session: String?
    public var pinned: String?
    public var directory: String?
    public var persistent: Bool?
    public var yolo: Bool?
    public var window: String?
    public init(host: String, project: String? = nil, tool: String? = nil, session: String? = nil, persistent: Bool? = nil, yolo: Bool? = nil) {
        self.host = host; self.project = project; self.tool = tool; self.session = session; self.persistent = persistent; self.yolo = yolo
    }
    public func resolve(_ config: Configuration) throws -> (Host, String, String?) {
        guard pinned == nil else { throw AEError("Pinned terminals must be reattached through the terminal registry") }
        let h = try config.host(host)
        let p: Project? = try project.map { id in guard let p = h.projects.first(where: { $0.id == id }) else { throw AEError("Unknown project on selected host") }; return p }
        let t: Tool? = try tool.flatMap { $0.isEmpty ? nil : $0 }.map { id in guard let t = config.enabledTools(h).first(where: { $0.id == id }) else { throw AEError("Unknown tool on selected host") }; return t }
        if yolo == true && t?.yoloArguments == nil { throw AEError("No approved YOLO preset for this tool") }
        if let directory { try absolutePath(directory); guard t != nil, p == nil else { throw AEError("A directory override requires an enabled standalone tool") } }
        let workingDirectory = directory ?? p?.directory ?? t?.directory
        let configuredSession = session == nil && tool == nil && persistent != false ? p?.session : nil
        let checks = (t.map { "( " + ExecutableProbe.script($0.executable) + " ) >/dev/null || { echo 'Tool executable unavailable' >&2; exit 127; }; " } ?? "") + (workingDirectory.map { "test -d \(quote($0)) && test -x \(quote($0)) || { echo 'Working directory unavailable' >&2; exit 1; }; " } ?? "")
        let launch = t.map { command([$0.executable] + $0.arguments + (yolo == true ? ($0.yoloArguments ?? []) : [])) } ?? "exec \"${SHELL:-/bin/sh}\" -l"
        let directory = workingDirectory
        var name = session ?? configuredSession
        if name == nil && persistent == true { name = p?.session ?? t?.session ?? "aelab-\(project ?? tool ?? "shell")-\(UUID().uuidString.prefix(8))" }
        if let name {
            try validateSession(name)
            var args = ["tmux", "attach-session", "-t", "=" + name]
            if persistent == true || configuredSession != nil {
                args = ["tmux", "new-session", "-A", "-s", name]
                if let directory { args += ["-c", directory] }
                args += [h.executionScript(launch)]
            }
            var script = command(args)
            if let window {
                guard window.range(of: "^@[0-9]+$", options: .regularExpression) != nil else { throw AEError("Invalid tmux window") }
                script = command(["tmux", "select-window", "-t", "=\(name):\(window)"]) + "; exec " + script
            } else { script = "exec " + script }
            return (h, checks + script, name)
        }
        let script = (directory.map { "cd -- \(quote($0)) && " } ?? "") + launch
        return (h, checks + script, nil)
    }
}
private enum ObservationProbe: Sendable {
    case home(CommandResult)
    case native(CommandResult?, CommandResult?)
    case docker(CommandResult)
    case tmux(CommandResult)
    case service(String, CommandResult)
    case branch(String, String?)
}

public struct Operations: Sendable {
    public let store: ConfigStore
    public let execution: HostExecution
    public let toolDiscovery = ToolDiscovery()
    public let initiator: String
    public init(store: ConfigStore, initiator: String = "admin") { self.store = store; execution = HostExecution(home: store.home); self.initiator = initiator }
    public func discoverTools(_ id: String, refresh: Bool = false) async throws -> ToolInventory {
        let snapshot = try await store.read()
        return await toolDiscovery.discover(host: try snapshot.config.host(id), config: snapshot.config, execution: execution, refresh: refresh)
    }
    public func validateLaunch(_ launch: TerminalLaunch, config: Configuration) async throws {
        _ = try launch.resolve(config)
        let host = try config.host(launch.host)
        let project = host.projects.first { $0.id == launch.project }
        let tool = config.enabledTools(host).first { $0.id == launch.tool }
        if let tool {
            let result = try await execution.execute(host, script: ExecutableProbe.script(tool.executable), timeout: 5)
            guard result.status == 0 else { throw AEError("Tool executable unavailable or validation failed: \(tool.executable)") }
        }
        if let directory = launch.directory ?? project?.directory ?? tool?.directory {
            let result = try await execution.execute(host, script: "test -d \(quote(directory)) && test -x \(quote(directory))", timeout: 5)
            guard result.status == 0 else { throw AEError("Working directory unavailable: \(directory)") }
        }
    }
    public func identity(_ host: Host) async throws -> HostIdentity {
        let result = try await execution.run(host, args: ["uname", "-snr"], timeout: 5)
        guard result.status == 0 else { throw AEError("Cannot detect host identity: " + result.error) }
        return HostIdentity.parse(result.output)
    }
    public func prepareProject(host id: String, project: Project) async throws {
        guard validID(project.id), !project.name.isEmpty else { throw AEError("Invalid project") }
        try absolutePath(project.directory)
        let host = try await store.read().config.host(id)
        try await store.audit("project-directory", host: id, target: project.id, outcome: "requested", initiator: initiator)
        let result = try await execution.run(host, args: ["mkdir", "-p", "--", project.directory])
        guard result.status == 0 else { throw AEError("Cannot create project directory: " + result.error) }
        let access = try await execution.execute(host, script: "test -d " + quote(project.directory) + " && test -x " + quote(project.directory), timeout: 5)
        guard access.status == 0 else { throw AEError("Project directory is not accessible") }
        try await store.audit("project-directory", host: id, target: project.id, outcome: "ready", initiator: initiator)
    }
    func projectBranch(_ host: Host, directory: String) async -> String? {
        // symbolic-ref reads HEAD without hooks, worktree scans or optional index writes.
        guard let result = try? await execution.run(host, args: ["git", "--no-optional-locks", "-C", directory, "symbolic-ref", "--quiet", "--short", "HEAD"], timeout: 3), result.status == 0, !result.truncated else { return nil }
        let branch = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty, branch.utf8.count <= 1024, !branch.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return branch
    }
    public func observe(_ id: String) async throws -> Observation {
        let config = try await store.read().config; let host = try config.host(id)
        let connection = try await execution.run(host, args: ["uname", "-snr"])
        guard connection.status == 0 else { return Observation(host: id, checked: ISO8601DateFormatter().string(from: Date()), reachable: false, connection: connection, discovered: []) }
        let identity = HostIdentity.parse(connection.output)
        // Collect every child task before assembling the response. In particular, avoid
        // nested tuple destructuring of async-let results, which crashed optimized builds.
        let probes = try await withThrowingTaskGroup(of: ObservationProbe.self) { group in
            group.addTask { .home(try await execution.execute(host, script: "printf '%s' \"$HOME\"", timeout: 5)) }
            group.addTask {
                let (systemd, launchd) = try await nativeServices(host, platform: identity.platform)
                return .native(systemd, launchd)
            }
            group.addTask { .docker(try await execution.run(host, args: ServiceCommands.dockerArguments(["ps", "--all", "--format", "{{json .}}"], context: host.dockerContext))) }
            group.addTask { .tmux(try await execution.run(host, args: ["tmux", "list-sessions", "-F", "#{session_name}|#{session_windows}|#{session_attached}"])) }
            for project in host.projects {
                group.addTask { .branch(project.id, await projectBranch(host, directory: project.directory)) }
            }
            for service in host.services {
                group.addTask {
                    do { return .service(service.id, try await runService(host, service: service, operation: "status", platform: identity.platform)) }
                    catch { return .service(service.id, CommandResult(status: 1, output: "", error: String(describing: error), truncated: false)) }
                }
            }
            var results: [ObservationProbe] = []
            for try await result in group { results.append(result) }
            return results
        }
        var observation = Observation(host: id, hostname: identity.hostname, platform: identity.platform, checked: ISO8601DateFormatter().string(from: Date()), reachable: true, connection: connection, discovered: [])
        for probe in probes {
            switch probe {
            case .home(let result):
                observation.home = result.status == 0 && (try? absolutePath(result.output)) != nil ? result.output : nil
            case .native(let systemd, let launchd): observation.systemd = systemd; observation.launchd = launchd
            case .docker(let result): observation.docker = result
            case .tmux(let result): observation.tmux = result
            case .service(let id, let result): observation.curated[id] = result
            case .branch(let id, let branch): observation.projectBranches[id] = branch
            }
        }
        func successfulOutput(_ result: CommandResult?) -> String { result.flatMap { $0.status == 0 ? $0.output : nil } ?? "" }
        observation.discovered = Self.parseDiscovery(systemd: successfulOutput(observation.systemd), docker: successfulOutput(observation.docker)) + LaunchdDiscovery.parse(successfulOutput(observation.launchd))
        return observation
    }
    public static func parseDiscovery(systemd: String, docker: String) -> [DiscoveryItem] {
        var result: [DiscoveryItem] = []
        for line in systemd.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard fields.count >= 4 else { continue }
            // Docker infrastructure is visible natively; application containers aren't synthesized as units.
            result.append(DiscoveryItem(provider: .systemd, target: fields[0], state: fields[2] + "/" + fields[3]))
        }
        var groups: [String: [String]] = [:]
        for line in docker.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8), let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let name = row["Names"] as? String else { continue }
            let labels = (row["Labels"] as? String ?? "").split(separator: ",").map { $0.split(separator: "=", maxSplits: 1).map(String.init) }
            let composeProject = labels.first(where: { $0.first == "com.docker.compose.project" }).flatMap { $0.count == 2 ? $0[1] : nil }
            let state = row["State"] as? String ?? "unknown"
            result.append(DiscoveryItem(provider: .docker, target: name, state: state, composeProject: composeProject, image: row["Image"] as? String))
            if let composeProject { groups[composeProject, default: []].append(state) }
        }
        for (composeProject, states) in groups.sorted(by: { $0.key < $1.key }) { result.append(DiscoveryItem(provider: .compose, target: composeProject, state: states.joined(separator: ", "), composeProject: composeProject)) }
        return result
    }
    public func service(_ hostID: String, id: String, operation: String) async throws -> CommandResult {
        let config = try await store.read().config; let host = try config.host(hostID)
        guard let service = host.services.first(where: { $0.id == id }) else { throw AEError("Unknown curated service on selected host") }
        let mutation = !["status", "logs"].contains(operation)
        if mutation { try await store.audit(operation, host: hostID, target: id, outcome: "requested", initiator: initiator) }
        do {
            let platform = try await identity(host).platform
            let result = try await runService(host, service: service, operation: operation, platform: platform)
            if mutation { try await store.audit(operation, host: hostID, target: id, outcome: result.category, initiator: initiator) }; return result
        } catch { if mutation { try await store.audit(operation, host: hostID, target: id, outcome: "execution-error", initiator: initiator) }; throw error }
    }
    public func renameSession(host id: String, session: String, name: String) async throws -> CommandResult {
        try validateSession(session); try validateSession(name)
        guard session != name else { throw AEError("Choose a different session name") }
        let host = try await store.read().config.host(id)
        try await store.audit("tmux-rename", host: id, target: session, outcome: "requested", initiator: initiator)
        let result = try await execution.run(host, args: ["tmux", "rename-session", "-t", "=" + session, name])
        try await store.audit("tmux-rename", host: id, target: session, outcome: result.category, initiator: initiator)
        return result
    }
    public func killSession(host id: String, session: String) async throws -> CommandResult {
        try validateSession(session)
        let host = try await store.read().config.host(id)
        try await store.audit("tmux-delete", host: id, target: session, outcome: "requested", initiator: initiator)
        let result = try await execution.run(host, args: ["tmux", "kill-session", "-t", "=" + session])
        try await store.audit("tmux-delete", host: id, target: session, outcome: result.category, initiator: initiator)
        return result
    }
    public func tmuxWindow(_ launch: TerminalLaunch, session: String) async throws -> CommandResult {
        try validateSession(session)
        let config = try await store.read().config
        try await validateLaunch(launch, config: config)
        let host = try config.host(launch.host)
        var windowLaunch = launch; windowLaunch.session = nil; windowLaunch.persistent = false; windowLaunch.window = nil
        let (_, script, _) = try windowLaunch.resolve(config)
        let args = ["tmux", "new-window", "-P", "-F", "#{window_id}", "-t", "=" + session + ":", host.executionScript(script)]
        try await store.audit("tmux-window", host: host.id, target: session, outcome: "requested", initiator: initiator)
        let result = try await execution.run(host, args: args)
        try await store.audit("tmux-window", host: host.id, target: session, outcome: result.category, initiator: initiator); return result
    }
}
