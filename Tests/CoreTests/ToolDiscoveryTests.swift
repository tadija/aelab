import Foundation
import Testing
@testable import Core

@Test func executableDiscoveryNeverRunsCandidatesAndHonorsPATH() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let executable = root.appendingPathComponent("fake tool")
    try Data("#!/bin/sh\nexit 99\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let result = try await ProcessRunner.run(executable: "/bin/sh", arguments: ["-c", "PATH=\(quote(root.path)); " + ExecutableProbe.script("fake tool")])
    #expect(result.status == 0); #expect(result.output.trimmingCharacters(in: .whitespacesAndNewlines) == executable.path)
    let missing = try await ProcessRunner.run(executable: "/bin/sh", arguments: ["-c", "PATH=\(quote(root.path)); " + ExecutableProbe.script("missing")])
    #expect(missing.status == 1)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: executable.path)
    let unavailable = try await ProcessRunner.run(executable: "/bin/sh", arguments: ["-c", ExecutableProbe.script(executable.path)])
    #expect(unavailable.status == 1)
}


private func tool(_ id: String, executable: String = "/bin/sh") throws -> Tool {
    try JSONDecoder().decode(Tool.self, from: JSONSerialization.data(withJSONObject: ["id":id,"name":id,"executable":executable,"arguments":["-c","printf safe"],"directory":"/tmp"]))
}
@Test func centralToolsShareDefinitionsButRequireHostEnablement() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let store = try ConfigStore(home: home); try await store.initialize()
    var snapshot = try await store.read()
    snapshot.config.tools = [try tool("shell")]; snapshot.config.hosts[0].tools = ["shell"]
    snapshot.config.hosts.append(Host(name: "other", transport: .local))
    try await store.write(snapshot.config, expected: snapshot.revision)
    let ops = Operations(store: store), config = try await store.read().config
    try await ops.validateLaunch(TerminalLaunch(host: "localhost", tool: "shell"), config: config)
    #expect(throws: (any Error).self) { _ = try TerminalLaunch(host: "other", tool: "shell").resolve(config) }
    let inventory = try await ops.discoverTools("other")
    #expect(inventory.tools.count == 1); #expect(inventory.tools[0].state == "installed"); #expect(!inventory.tools[0].enabled)
    #expect(try await ops.discoverTools("other").checked == inventory.checked)
    var changed = config; changed.hosts[1].tools = ["shell"]; changed.tools[0].arguments = ["-l"]
    #expect(try TerminalLaunch(host: "other", tool: "shell").resolve(changed).1.contains("'-l'"))
    changed.hosts[0].tools = []
    #expect(throws: (any Error).self) { _ = try TerminalLaunch(host: "localhost", tool: "shell").resolve(changed) }
    changed.tools[0].directory = "/aelab-missing-\(UUID())"
    await #expect(throws: (any Error).self) { try await ops.validateLaunch(TerminalLaunch(host: "other", tool: "shell"), config: changed) }
}
@Test func discoveryErrorsRemainDistinctAndPresetsRemainSeparate() async throws {
    var config = Configuration(); let host = Host(name: "remote", destination: "unused.invalid"); config.hosts = [host]
    config.tools = [try tool("one"), try tool("two")]
    let execution = HostExecution(ssh: SSH(configFile: "/tmp/aelab-missing-\(UUID())"))
    let discovery = ToolDiscovery()
    let inventory = await discovery.discover(host: host, config: config, execution: execution)
    #expect(inventory.tools.count == 2); #expect(inventory.tools.allSatisfy { $0.state == "discovery-error" && $0.error != nil })
    let refreshed = await discovery.discover(host: host, config: config, execution: execution, refresh: true)
    #expect(refreshed.tools.allSatisfy { $0.state == "discovery-error" })
    config.hosts = [Host(name: "local", transport: .local)]
    let local = await discovery.discover(host: config.hosts[0], config: config, execution: HostExecution())
    #expect(local.tools.map(\.tool.id) == ["one", "two"]); #expect(local.tools.allSatisfy { $0.state == "installed" })
}
@Test func centralConfigurationRejectsUnknownDuplicateAndOldDefinitions() throws {
    var config = Configuration(); config.tools = [try tool("shell")]; config.hosts = [Host(name: "local", transport: .local)]
    config.hosts[0].tools = ["missing"]
    #expect(throws: (any Error).self) { try config.validate() }
    config.hosts[0].tools = ["shell", "shell"]
    #expect(throws: (any Error).self) { try config.validate() }
    config.hosts[0].tools = ["shell"]; config.tools.append(config.tools[0])
    #expect(throws: (any Error).self) { try config.validate() }
    for text in [#"{"version":1,"hosts":[],"toolCatalog":[]}"#, #"{"version":1,"hosts":[{"name":"a","transport":"local","path":[]}]}"#, #"{"version":1,"hosts":[{"name":"a","transport":"local","tools":[{"id":"old"}]}]}"#] {
        #expect(throws: (any Error).self) { _ = try ConfigStore.validateDocument(text) }
    }
}
@Test func ttyButtonsStayOneLineAndPreserveEscapedLabels() throws {
    var config = Configuration(); config.ttyButtons = [TTYButton(key: "ctrl-c", label: "Stop \"now\""), TTYButton(key: "enter", label: "Enter")]
    let data = try configurationData(config), text = String(decoding: data, as: UTF8.self)
    #expect(text.split(separator: "\n").filter { $0.contains("\"key\"") }.count == 2)
    #expect(try JSONDecoder().decode(Configuration.self, from: data).ttyButtons[0].label == "Stop \"now\"")
}
