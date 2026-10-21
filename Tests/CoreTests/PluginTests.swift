import Foundation
import Testing
@testable import Core

private func plugin(_ text: String) throws -> Plugin { try JSONDecoder().decode(Plugin.self, from: Data(text.utf8)) }
private let validReport = #"{"version":1,"status":"ok","summary":"Real probe","details":[{"label":"Value","value":"<script>literal</script>"}]}"#

@Test func pluginContractsAndLimits() throws {
    let definition = try plugin(#"{"name":"probe","executable":"/bin/sh","arguments":[]}"#)
    try definition.validate(); #expect(definition.timeout == 10)
    for timeout in [0, 31] { var bad = definition; bad.timeout = timeout; #expect(throws: (any Error).self) { try bad.validate() } }
    var bad = definition; bad.executable = "-unsafe"; #expect(throws: (any Error).self) { try bad.validate() }
    bad = definition; bad.arguments = ["\0"]; #expect(throws: (any Error).self) { try bad.validate() }
    let result = CommandResult(status: 0, output: validReport, error: "", truncated: false)
    #expect(try PluginReport.parse(result).details.first?.value == "<script>literal</script>")
    for output in ["not json", validReport.replacingOccurrences(of: "\"version\":1", with: "\"version\":9"), validReport.replacingOccurrences(of: "\"ok\"", with: "\"made-up\""), String(repeating: " ", count: 65_537), validReport.replacingOccurrences(of: "Real probe", with: String(repeating: "x", count: 513))] {
        #expect(throws: (any Error).self) { _ = try PluginReport.parse(CommandResult(status: 0, output: output, error: "", truncated: false)) }
    }
    for result in [CommandResult(status: 1, output: validReport, error: "private diagnostic", truncated: false), CommandResult(status: 0, output: validReport, error: "", truncated: true)] {
        #expect(throws: (any Error).self) { _ = try PluginReport.parse(result) }
    }
}
@Test func pluginExecutionIsExplicitScopedAuditedAndBounded() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let store = try ConfigStore(home: home); try await store.initialize()
    var snapshot = try await store.read()
    var definition = try plugin(#"{"name":"probe","executable":"/bin/sh","arguments":[]}"#)
    // Script uses environment metadata and the fixed hook; none comes from HTTP request data.
    definition.arguments = ["-c", "test \"$2\" = --aelab-probe && test \"$AELAB_HOST_ID\" = localhost && test \"$AELAB_PLUGIN_ID\" = probe && printf '%s' \"$1\"", "fixture", validReport]
    snapshot.config.plugins = [definition]; snapshot.config.hosts[0].plugins = [definition.id]
    snapshot.config.hosts.append(Host(name: "other", transport: .local))
    try await store.write(snapshot.config, expected: snapshot.revision)
    let ops = Operations(store: store)
    // No implicit execution during ordinary observation/config reads.
    #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("state/audit.log").path))
    await #expect(throws: (any Error).self) { _ = try await ops.probePlugin(host: "other", plugin: "probe") }
    let result = try await ops.probePlugin(host: "localhost", plugin: "probe")
    #expect(result.report?.summary == "Real probe"); #expect(result.error == nil)
    let audit = try String(contentsOf: home.appendingPathComponent("state/audit.log"), encoding: .utf8)
    #expect(audit.contains("reported")); #expect(!audit.contains("<script>")); #expect(!audit.contains("Real probe"))
    snapshot = try await store.read(); definition.arguments = ["-c", "printf 'private diagnostic' >&2; exit 7"]
    snapshot.config.plugins = [definition]; snapshot.config.hosts[0].plugins = [definition.id]; try await store.write(snapshot.config, expected: snapshot.revision)
    let failed = try await ops.probePlugin(host: "localhost", plugin: "probe")
    #expect(failed.exitStatus == 7); #expect(failed.report == nil); #expect(failed.error?.contains("private diagnostic") == false)
    snapshot = try await store.read(); definition.timeout = 1; definition.arguments = ["-c", "sleep 10"]
    snapshot.config.plugins = [definition]; snapshot.config.hosts[0].plugins = [definition.id]; try await store.write(snapshot.config, expected: snapshot.revision)
    let timeout = try await ops.probePlugin(host: "localhost", plugin: "probe")
    #expect(timeout.exitStatus == 124); #expect(timeout.report == nil)
    snapshot = try await store.read(); snapshot.config.plugins.append(definition)
    #expect(throws: (any Error).self) { try snapshot.config.validate() }
}

@Test func sharedPluginAvailabilityNeverRunsScriptsAndEnablementIsRequired() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let store = try ConfigStore(home: home); try await store.initialize()
    let script = home.appendingPathComponent("probe.sh"), marker = home.appendingPathComponent("must-not-exist")
    try Data(("#!/bin/sh\ntouch " + quote(marker.path) + "\n").utf8).write(to: script)
    var snapshot = try await store.read()
    var definition = try plugin(#"{"name":"probe","executable":"sh","arguments":[]}"#)
    definition.arguments = [script.path]; snapshot.config.plugins = [definition]
    try await store.write(snapshot.config, expected: snapshot.revision)
    let ops = Operations(store: store)
    #expect(try await ops.discoverPlugins(host: "localhost")[0].state == "installed")
    #expect(!FileManager.default.fileExists(atPath: marker.path))
    await #expect(throws: (any Error).self) { _ = try await ops.probePlugin(host: "localhost", plugin: "probe") }
    try FileManager.default.removeItem(at: script)
    #expect(try await ops.discoverPlugins(host: "localhost")[0].state == "unavailable")
    #expect(!FileManager.default.fileExists(atPath: marker.path))
}

@Test func diskProbeUsesAPFSSharedCapacityAndPreservesLinuxPercentage() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Plugins/disk-space.sh")
    func executable(_ name: String, _ body: String) throws {
        let path = root.appendingPathComponent(name)
        try Data(("#!/bin/sh\n" + body + "\n").utf8).write(to: path)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
    }
    let cases: [(String, String, Int?, String)] = [
        ("Linux", "1000 450 500 49%", 49, "ok"),
        ("Darwin", "1000 20 300 7%", 70, "ok"),
        ("Darwin", "1000 20 200 10%", 80, "warning"),
        ("Darwin", "1000 20 99 17%", 91, "critical"),
        ("Darwin", "1000 20 0 100%", 100, "critical"),
        ("Darwin", "0 20 0 100%", nil, ""),
        ("Darwin", "1000 20 1001 2%", nil, ""),
        ("Linux", "invalid output", nil, "")
    ]
    for (platform, fields, expected, status) in cases {
        try executable("uname", "printf '%s\n' " + quote(platform))
        try executable("df", "printf '%s\n' 'Filesystem 1024-blocks Used Available Capacity Mounted on' " + quote("/dev/test " + fields + " /"))
        let result = try await ProcessRunner.run(executable: "/usr/bin/env", arguments: ["PATH=" + root.path + ":/usr/bin:/bin", "/bin/bash", script.path, "--aelab-probe"])
        if let expected {
            let report = try PluginReport.parse(result)
            #expect(report.summary == "Root filesystem: \(expected)% used")
            #expect(report.status.rawValue == status)
            #expect(report.details.contains { $0.label == "Scope" && $0.value == (platform == "Darwin" ? "Shared APFS space (total minus available)" : "Root filesystem") })
        } else { #expect(result.status != 0); #expect(result.output.isEmpty) }
    }
}
