import Foundation

public enum RuntimePaths {
    public static var executable: URL {
        (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
    }

    public static func initialConfiguration() throws -> Configuration? {
        let installed = executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("config/aelab.example.json")
        if FileManager.default.fileExists(atPath: installed.path) { return try ConfigStore.validateDocument(String(contentsOf: installed, encoding: .utf8)) }
        var parent = executable.deletingLastPathComponent()
        while parent.path != "/" {
            let candidate = parent.appendingPathComponent("Docs/Config/aelab.example.json")
            if FileManager.default.fileExists(atPath: candidate.path) { return try ConfigStore.validateDocument(String(contentsOf: candidate, encoding: .utf8)) }
            parent.deleteLastPathComponent()
        }
        return nil
    }
    public static var publicDirectory: String {
        let installed = executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("public")
        if FileManager.default.fileExists(atPath: installed.appendingPathComponent("index.html").path) { return installed.path }
        return "Frontend/dist"
    }
}
