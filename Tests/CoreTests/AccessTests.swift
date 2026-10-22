import Foundation
import Testing
@testable import Core

@Test func hostPathIsLiteralSharedAndValidated() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("aelab path ' \(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("aelab-test-tool")
    try Data("#!/bin/sh\nprintf path-ok".utf8).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
    var config = Configuration(); config.paths = [dir.path]; config.hosts = [Host(name: "local", transport: .local)]
    let host = try config.host("local")
    let execution = HostExecution()
    #expect(try await execution.run(host, args: ["aelab-test-tool"]).output == "path-ok")
    #expect(try await execution.execute(host, script: ExecutableProbe.script("aelab-test-tool")).output.trimmingCharacters(in: .newlines) == file.path)
    let terminal = try execution.terminalCommand(host, script: "aelab-test-tool")
    #expect(try await ProcessRunner.run(executable: terminal.executable, arguments: terminal.arguments).output == "path-ok")
    try config.validate()
    #expect(try JSONDecoder().decode(Configuration.self, from: jsonEncoder.encode(config)).paths == [dir.path])
    for path in [["relative"], ["/bad:path"], ["/same", "/same"], ["/bad\npath"], ["/bad\rpath"]] {
        config.paths = path
        #expect(throws: (any Error).self) { try config.validate() }
    }
}
@Test func configuredProjectSessionAndStandaloneToolDirectory() throws {
    let data = Data(#"{"version":1,"hosts":[{"name":"h","transport":"local","projects":[{"name":"p","directory":"/srv/p","session":"configured"}],"tools":["t"],"plugins":[]}],"tools":[{"name":"t","executable":"test-tool","arguments":[],"yoloArguments":["--yes"]}],"plugins":[],"paths":[]}"#.utf8)
    let config = try JSONDecoder().decode(Configuration.self, from: data)
    let (_, script, session) = try TerminalLaunch(host: "h", project: "p").resolve(config)
    #expect(session == "configured"); #expect(script.contains("new-session")); #expect(script.contains("-A"))
    #expect(try TerminalLaunch(host: "h", project: "p", persistent: false).resolve(config).2 == nil)
    #expect(try TerminalLaunch(host: "h", project: "p", tool: "t").resolve(config).2 == nil)
    var launch = TerminalLaunch(host: "h", tool: "t", yolo: true); launch.directory = "/srv/it's literal"
    #expect(try launch.resolve(config).1.contains("cd -- '/srv/it'"))
    launch.yolo = false
    let normal = try launch.resolve(config).1
    #expect(normal.contains("cd -- '/srv/it'")); #expect(!normal.contains("--yes"))
    var plain = config; plain.tools[0].yoloArguments = nil
    #expect(try launch.resolve(plain).1 == normal)
    var disabled = config; disabled.hosts[0].tools = []
    #expect(throws: (any Error).self) { _ = try launch.resolve(disabled) }
    launch.yolo = true
    #expect(throws: (any Error).self) { _ = try launch.resolve(plain) }
    launch.yolo = false
    launch.tool = nil
    #expect(throws: (any Error).self) { _ = try launch.resolve(config) }
    launch.tool = "t"; launch.directory = "relative"
    #expect(throws: (any Error).self) { _ = try launch.resolve(config) }
    launch.directory = "/srv/it's literal"
    launch.yolo = true; launch.project = "p"
    #expect(throws: (any Error).self) { _ = try launch.resolve(config) }
}

@Test func hostShellsStartInPlatformHome() throws {
    var config = Configuration()
    config.hosts = [Host(name: "local", transport: .local)]
    let shell = try TerminalLaunch(host: "local").resolve(config).1
    #expect(shell.hasPrefix("cd -- \"$HOME\" && "))
    let tmux = try TerminalLaunch(host: "local", persistent: true).resolve(config).1
    #expect(tmux.contains(" -c \"$HOME\" "))
    let attached = try TerminalLaunch(host: "local", session: "existing").resolve(config).1
    #expect(attached.contains("attach-session"))
    #expect(!attached.contains("$HOME"))
}
