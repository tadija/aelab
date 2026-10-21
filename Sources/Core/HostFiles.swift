import Foundation

/// Explicit home-relative paths; other shell substitutions and working-directory-relative paths stay literal/invalid.
public enum HostPath {
    public static func validate(_ value: String) throws {
        if value == "~" || value.hasPrefix("~/") {
            let suffix = String(value.dropFirst(value == "~" ? 1 : 2))
            guard !suffix.split(separator: "/").contains(".."), !value.contains("\0"), !value.contains("\n"), value.utf8.count <= 4096 else { throw AEError("Invalid home-relative host path") }
        } else { try absolutePath(value) }
    }
    public static func resolve(_ value: String, home: String) throws -> String {
        try validate(value)
        guard value == "~" || value.hasPrefix("~/") else { return value }
        try absolutePath(home)
        let result = value == "~" ? home : (home == "/" ? "" : home) + "/" + value.dropFirst(2)
        try absolutePath(result); return result
    }
    static func expression(_ value: String) throws -> String {
        try validate(value)
        if value == "~" { return "\"$HOME\"" }
        if value.hasPrefix("~/") { return "\"$HOME\"/" + quote(String(value.dropFirst(2))) }
        return quote(value)
    }
}
public struct HostDirectory: Codable, Sendable {
    public var name: String
    public var path: String
}
public struct DirectoryListing: Codable, Sendable {
    public var host: String
    public var path: String
    public var home: String
    public var parent: String?
    public var directories: [HostDirectory]
    public var truncated: Bool
}
public struct HostFiles: Sendable {
    let execution: HostExecution
    public init(execution: HostExecution = HostExecution()) { self.execution = execution }
    public func home(_ host: Host) async throws -> String {
        let result = try await execution.execute(host, script: "printf '%s' \"$HOME\"", timeout: 5)
        guard result.status == 0, !result.truncated else { throw AEError("Cannot determine host home directory") }
        try absolutePath(result.output); return result.output
    }
    public func directories(_ host: Host, path: String = "~") async throws -> DirectoryListing {
        let path = try HostPath.expression(path)
        // NUL records inside base64 preserve spaces, quotes and shell metacharacters on both transports.
        // Expand only one level; never follow directory symlink entries or list file names.
        let script = """
        (
        set -eu
        cd -P \(path)
        test -r . && test -x .
        printf '%s\\0' "$HOME" "$PWD"
        base=${PWD%/}; count=0; more=0
        for entry in ./* ./.[!.]* ./..?*; do
          test -d "$entry" && test ! -L "$entry" || continue
          if test "$count" -ge 256; then more=1; break; fi
          printf '%s\\0' "$base/${entry#./}"
          count=$((count + 1))
        done
        printf '%s\\0' "$more"
        ) | base64
        """
        let result = try await execution.run(host, args: ["/bin/sh", "-c", script], timeout: 10)
        guard result.status == 0, !result.truncated, let data = Data(base64Encoded: result.output.filter { !$0.isWhitespace }) else { throw AEError("Cannot list host directories: " + result.error) }
        let records = data.split(separator: 0, omittingEmptySubsequences: false)
        guard records.count >= 4, records.last?.isEmpty == true,
              let home = String(data: Data(records[0]), encoding: .utf8), let current = String(data: Data(records[1]), encoding: .utf8),
              let limit = String(data: Data(records[records.count - 2]), encoding: .utf8), ["0", "1"].contains(limit) else { throw AEError("Directory is unavailable or not readable: " + result.error) }
        try absolutePath(home); try absolutePath(current)
        let directories = records.dropFirst(2).dropLast(2).compactMap { record -> HostDirectory? in
            guard let path = String(data: Data(record), encoding: .utf8), (try? absolutePath(path)) != nil else { return nil }
            return HostDirectory(name: URL(fileURLWithPath: path).lastPathComponent, path: path)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return DirectoryListing(host: host.id, path: current, home: home, parent: current == "/" ? nil : URL(fileURLWithPath: current).deletingLastPathComponent().path, directories: directories, truncated: limit == "1")
    }
}
extension Operations {
    public func directories(host id: String, path: String = "~") async throws -> DirectoryListing {
        try await HostFiles(execution: execution).directories(store.read().config.host(id), path: path)
    }
}
