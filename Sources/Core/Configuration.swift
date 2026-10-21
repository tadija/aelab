import Foundation
import Crypto
#if os(Linux)
import Glibc
#else
import Darwin
#endif

public struct AEError: Error, CustomStringConvertible, Sendable {
    public let description: String
    public init(_ message: String) { description = message }
}
public struct RevisionConflict: Error, CustomStringConvertible, Sendable {
    public let description: String
    public init(_ description: String) { self.description = description }
}
public enum HostTransport: String, Codable, Sendable { case ssh, local, daemon }
public struct Host: Codable, Sendable, Identifiable {
    public var id: String { nameID(name) }
    public var name: String
    public var destination: String
    public var daemon: String?
    public var transport: HostTransport?
    public var isLocal: Bool { transport == .local }
    var executionPaths: [String] = []
    public var port: Int?
    public var dockerContext: String?
    public var background: String?
    public var tint: String?
    public var projects: [Project] = []
    public var services: [Service] = []
    public var tools: [String] = []
    public var plugins: [String] = []
    public init(name: String, destination: String = "", port: Int? = nil, transport: HostTransport? = nil) {
        self.name = name; self.destination = destination; self.port = port; self.transport = transport
    }
    enum CodingKeys: String, CodingKey, CaseIterable { case name, destination, transport, daemon, port, background, tint, projects, services, tools, plugins, dockerContext }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let unknown = Set(try decoder.container(keyedBy: ConfigurationKey.self).allKeys.map(\.stringValue)).subtracting(CodingKeys.allCases.map(\.rawValue))
        guard unknown.isEmpty else { throw AEError("Unknown host keys: \(unknown.sorted().joined(separator: ", "))") }
        name = try c.decode(String.self, forKey: .name)
        projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
        services = try c.decodeIfPresent([Service].self, forKey: .services) ?? []
        tools = try c.decodeIfPresent([String].self, forKey: .tools) ?? []
        plugins = try c.decodeIfPresent([String].self, forKey: .plugins) ?? []
        destination = try c.decodeIfPresent(String.self, forKey: .destination) ?? ""
        daemon = try c.decodeIfPresent(String.self, forKey: .daemon)
        transport = try c.decodeIfPresent(HostTransport.self, forKey: .transport)
        dockerContext = try c.decodeIfPresent(String.self, forKey: .dockerContext)
        port = try c.decodeIfPresent(Int.self, forKey: .port)
        background = try c.decodeIfPresent(String.self, forKey: .background); tint = try c.decodeIfPresent(String.self, forKey: .tint)
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(plugins, forKey: .plugins)
        try c.encode(projects, forKey: .projects); try c.encode(services, forKey: .services); try c.encode(tools, forKey: .tools)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(destination.isEmpty ? nil : destination, forKey: .destination)
        try c.encodeIfPresent(dockerContext, forKey: .dockerContext)
        try c.encodeIfPresent(daemon, forKey: .daemon)
        try c.encodeIfPresent(transport, forKey: .transport); try c.encodeIfPresent(port, forKey: .port)
        try c.encodeIfPresent(background, forKey: .background); try c.encodeIfPresent(tint, forKey: .tint)
    }
}
public struct Project: Codable, Sendable, Identifiable {
    public var id: String { nameID(name) }
    public var name: String
    public var directory: String
    public var session: String?
}
public enum Provider: String, Codable, Sendable { case systemd, launchd, docker, compose }
public struct Service: Codable, Sendable, Identifiable {
    public var id: String { nameID(name) }
    public var name: String
    public var provider: Provider
    public var target: String
    public var directory: String?
    public var files: [String]?
    public var environmentFile: String?
    public var plist: String?
    public var logFiles: [String]?
    public var userUnit: Bool?
    public var sudo: Bool?
}
public struct Tool: Codable, Sendable, Identifiable {
    public var directory: String? = nil
    public var id: String { nameID(name) }
    public var name: String
    public var executable: String
    public var arguments: [String]
    public var yoloArguments: [String]?
    public var session: String?
}
private struct ConfigurationKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
public struct TTYButton: Codable, Sendable {
    public var key: String
    public var label: String
    public static func supports(_ key: String) -> Bool {
        if key.range(of: "^ctrl-[a-z]$", options: .regularExpression) != nil { return true }
        switch key {
        case "alt", "shift", "reload-tty", "tmux-zoom", "tmux-mouse", "up", "down", "left", "right", "escape", "tab", "enter", "backspace", "delete", "home", "end", "page-up", "page-down", "copy", "paste", "reconnect", "scroll-up", "scroll-down", "copy-mode", "tmux-window", "tmux-split-horizontal", "tmux-split-vertical": return true
        default: return false
        }
    }
}
public struct Configuration: Codable, Sendable {
    public var version: Int = 1
    public var ttyButtons: [TTYButton] = []
    public var tools: [Tool] = []
    public var plugins: [Plugin] = []
    public var paths: [String] = []
    public var hosts: [Host] = []
    public init() {}
    enum CodingKeys: String, CodingKey, CaseIterable { case version, tools, plugins, paths, hosts, ttyButtons }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        guard version == 1 else { throw AEError("Unsupported configuration version; expected 1") }
        let keys = Set(try decoder.container(keyedBy: ConfigurationKey.self).allKeys.map(\.stringValue))
        let unknown = keys.subtracting(CodingKeys.allCases.map(\.rawValue))
        guard unknown.isEmpty else { throw AEError("Unknown configuration keys: \(unknown.sorted().joined(separator: ", "))") }
        tools = try c.decodeIfPresent([Tool].self, forKey: .tools) ?? []
        plugins = try c.decodeIfPresent([Plugin].self, forKey: .plugins) ?? []
        paths = try c.decodeIfPresent([String].self, forKey: .paths) ?? []
        ttyButtons = try c.decodeIfPresent([TTYButton].self, forKey: .ttyButtons) ?? []
        hosts = try c.decode([Host].self, forKey: .hosts)
    }
    public func host(_ id: String) throws -> Host {
        guard var host = hosts.first(where: { $0.id == id }) else { throw AEError("Unknown approved host: \(id)") }
        host.executionPaths = paths; return host
    }
    public func enabledTools(_ host: Host) -> [Tool] { tools.filter { host.tools.contains($0.id) } }
    public func enabledPlugins(_ host: Host) -> [Plugin] { plugins.filter { host.plugins.contains($0.id) } }
    /// Only transfer retained terminal context when the host itself is unchanged.
    public func renamedHosts(to updated: Configuration) -> [String: String] {
        let removed = hosts.filter { old in !updated.hosts.contains { $0.id == old.id } }
        let added = updated.hosts.filter { new in !hosts.contains { $0.id == new.id } }
        func sameConnection(_ a: Host, _ b: Host) -> Bool {
            (a.transport ?? .ssh) == (b.transport ?? .ssh) && a.destination == b.destination && a.port == b.port && ((a.transport ?? .ssh) != .daemon || a.daemon == b.daemon)
        }
        var result: [String: String] = [:]
        for old in removed {
            let matches = added.filter { sameConnection(old, $0) }
            if matches.count == 1, let new = matches.first, removed.filter({ sameConnection($0, new) }).count == 1 { result[old.id] = new.id }
        }
        return result
    }
    public func validate() throws {
        guard ttyButtons.count <= 64, Set(ttyButtons.map(\.key)).count == ttyButtons.count,
              ttyButtons.allSatisfy({ TTYButton.supports($0.key) && !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.label.count <= 40 && !$0.label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }) else { throw AEError("Invalid ttyButtons: use unique supported keys and labels of 1–40 characters (maximum 64 buttons)") }

        guard hosts.count <= 64, hosts.reduce(0, { $0 + $1.projects.count }) <= 512, hosts.reduce(0, { $0 + $1.services.count }) <= 512, tools.count <= 256, plugins.count <= 256 else { throw AEError("Configuration entry limit exceeded") }
        guard version == 1 else { throw AEError("Unsupported config version") }
        func ids(_ values: [String]) throws {
            guard Set(values).count == values.count else { throw AEError("Names must produce unique URL identifiers within each collection") }; guard values.allSatisfy(validID) else { throw AEError("Names must contain a letter or number and produce an identifier of at most 64 characters") }
        }
        try ids(hosts.map(\.id)); try ids(tools.map(\.id)); try ids(plugins.map(\.id))
        guard paths.count <= 64, Set(paths).count == paths.count else { throw AEError("paths must contain at most 64 unique directories") }
        for directory in paths {
            try absolutePath(directory)
            guard !directory.contains(":"), !directory.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw AEError("paths must not contain colons or control characters") }
        }
        for plugin in plugins { try plugin.validate() }
        for t in tools {
            if let directory = t.directory { try absolutePath(directory) }
            guard !t.name.isEmpty, !t.executable.isEmpty, !t.executable.hasPrefix("-"), !t.executable.contains("\0"), !t.executable.contains("\n"), t.executable.utf8.count <= 4096, t.arguments.count <= 64, (t.yoloArguments?.count ?? 0) <= 64,
                  (t.arguments + (t.yoloArguments ?? [])).allSatisfy({ !$0.contains("\0") && $0.utf8.count <= 8192 }) else { throw AEError("Invalid tool command") }
            if let session = t.session { try validateSession(session) }
        }
        for h in hosts {
            guard !h.name.isEmpty, [h.background, h.tint].allSatisfy({ $0 == nil || $0!.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil }) else { throw AEError("Invalid host \(h.id)") }
            if h.isLocal {
                guard h.destination.isEmpty, h.port == nil else { throw AEError("Local host \(h.id) must not specify an SSH destination or port") }
            } else if h.transport == .daemon {
                guard let identity = h.daemon, UUID(uuidString: identity) != nil else { throw AEError("Daemon host requires a paired connection ID") }
                guard h.destination.isEmpty || (!h.destination.hasPrefix("-") && h.destination.range(of: "^[A-Za-z0-9_.@:\\[\\]-]+$", options: .regularExpression) != nil), h.port == nil || (1...65535).contains(h.port!) else { throw AEError("Invalid retained SSH destination") }
            } else {
                guard !h.destination.isEmpty, !h.destination.hasPrefix("-"), h.destination.range(of: "^[A-Za-z0-9_.@:\\[\\]-]+$", options: .regularExpression) != nil,
                      h.port == nil || (1...65535).contains(h.port!) else { throw AEError("Invalid SSH host \(h.id)") }
            }
            try ids(h.tools); try ids(h.plugins)
            guard h.tools.allSatisfy({ id in tools.contains { $0.id == id } }), h.plugins.allSatisfy({ id in plugins.contains { $0.id == id } }) else { throw AEError("Unknown enabled tool or plugin on \(h.id)") }
            if let context = h.dockerContext { try ServiceCommands.validateDockerContext(context) }
            let projects = h.projects, services = h.services
            try ids(projects.map(\.id)); try ids(services.map(\.id))
            for p in projects {
                guard !p.name.isEmpty else { throw AEError("Project name is required") }; try absolutePath(p.directory)
                if let session = p.session { try validateSession(session) }
            }
            for s in services {
                guard !s.name.isEmpty else { throw AEError("Service name is required") }
                if s.provider == .launchd { try ServiceCommands.validateLaunchdTarget(s.target) }
                else { guard !s.target.hasPrefix("-"), s.target.range(of: "^[A-Za-z0-9_][A-Za-z0-9_.@:-]*$", options: .regularExpression) != nil else { throw AEError("Invalid service target") } }
                if let plist = s.plist { guard s.provider == .launchd else { throw AEError("plist only applies to launchd") }; try HostPath.validate(plist) }
                if let files = s.logFiles {
                    guard s.provider == .launchd, files.count <= 8 else { throw AEError("logFiles only applies to launchd (at most 8 paths)") }
                    for file in files { try HostPath.validate(file) }
                }
                if let d = s.directory { try absolutePath(d) }
                for f in s.files ?? [] { try absolutePath(f) }
                if let f = s.environmentFile { try absolutePath(f) }
                if s.userUnit == true && s.provider != .systemd { throw AEError("userUnit only applies to systemd") }
                if s.sudo == true && ![.systemd, .launchd].contains(s.provider) { throw AEError("sudo only applies to systemd/launchd") }
            }
        }
    }
}

