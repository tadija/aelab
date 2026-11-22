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
