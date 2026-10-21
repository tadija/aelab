import Foundation
import Testing
@testable import Core

@Test func portablePluginPathsUseEachHostHomeWithoutShellExpansion() throws {
    let plugin = try JSONDecoder().decode(Plugin.self, from: Data(#"{"name":"probe","executable":"~/bin/probe","arguments":["~/.aelab/plugins/it's $(literal).rb","--keep=$HOME"],"source":"~/.aelab/plugins/probe.rb"}"#.utf8))
    try plugin.validate()
    let first = try plugin.resolved(home: "/home/operator"), second = try plugin.resolved(home: "/Users/another user")
    #expect(first.executable == "/home/operator/bin/probe")
    #expect(second.arguments[0] == "/Users/another user/.aelab/plugins/it's $(literal).rb")
    #expect(first.arguments[1] == "--keep=$HOME")
    #expect(second.source == "/Users/another user/.aelab/plugins/probe.rb")
    for invalid in ["relative/probe.sh", "~someone/probe.sh", "~/../escape.sh", "~/bad\nname", "~/bad\0name"] {
        #expect(throws: (any Error).self) { try HostPath.validate(invalid) }
    }
}
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
@Test func scriptDeploymentRequiresExplicitLocalSourceAndRemoteTarget() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let store = try ConfigStore(home: home); try await store.initialize()
    var snapshot = try await store.read()
    snapshot.config.hosts.append(Host(name: "remote", destination: "unreachable-test-host"))
    try await store.write(snapshot.config, expected: snapshot.revision)
    let sources = PluginSources(store: store)
    await #expect(throws: (any Error).self) { _ = try await sources.deployment(host: "localhost", plugin: "probe", from: "localhost") }
    await #expect(throws: (any Error).self) { _ = try await sources.deployment(host: "localhost", plugin: "probe", from: "remote") }
}

@Test func absoluteLocalPluginSourcesUseManagedRemotePaths() throws {
    let interpreted = try JSONDecoder().decode(Plugin.self, from: Data(#"{"name":"disk","executable":"/bin/bash","arguments":["/Users/local/.aelab/plugins/disk.sh","--literal=$HOME","/data/input.json"]}"#.utf8))
    let local = try interpreted.resolved(home: "/Users/local")
    let remote = try interpreted.resolved(home: "/home/agent", remote: true)
    #expect(local.arguments[0] == "/Users/local/.aelab/plugins/disk.sh")
    #expect(remote.arguments == ["/home/agent/.aelab/plugins/disk/disk.sh", "--literal=$HOME", "/data/input.json"])
    #expect(remote.executable == "/bin/bash")
    let compiled = try JSONDecoder().decode(Plugin.self, from: Data(#"{"name":"uptime","executable":"/Users/local/.aelab/plugins/uptime","arguments":[],"source":"/Users/local/.aelab/plugins/uptime.swift"}"#.utf8))
    let target = try compiled.resolved(home: "/home/other user", remote: true)
    #expect(target.source == "/home/other user/.aelab/plugins/uptime/uptime.swift")
    #expect(target.executable == "/home/other user/.aelab/plugins/uptime/uptime")
    let other = try JSONDecoder().decode(Plugin.self, from: Data(#"{"name":"other","executable":"/bin/bash","arguments":["/Users/local/.aelab/plugins/disk.sh"]}"#.utf8))
    #expect(try other.resolved(home: "/home/agent", remote: true).arguments[0] == remote.arguments[0])
}
