import Foundation

/// Explicit administrator-approved host commands. Plugins are trusted, not sandboxed.
public struct Plugin: Codable, Sendable, Identifiable {
    public var id: String { nameID(name) }
    public var name: String
    public var source: String?
    public var executable: String
    public var arguments: [String]
    public var timeout: Int = 10
    enum CodingKeys: String, CodingKey { case name, executable, arguments, timeout, source }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        executable = try c.decode(String.self, forKey: .executable)
        arguments = try c.decode([String].self, forKey: .arguments)
        timeout = try c.decodeIfPresent(Int.self, forKey: .timeout) ?? 10
    }
    var needsHome: Bool { ([source, executable].compactMap { $0 } + arguments).contains { $0.hasPrefix("~/") || $0 == "~" } }
    private var remoteManagedPaths: Set<String> {
        let paths = [source, executable].compactMap { $0 } + arguments
        var managed = Set(paths.filter { $0.hasPrefix("/") && ["sh", "bash", "rb", "swift"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) })
        // A compiled plugin's source and its future host-built executable share a directory.
        if source != nil, executable.hasPrefix("/"), !["sh", "bash", "ruby", "swift"].contains(URL(fileURLWithPath: executable).lastPathComponent) { managed.insert(executable) }
        return managed
    }
    func needsHome(on host: Host) -> Bool { needsHome || (!host.isLocal && !remoteManagedPaths.isEmpty) }
    func resolved(home: String, remote: Bool = false) throws -> Plugin {
        var plugin = self
        let managed = remote ? remoteManagedPaths : []
        let scriptName = URL(fileURLWithPath: source ?? managed.sorted().first ?? executable).deletingPathExtension().lastPathComponent
        func expand(_ value: String) throws -> String {
            if managed.contains(value) { return try HostPath.resolve("~/.aelab/plugins/" + scriptName + "/" + URL(fileURLWithPath: value).lastPathComponent, home: home) }
            return value.hasPrefix("~/") || value == "~" ? try HostPath.resolve(value, home: home) : value
        }
        plugin.executable = try expand(executable); plugin.arguments = try arguments.map(expand)
        if let source { plugin.source = try expand(source) }
        return plugin
    }
    func resolved(on host: Host, execution: HostExecution) async throws -> Plugin {
        needsHome(on: host) ? try await resolved(home: HostFiles(execution: execution).home(host), remote: !host.isLocal) : self
    }
    public func validate() throws {
        if let source { try HostPath.validate(source) }
        if executable.contains("/") { try HostPath.validate(executable) }
        for argument in arguments where argument.hasPrefix("~/") { try HostPath.validate(argument) }
        guard validID(id), !name.isEmpty, name.utf8.count <= 256,
              !executable.isEmpty, !executable.hasPrefix("-"), !executable.contains("\0"), !executable.contains("\n"), executable.utf8.count <= 4096,
              arguments.count <= 64, arguments.allSatisfy({ !$0.contains("\0") && $0.utf8.count <= 8192 }),
              (1...30).contains(timeout) else { throw AEError("Invalid plugin definition: \(id)") }
    }
}
public enum PluginStatus: String, Codable, Sendable { case ok, warning, critical, unknown }
public struct PluginDetail: Codable, Sendable {
    public var label: String
    public var value: String
}
public struct PluginReport: Codable, Sendable {
    public var version: Int
    public var status: PluginStatus
    public var summary: String
    public var details: [PluginDetail]
    public static func parse(_ result: CommandResult) throws -> PluginReport {
        guard result.status == 0 else { throw AEError("Plugin command failed (\(result.category), exit \(result.status))") }
        guard !result.truncated, result.output.utf8.count <= 65_536 else { throw AEError("Plugin output exceeds 64 KiB") }
        let report: PluginReport
        do { report = try JSONDecoder().decode(Self.self, from: Data(result.output.utf8)) }
        catch { throw AEError("Plugin must emit a valid report: version, status, summary and details") }
        guard report.version == 1, !report.summary.isEmpty, report.summary.utf8.count <= 512, report.details.count <= 32,
              report.details.allSatisfy({ !$0.label.isEmpty && $0.label.utf8.count <= 128 && $0.value.utf8.count <= 4096 }) else { throw AEError("Invalid plugin report version or field limits") }
        return report
    }
}
public struct PluginObservation: Codable, Sendable {
    public var host: String
    public var plugin: String
    public var checked: String
    public var exitStatus: Int32
    public var report: PluginReport?
    public var error: String?
}
extension Operations {
    public func probePlugin(host id: String, plugin pluginID: String) async throws -> PluginObservation {
        let config = try await store.read().config; let host = try config.host(id)
        guard let definition = config.enabledPlugins(host).first(where: { $0.id == pluginID }) else { throw AEError("Unknown plugin on selected host") }
        try definition.validate()
        let plugin = try await definition.resolved(on: host, execution: execution)
        try await store.audit("plugin-probe", host: id, target: pluginID, outcome: "requested", initiator: initiator)
        do {
            let args = ["env", "AELAB_HOST_ID=\(id)", "AELAB_PLUGIN_ID=\(pluginID)", plugin.executable] + plugin.arguments + ["--aelab-probe"]
            let result = try await execution.run(host, args: args, timeout: TimeInterval(plugin.timeout))
            var report: PluginReport?; var error: String?
            do { report = try PluginReport.parse(result) } catch let failure { error = String(describing: failure) }
            try await store.audit("plugin-probe", host: id, target: pluginID, outcome: error == nil ? "reported" : "failed", initiator: initiator)
            return PluginObservation(host: id, plugin: pluginID, checked: ISO8601DateFormatter().string(from: Date()), exitStatus: result.status, report: report, error: error)
        } catch {
            try await store.audit("plugin-probe", host: id, target: pluginID, outcome: "execution-error", initiator: initiator)
            throw AEError("Plugin execution failed; check host connectivity and executable permissions")
        }
    }
}

public struct PluginAvailability: Codable, Sendable {
    public var plugin: String
    public var state: String
    public var error: String?
    public var source: PluginSource?
}
extension Operations {
    public func discoverPlugins(host id: String) async throws -> [PluginAvailability] {
        let config = try await store.read().config; let host = try config.host(id)
        async let sourceFiles = PluginSources(store: store).list(host: id)
        let home = config.plugins.contains(where: { $0.needsHome(on: host) }) ? try await HostFiles(execution: execution).home(host) : "/"
        var rows: [PluginAvailability] = []
        for definition in config.plugins {
            let plugin = try definition.resolved(home: home, remote: !host.isLocal)
            var script = "( " + ExecutableProbe.script(plugin.executable) + " ) >/dev/null"
            for path in plugin.arguments where path.hasPrefix("/") && ["sh", "bash", "rb", "swift"].contains(URL(fileURLWithPath: path).pathExtension) {
                script += " && test -f " + quote(path) + " && test -r " + quote(path)
            }
            let result = try await execution.execute(host, script: script, timeout: 5)
            rows.append(PluginAvailability(plugin: plugin.id, state: result.status == 0 ? "installed" : result.status == 1 ? "unavailable" : "discovery-error", error: result.status > 1 ? result.error : nil, source: nil))
        }
        let sources = try await sourceFiles
        for index in rows.indices { rows[index].source = sources.first { $0.id == rows[index].plugin } }
        return rows
    }
}
