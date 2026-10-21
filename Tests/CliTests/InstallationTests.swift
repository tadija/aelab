import Foundation
import Testing
@testable import Cli

private func source(at root: URL) throws -> URL {
    let source = root.appendingPathComponent("source")
    let fm = FileManager.default
    try fm.createDirectory(at: source.appendingPathComponent(".build/release"), withIntermediateDirectories: true)
    try fm.createDirectory(at: source.appendingPathComponent("Frontend/dist/assets"), withIntermediateDirectories: true)
    for name in ["aelab", "aelab-server"] {
        let path = source.appendingPathComponent(".build/release/" + name)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: path)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
    }
    try Data("dashboard".utf8).write(to: source.appendingPathComponent("Frontend/dist/index.html"))
    try Data("asset".utf8).write(to: source.appendingPathComponent("Frontend/dist/assets/app.js"))
    try fm.createDirectory(at: source.appendingPathComponent("Docs/Config"), withIntermediateDirectories: true)
    try Data("{\"version\":1,\"hosts\":[]}".utf8).write(to: source.appendingPathComponent("Docs/Config/aelab.example.json"))
    return source
}

@Test func installationCopiesCompleteReleaseAndUpdatesStableLinks() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try source(at: root)
    let location = Installation.location(prefix: root.appendingPathComponent("prefix with spaces"))
    try location.install(source: source)
    let first = try FileManager.default.destinationOfSymbolicLink(atPath: location.application.appendingPathComponent("current").path)
    #expect(FileManager.default.isExecutableFile(atPath: location.bin.appendingPathComponent("aelab").path))
    #expect(FileManager.default.isExecutableFile(atPath: location.bin.appendingPathComponent("aelab-server").path))
    #expect(try String(contentsOf: location.application.appendingPathComponent("current/public/assets/app.js"), encoding: .utf8) == "asset")
    #expect(try String(contentsOf: location.application.appendingPathComponent("current/config/aelab.example.json"), encoding: .utf8) == "{\"version\":1,\"hosts\":[]}")
    try Data("updated dashboard".utf8).write(to: source.appendingPathComponent("Frontend/dist/index.html"))
    try location.install(source: source)
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: location.application.appendingPathComponent("current").path) != first)
    try FileManager.default.removeItem(at: source)
    #expect(try String(contentsOf: location.application.appendingPathComponent("current/public/index.html"), encoding: .utf8) == "updated dashboard")
    #expect(FileManager.default.isExecutableFile(atPath: location.bin.appendingPathComponent("aelab").path))
}

@Test func installationRefusesUnrelatedExecutablesAndCurrentLinks() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try source(at: root)
    let location = Installation.location(prefix: root.appendingPathComponent("install"))
    try FileManager.default.createDirectory(at: location.bin, withIntermediateDirectories: true)
    let unrelated = location.bin.appendingPathComponent("aelab")
    try Data("unrelated".utf8).write(to: unrelated)
    #expect(throws: (any Error).self) { try location.install(source: source) }
    #expect(try String(contentsOf: unrelated, encoding: .utf8) == "unrelated")
    try FileManager.default.removeItem(at: unrelated)
    try FileManager.default.createDirectory(at: location.application, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(atPath: location.application.appendingPathComponent("current").path, withDestinationPath: "/unrelated")
    #expect(throws: (any Error).self) { try location.install(source: source) }
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: location.application.appendingPathComponent("current").path) == "/unrelated")
}

@Test func incompleteBuildDoesNotCreateInstallation() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let location = Installation.location(prefix: root.appendingPathComponent("install"))
    #expect(throws: (any Error).self) { try location.install(source: root.appendingPathComponent("missing source")) }
    #expect(!FileManager.default.fileExists(atPath: location.application.path))
}

@Test func installationUsesSharedXDGPathsAndExplicitPrefix() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    for environment in [[:], ["XDG_DATA_HOME": ""], ["XDG_DATA_HOME": "relative/path"]] {
        let location = Installation.location(prefix: nil, environment: environment)
        #expect(location.bin == home.appendingPathComponent(".local/bin"))
        #expect(location.application == home.appendingPathComponent(".local/share/aelab"))
    }
    let custom = Installation.location(prefix: nil, environment: ["XDG_DATA_HOME": "/tmp/custom data"])
    #expect(custom.bin == home.appendingPathComponent(".local/bin"))
    #expect(custom.application.path == "/tmp/custom data/aelab")
    let prefix = Installation.location(prefix: URL(fileURLWithPath: "/tmp/prefix"), environment: ["XDG_DATA_HOME": "/tmp/ignored"])
    #expect(prefix.bin.path == "/tmp/prefix/bin")
    #expect(prefix.application.path == "/tmp/prefix/share/aelab")
}