/// Keep the configured key bar readable without changing the raw file editor's formatting.
public func configurationData(_ config: Configuration) throws -> Data {
    var text = String(decoding: try jsonEncoder.encode(config), as: UTF8.self)
    if !config.ttyButtons.isEmpty {
        let expression = try NSRegularExpression(pattern: #"("ttyButtons"\s*:\s*\[).*?(\n  \])"#, options: [.dotMatchesLineSeparators])
        if let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range(at: 0), in: text) {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let rows = try config.ttyButtons.map { "    " + String(decoding: try encoder.encode($0), as: UTF8.self) }
            text.replaceSubrange(range, with: "\"ttyButtons\" : [\n" + rows.joined(separator: ",\n") + "\n  ]")
        }
    }
    return Data((text + "\n").utf8)
}

/// Derived identity is independent of row order and filesystem paths.
public func nameID(_ name: String) -> String {
    let plain = name.decomposedStringWithCompatibilityMapping.unicodeScalars.filter { !CharacterSet.nonBaseCharacters.contains($0) }
    let lower = String(String.UnicodeScalarView(plain)).lowercased()
    return lower.components(separatedBy: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").inverted).filter { !$0.isEmpty }.joined(separator: "-")
}

public func validID(_ value: String) -> Bool { value.range(of: "^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$", options: .regularExpression) != nil }
public func validateSession(_ value: String) throws {
    guard value.range(of: "^[A-Za-z0-9][A-Za-z0-9_-]{0,95}$", options: .regularExpression) != nil else { throw AEError("Invalid tmux session name") }
}
public func absolutePath(_ value: String) throws {
    guard value.hasPrefix("/"), !value.contains("\0"), !value.contains("\n"), value.utf8.count <= 4096 else { throw AEError("Expected an absolute host path") }
}
public func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
public func command(_ args: [String]) -> String { args.map(quote).joined(separator: " ") }
public var jsonEncoder: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }
public func revision(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
public struct ConfigDocument: Codable, Sendable { public var content: String; public var revision: String }
public struct ConfigSnapshot: Codable, Sendable { public var config: Configuration; public var revision: String }

/// All clients lock the same inode. External editors must use `aelab config apply` for CAS guarantees.
public actor ConfigStore {
    public let home: URL
    public init(home: URL) throws {
        self.home = home
        for path in ["config", "state"] {
            let url = home.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }
    public func read() throws -> ConfigSnapshot {
        let data = try Data(contentsOf: home.appendingPathComponent("config/aelab.json"))
        let config = try JSONDecoder().decode(Configuration.self, from: data); try config.validate()
        return ConfigSnapshot(config: config, revision: revision(data))
    }
    public func initialize(template: Configuration? = nil) throws {
        let path = home.appendingPathComponent("config/aelab.json")
        guard !FileManager.default.fileExists(atPath: path.path) else { throw AEError("Configuration already exists") }
        var config = template ?? Configuration(); config.hosts = [Host(name: "localhost", transport: .local)]
        try write(config, expected: nil)
    }
    /// First-run/update setup never replaces existing entries or credentials.
    public func initializeIfNeeded(template: Configuration? = nil) throws {
        let path = home.appendingPathComponent("config/aelab.json")
        if !FileManager.default.fileExists(atPath: path.path) { try initialize(template: template); return }
        let snapshot = try read()
        guard !snapshot.config.hosts.contains(where: { $0.isLocal || $0.destination == "localhost" }) else { return }
        var config = snapshot.config
        config.hosts.append(Host(name: "localhost", transport: .local))
        try write(config, expected: snapshot.revision)
        try audit("config", host: "central", target: "localhost", outcome: "default-host-added", initiator: "local-cli")
    }
    public func write(_ config: Configuration, expected: String?) throws {
        try config.validate()
        try commit(configurationData(config), expected: expected)
    }
    private func commit(_ data: Data, expected: String?) throws {
        let lockFD = open(home.appendingPathComponent("config/.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0 else { throw AEError("Cannot open configuration lock") }
        defer { _ = flock(lockFD, LOCK_UN); _ = close(lockFD) }
        guard flock(lockFD, LOCK_EX) == 0 else { throw AEError("Cannot lock configuration") }
        let url = home.appendingPathComponent("config/aelab.json")
        if let expected { guard try readDocument().revision == expected else { throw RevisionConflict("Configuration changed; reload before saving") } }
        else if FileManager.default.fileExists(atPath: url.path) { throw RevisionConflict("Expected revision required") }
        let previous = try? JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url))
        let updated = try JSONDecoder().decode(Configuration.self, from: data)
        try atomicPrivateWrite(data, to: url)
        if let previous {
            let renames = previous.renamedHosts(to: updated)
            if !renames.isEmpty, var sections = try? sectionState() {
                for (from, to) in renames { if let value = sections.removeValue(forKey: from) { sections[to] = value } }
                // Preferences are best effort; a failed state write must not report an already-saved config as failed.
                try? atomicPrivateWrite(jsonEncoder.encode(sections), to: home.appendingPathComponent("state/sections.json"))
            }
        }
    }
    public func readDocument() throws -> ConfigDocument {
        let data: Data
        do { data = try Data(contentsOf: home.appendingPathComponent("config/aelab.json")) }
        catch { throw AEError("Cannot read the main configuration file") }
        guard let content = String(data: data, encoding: .utf8) else { throw AEError("Configuration must be UTF-8 text") }
        return ConfigDocument(content: content, revision: revision(data))
    }
    public static func validateDocument(_ content: String) throws -> Configuration {
        guard content.utf8.count <= 1_048_576 else { throw AEError("Configuration is too large") }
        let config: Configuration
        do { config = try JSONDecoder().decode(Configuration.self, from: Data(content.utf8)) }
        catch let error as DecodingError {
            switch error {
            case .keyNotFound(let key, let context): throw AEError("Missing \(key.stringValue) at \(context.codingPath.map(\.stringValue).joined(separator: "."))")
            case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context): throw AEError("Invalid JSON/configuration at \(context.codingPath.map(\.stringValue).joined(separator: ".")): \(context.debugDescription)")
            @unknown default: throw AEError("Invalid configuration JSON")
            }
        }
        try config.validate(); return config
    }
    public func writeDocument(_ document: ConfigDocument) throws {
        _ = try Self.validateDocument(document.content)
        try commit(Data(document.content.utf8), expected: document.revision)
    }
    private static let sectionKeys = Set(["hosts", "shells", "projects", "services", "tools", "plugins"])
    public func sectionState() throws -> [String: [String: Bool]] {
        let url = home.appendingPathComponent("state/sections.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        return try JSONDecoder().decode([String: [String: Bool]].self, from: Data(contentsOf: url)).mapValues { $0.filter { Self.sectionKeys.contains($0.key) } }
    }
    public func saveSections(host: String, sections: [String: Bool]) throws {
        guard try host == "overview" || read().config.hosts.contains(where: { $0.id == host }) else { throw AEError("Unknown host") }
        guard Set(sections.keys).isSubset(of: Self.sectionKeys) else { throw AEError("Unknown section") }
        let configured = Set(try read().config.hosts.map(\.id) + ["overview"])
        var state = try sectionState().filter { configured.contains($0.key) }
        state[host] = sections
        try atomicPrivateWrite(jsonEncoder.encode(state), to: home.appendingPathComponent("state/sections.json"))
    }
    public func audit(_ operation: String, host: String, target: String, outcome: String, initiator: String = "admin") throws {
        struct Entry: Codable { let time: String; let initiator: String; let operation: String; let host: String; let target: String; let outcome: String }
        let entry = Entry(time: ISO8601DateFormatter().string(from: Date()), initiator: initiator, operation: operation, host: host, target: target, outcome: outcome)
        var data = try JSONEncoder().encode(entry); data.append(10)
        let fd = open(home.appendingPathComponent("state/audit.log").path, O_CREAT | O_WRONLY | O_APPEND, 0o600)
        guard fd >= 0 else { throw AEError("Cannot open audit log") }; defer { _ = close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw AEError("Cannot lock audit log") }
        defer { _ = flock(fd, LOCK_UN) }
        let count = data.withUnsafeBytes { systemWrite(fd, $0.baseAddress, $0.count) }
        guard count == data.count else { throw AEError("Cannot write audit log") }
    }
}
public func atomicPrivateWrite(_ data: Data, to url: URL, overwrite: Bool = true) throws {
    let temp = url.deletingLastPathComponent().appendingPathComponent(".write-\(UUID().uuidString)")
    guard FileManager.default.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw AEError("Cannot write file") }
    defer { try? FileManager.default.removeItem(at: temp) }
    let fd = open(temp.path, O_RDONLY)
    guard fd >= 0 else { throw AEError("Cannot open temporary file") }
    _ = fsync(fd); _ = close(fd)
    let result = overwrite ? rename(temp.path, url.path) : link(temp.path, url.path)
    guard result == 0 else { throw AEError("Cannot atomically save file (it may already exist)") }
    let directoryFD = open(url.deletingLastPathComponent().path, O_RDONLY)
    if directoryFD >= 0 { _ = fsync(directoryFD); _ = close(directoryFD) }
}

private func systemWrite(_ fd: Int32, _ bytes: UnsafeRawPointer?, _ count: Int) -> Int {
#if os(Linux)
    return Glibc.write(fd, bytes, count)
#else
    return Darwin.write(fd, bytes, count)
#endif
}
