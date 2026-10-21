import Foundation

/// A literal URL path prefix, independent of the authentication origin.
public struct WebBasePath: Sendable {
    public let value: String
    public var root: String { value + "/" }
    public init(_ raw: String = "") throws {
        let path = raw == "/" ? "" : raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        guard path.isEmpty || (path.hasPrefix("/") && path.dropFirst().split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".." && $0.range(of: "^[A-Za-z0-9._~-]+$", options: .regularExpression) != nil
        }) else { throw AEError("AELAB_BASE_PATH must be an absolute path such as /aelab, without encoded or empty segments") }
        value = path
    }
    public func relative(_ path: String) -> String? {
        if value.isEmpty { return path }
        if path == value { return "" }
        return path.hasPrefix(root) ? String(path.dropFirst(value.count)) : nil
    }
}
