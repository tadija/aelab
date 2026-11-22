import Foundation
import Testing
@testable import Core

@Test func directoryListingIsOneLevelDirectoryOnlyAndQuoted() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let store = try ConfigStore(home: home); try await store.initialize()
    let root = home.appendingPathComponent("browse ' $(touch unwanted)")
    for path in ["normal/nested", ".hidden", "space dir", "quote ' dir"] { try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true) }
    try Data("private".utf8).write(to: root.appendingPathComponent("secret-file"))
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
    let ops = Operations(store: store)
    let listing = try await ops.directories(host: "localhost", path: root.path)
    #expect(Set(listing.directories.map(\.name)) == Set(["normal", ".hidden", "space dir", "quote ' dir"]))
    #expect(!listing.truncated)
    #expect(!FileManager.default.fileExists(atPath: "unwanted"))
    #expect(listing.path.hasSuffix(root.lastPathComponent))
    #expect(listing.parent != nil)
    await #expect(throws: (any Error).self) { _ = try await ops.directories(host: "localhost", path: root.appendingPathComponent("secret-file").path) }
    await #expect(throws: (any Error).self) { _ = try await ops.directories(host: "unknown", path: root.path) }
    await #expect(throws: (any Error).self) { _ = try await ops.directories(host: "localhost", path: "relative") }
}
@Test func directoryListingBoundsLargeTrees() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    for index in 0...256 { try FileManager.default.createDirectory(at: root.appendingPathComponent("dir-\(index)"), withIntermediateDirectories: true) }
    let host = Host(name: "local", transport: .local)
    let listing = try await HostFiles().directories(host, path: root.path)
    #expect(listing.directories.count == 256)
    #expect(listing.truncated)
}
