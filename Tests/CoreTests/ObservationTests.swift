import Foundation
import Testing
@testable import Core

@Test func repeatedLinuxHostObservationKeepsConcurrentResultsAlive() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let bin = root.appendingPathComponent("bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    let scripts = [
        "uname": "printf 'Linux fixture-vps 6.8\\n'",
        "systemctl": "printf 'example.service loaded active running Example\\n'",
        "docker": "printf '%s\\n' '{\"Names\":\"fixture-container\",\"State\":\"running\"}'",
        "tmux": "echo 'no server running' >&2; exit 1"
    ]
    for (name, script) in scripts {
        let path = bin.appendingPathComponent(name)
        try Data(("#!/bin/sh\n" + script + "\n").utf8).write(to: path)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
    }
    let store = try ConfigStore(home: root.appendingPathComponent("home"))
    try await store.initialize()
    var snapshot = try await store.read()
    snapshot.config.paths = [bin.path]
    snapshot.config.tools = (1...3).map { Tool(name: "tool-\($0)", executable: "/bin/sh", arguments: []) }
    snapshot.config.hosts[0].tools = snapshot.config.tools.map(\.id)
    snapshot.config.hosts[0].services = try (1...6).map { index in
        try JSONDecoder().decode(Service.self, from: Data("{\"id\":\"service-\(index)\",\"name\":\"Service \(index)\",\"provider\":\"systemd\",\"target\":\"example.service\"}".utf8))
    }
    try await store.write(snapshot.config, expected: snapshot.revision)
    let operations = Operations(store: store)
    for _ in 0..<40 {
        let observation = try await operations.observe("localhost")
        #expect(observation.reachable)
        #expect(observation.hostname == "fixture-vps")
        #expect(observation.platform == "linux")
        #expect(observation.systemd?.status == 0)
        #expect(observation.launchd == nil)
        #expect(observation.tmux?.status == 1)
        #expect(!String(decoding: try jsonEncoder.encode(observation), as: UTF8.self).contains("\"tools\""))
        #expect(observation.curated.count == 6)
        #expect(observation.discovered.map(\.target) == ["example.service", "fixture-container"])
        #expect(observation.home?.hasPrefix("/") == true)
    }
}

@Test func projectBranchesReadOnlyLiteralPathsAndDetachedHeads() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let repo = root.appendingPathComponent("repo ' $(printf injected)")
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    let initialized = try await ProcessRunner.run(executable: "/usr/bin/env", arguments: ["git", "init", "--template=", repo.path])
    #expect(initialized.status == 0)
    let named = try await ProcessRunner.run(executable: "/usr/bin/env", arguments: ["git", "-C", repo.path, "symbolic-ref", "HEAD", "refs/heads/feature/Case-Sensitive"])
    #expect(named.status == 0)
    let operations = Operations(store: try ConfigStore(home: root.appendingPathComponent("home")))
    let host = Host(name: "local", transport: .local)
    let head = repo.appendingPathComponent(".git/HEAD"), before = try Data(contentsOf: repo.appendingPathComponent(".git/HEAD"))
    #expect(await operations.projectBranch(host, directory: repo.path) == "feature/Case-Sensitive")
    #expect(try Data(contentsOf: head) == before)
    #expect(!FileManager.default.fileExists(atPath: repo.appendingPathComponent(".git/index").path))
    #expect(await operations.projectBranch(host, directory: root.path) == nil)
    #expect(await operations.projectBranch(host, directory: root.appendingPathComponent("missing").path) == nil)
    try Data((String(repeating: "1", count: 40) + "\n").utf8).write(to: head)
    #expect(await operations.projectBranch(host, directory: repo.path) == nil)
}
