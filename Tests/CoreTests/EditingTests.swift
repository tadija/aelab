import Foundation
import Testing
@testable import Core

@Test func hostIdentityDetectsNativeNamesAndPlatforms() {
    #expect(HostIdentity.parse("Darwin aeMini 25.0.0").hostname == "aeMini")
    #expect(HostIdentity.parse("Darwin aeMini 25.0.0").platform == "macos")
    #expect(HostIdentity.parse("Linux ubuntu-4gb-hel1-app 6.8.0").platform == "linux")
    #expect(HostIdentity.parse("Linux workstation 5.15.0-microsoft-standard-WSL2").platform == "wsl")
}
@Test func projectDirectoryCreationIsExplicitIdempotentAndQuoted() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let store = try ConfigStore(home: home); try await store.initialize()
    let path = home.appendingPathComponent("project ' $(touch should-not-run)/nested").path
    let project = Project(name: "app", directory: path)
    let operations = Operations(store: store)
    try await operations.prepareProject(host: "localhost", project: project)
    try await operations.prepareProject(host: "localhost", project: project)
    #expect(FileManager.default.fileExists(atPath: path))
    #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("should-not-run").path))
    await #expect(throws: (any Error).self) { try await operations.prepareProject(host: "unknown", project: project) }
}
@Test func pluginSourceEditingIsScopedAtomicAndConflictAware() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let store = try ConfigStore(home: home); try await store.initialize()
    let path = home.appendingPathComponent("probe ' file.sh")
    try Data("#!/bin/bash\nprintf hello\n".utf8).write(to: path)
    try FileManager.default.setAttributes([.posixPermissions: 0o750], ofItemAtPath: path.path)
    var snapshot = try await store.read()
    let data = try JSONSerialization.data(withJSONObject: ["id":"probe", "name":"Probe", "executable":"/bin/bash", "arguments":[path.path]])
    snapshot.config.plugins = [try JSONDecoder().decode(Plugin.self, from: data)]; snapshot.config.hosts[0].plugins = ["probe"]
    try await store.write(snapshot.config, expected: snapshot.revision)
    let sources = PluginSources(store: store)
    #expect(try await sources.list(host: "localhost").count == 1)
    let original = try await sources.read(host: "localhost", plugin: "probe")
    let updated = try await sources.edit(host: "localhost", plugin: "probe", document: ConfigDocument(content: "#!/bin/bash\nprintf goodbye\n", revision: original.revision), save: true)
    #expect(updated.content == (try String(contentsOf: path, encoding: .utf8)))
    // Keep the shell command below Linux's per-argument limit even near the source limit.
    let large = "#!/bin/bash\n#" + String(repeating: "x", count: 60_000) + "\n"
    let big = try await sources.edit(host: "localhost", plugin: "probe", document: ConfigDocument(content: large, revision: updated.revision), save: true)
    _ = try await sources.edit(host: "localhost", plugin: "probe", document: ConfigDocument(content: updated.content, revision: big.revision), save: true)
    let permissions = try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as? NSNumber
    #expect(permissions?.intValue == 0o750)
    await #expect(throws: (any Error).self) { _ = try await sources.edit(host: "localhost", plugin: "probe", document: original, save: true) }
    await #expect(throws: (any Error).self) { _ = try await sources.edit(host: "localhost", plugin: "probe", document: ConfigDocument(content: "if then", revision: updated.revision), save: true) }
    #expect(try String(contentsOf: path, encoding: .utf8) == updated.content)
    await #expect(throws: (any Error).self) { _ = try await sources.read(host: "localhost", plugin: "../config") }
    await #expect(throws: (any Error).self) { _ = try await sources.read(host: "other", plugin: "probe") }
    try FileManager.default.removeItem(at: path)
    let target = home.appendingPathComponent("other.sh"); try Data("echo secret".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: path, withDestinationURL: target)
    await #expect(throws: (any Error).self) { _ = try await sources.read(host: "localhost", plugin: "probe") }
    #expect(try await sources.list(host: "localhost").isEmpty)
}

@Test func projectConfigUsesDirKey() throws {
    let project = try JSONDecoder().decode(Project.self, from: Data(#"{"name":"app","dir":"/srv/app"}"#.utf8))
    #expect(project.directory == "/srv/app")
    let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as! [String: String]
    #expect(encoded["dir"] == "/srv/app")
    #expect(encoded["directory"] == nil)
    #expect(throws: (any Error).self) {
        _ = try JSONDecoder().decode(Project.self, from: Data(#"{"name":"app","directory":"/srv/app"}"#.utf8))
    }
}
