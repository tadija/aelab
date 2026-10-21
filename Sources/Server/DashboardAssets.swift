import Foundation

/// Keep the dashboard from the same build for the lifetime of this server.
/// A checkout rebuild may replace dist while this process is still running.
struct DashboardAssets: Sendable {
    private let files: [String: Data]

    init(directory: String) throws {
        let root = URL(fileURLWithPath: directory).standardizedFileURL
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        let entries = FileManager.default.enumerator(atPath: root.path)
        var files: [String: Data] = [:]
        while let path = entries?.nextObject() as? String {
            let file = root.appendingPathComponent(path)
            if file.lastPathComponent.hasPrefix(".") { entries?.skipDescendants(); continue }
            let values = try file.resourceValues(forKeys: keys)
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            files["/" + path] = try Data(contentsOf: file)
        }
        self.files = files
    }

    func data(for path: String) -> Data? { files[path] }
}
