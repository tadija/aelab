import Foundation

/// Resolve only filesystem executables, never aliases/functions or the tool itself.
public enum ExecutableProbe {
    public static func script(_ executable: String) -> String {
        let value = quote(executable)
        if executable.contains("/") {
            return "test -f \(value) && test -x \(value) && printf '%s\\n' \(value)"
        }
        // Preserve empty PATH components (current directory) and spaces. No eval or glob expansion.
        return "ae_name=\(value); ae_rest=$PATH; while :; do ae_dir=${ae_rest%%:*}; test -n \"$ae_dir\" || ae_dir=.; ae_file=$ae_dir/$ae_name; if test -f \"$ae_file\" && test -x \"$ae_file\"; then printf '%s\\n' \"$ae_file\"; exit 0; fi; case $ae_rest in *:*) ae_rest=${ae_rest#*:};; *) exit 1;; esac; done"
    }
}
public struct DiscoveredTool: Codable, Sendable {
    public var tool: Tool
    public var state: String
    public var path: String?
    public var error: String?
    public var enabled: Bool
}
public struct ToolInventory: Codable, Sendable {
    public var host: String
    public var checked: String
    public var staleAfterSeconds: Int = 300
    public var tools: [DiscoveredTool]
}
public actor ToolDiscovery {
    private struct Cached { let key: String; let date: Date; let inventory: ToolInventory }
    private var cache: [String: Cached] = [:]
    public init() {}
    public func discover(host: Host, config: Configuration, execution: HostExecution, refresh: Bool = false) async -> ToolInventory {
        let key = revision((try? jsonEncoder.encode(config)) ?? Data())
        if !refresh, let saved = cache[host.id], saved.key == key, Date().timeIntervalSince(saved.date) < 300 { return saved.inventory }
        var rows: [DiscoveredTool] = []
        // Sequential bounded probes avoid an unbounded fan-out across configured hosts.
        for tool in config.tools {
            var row = DiscoveredTool(tool: tool, state: "discovery-error", enabled: host.tools.contains(tool.id))
            do {
                let result = try await execution.execute(host, script: ExecutableProbe.script(tool.executable), timeout: 5)
                if result.status == 0 && !result.truncated && !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    row.state = "installed"; row.path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                } else if result.status == 1 && result.error.isEmpty && !result.truncated { row.state = "unavailable" }
                else { row.error = result.error.isEmpty ? result.category : result.error }
            } catch { row.error = String(describing: error) }
            rows.append(row)
        }
        let inventory = ToolInventory(host: host.id, checked: ISO8601DateFormatter().string(from: Date()), tools: rows)
        cache[host.id] = Cached(key: key, date: Date(), inventory: inventory)
        return inventory
    }
}
