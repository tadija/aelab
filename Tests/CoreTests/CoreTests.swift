import Testing
import Foundation
@testable import Core

@Test func quotingDoesNotInterpolate() {
    #expect(command(["echo", "x'; $(touch /tmp/evil)\n`id`"]) == "'echo' 'x'\\''; $(touch /tmp/evil)\n`id`'")
}
@Test func strictSSHAndHostValidation() throws {
    let ssh = SSH(); let args = ssh.arguments(Host(name: "one", destination: "user@host", port: 2222))
    #expect(args.contains("StrictHostKeyChecking=yes")); #expect(args.contains("BatchMode=yes")); #expect(args.contains("ForwardAgent=no")); #expect(args.suffix(2) == ["--", "user@host"])
    for value in ["-oProxyCommand=evil", "host;id", "$(id)", "host\nother"] {
        var config = Configuration(); config.hosts = [Host(name: "a", destination: value)]
        #expect(throws: (any Error).self) { try config.validate() }
    }
}
@Test func sshDestinationIsIndependentOfNameAndDerivedID() throws {
    var host = Host(name: "Friendly dashboard label", destination: "agent@approved-ssh-alias", port: 2222)
    let ssh = SSH(configFile: "/tmp/approved-ssh-config")
    #expect(host.id == "friendly-dashboard-label")
    #expect(ssh.arguments(host).suffix(2) == ["--", "agent@approved-ssh-alias"])
    #expect(!ssh.arguments(host).contains(host.name) && !ssh.arguments(host).contains(host.id))
    host.name = "Renamed dashboard label"
    let terminal = try HostExecution(ssh: ssh).terminalCommand(host, script: "pwd")
    #expect(terminal.executable == "/usr/bin/ssh")
    #expect(Array(terminal.arguments.suffix(3)) == ["--", "agent@approved-ssh-alias", "pwd"])
    #expect(terminal.arguments.contains("-tt") && terminal.arguments.contains("StrictHostKeyChecking=yes"))
}

@Test func configAtomicityAndConflict() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let first = try ConfigStore(home: home); let second = try ConfigStore(home: home)
    try await first.initialize(); let initial = try await first.read()
    var config = initial.config; config.hosts = [Host(name: "a", destination: "host-a")]
    try await first.write(config, expected: initial.revision)
    await #expect(throws: RevisionConflict.self) { try await second.write(Configuration(), expected: initial.revision) }
    #expect(try await second.read().config.hosts.first?.id == "a")
    var bad = config; bad.hosts.append(config.hosts[0])
    await #expect(throws: (any Error).self) { try await first.write(bad, expected: await first.read().revision) }
    #expect(try await first.read().config.hosts.count == 1)
    try await first.audit("restart", host: "a", target: "unit", outcome: "ok")
    #expect(try String(contentsOf: home.appendingPathComponent("state/audit.log"), encoding: .utf8).contains("restart"))
}
@Test func hostScopedLaunchAndLiteralArguments() throws {
    let data = Data(#"{"version":1,"hosts":[{"name":"a","destination":"host-a","projects":[{"name":"p","dir":"/srv/it's a project","session":"saved"}],"services":[],"tools":["t"],"plugins":[]},{"name":"b","destination":"host-b","projects":[],"services":[],"tools":[],"plugins":[]}],"tools":[{"name":"t","executable":"codex","arguments":["$(touch /tmp/evil)"]}],"plugins":[],"paths":[]}"#.utf8)
    let config = try JSONDecoder().decode(Configuration.self, from: data); try config.validate()
    let encoded = try JSONSerialization.jsonObject(with: jsonEncoder.encode(config)) as! [String: Any]
    #expect(encoded["projects"] == nil); #expect((encoded["hosts"] as? [[String: Any]])?.first?["projects"] != nil)
    let (host, script, session) = try TerminalLaunch(host: "a", project: "p", tool: "t", persistent: true).resolve(config)
    let (_, ordinary, ordinarySession) = try TerminalLaunch(host: "a", project: "p", tool: "t").resolve(config)
    #expect(ordinarySession == nil); #expect(!ordinary.contains("tmux"))
    let (_, attached, _) = try TerminalLaunch(host: "a", session: "saved").resolve(config)
    #expect(attached.contains("attach-session")); #expect(!attached.contains("new-session"))
    #expect(host.destination == "host-a"); #expect(session == "saved"); #expect(script.contains("new-session")); #expect(script.contains("-A")); #expect(script.contains("/srv/it"))
    #expect(throws: (any Error).self) { _ = try TerminalLaunch(host: "b", project: "p").resolve(config) }
    #expect(throws: (any Error).self) { _ = try TerminalLaunch(host: "a", session: "bad:target").resolve(config) }
    #expect(throws: (any Error).self) { _ = try TerminalLaunch(host: "a", tool: "t", yolo: true).resolve(config) }
    #expect(throws: (any Error).self) { _ = try TerminalLaunch(host: "a", yolo: true).resolve(config) }
}
@Test func serviceBoundariesAndCompose() throws {
    let data = Data(#"{"name":"s","provider":"compose","target":"app","directory":"/srv/app","files":["/srv/app/compose.yml"],"environmentFile":"/srv/app/.env"}"#.utf8)
    var s = try JSONDecoder().decode(Service.self, from: data)
    let stop = try ServiceCommands.arguments(s, operation: "stop")
    #expect(stop.contains("--project-directory")); #expect(stop.contains("--project-name"));
    #expect(stop.last == "stop"); #expect(!stop.contains("down")); #expect(!stop.contains("up")); #expect(stop.contains("--env-file"))
    s.directory = nil
    #expect(throws: (any Error).self) { _ = try ServiceCommands.arguments(s, operation: "restart") }
    s.provider = .systemd; s.sudo = true
    #expect(try ServiceCommands.arguments(s, operation: "start").prefix(2) == ["sudo", "-n"])
    #expect(throws: (any Error).self) { _ = try ServiceCommands.arguments(s, operation: "down") }
}
@Test func discoveryGroupsNativeServices() {
    let list = Operations.parseDiscovery(systemd: "a.service loaded failed failed description", docker: #"{"Names":"app-one","State":"running","Labels":"com.docker.compose.project=app","Image":"test"}"#)
    #expect(list.last?.composeProject == "app");
    #expect(list.count == 3); #expect(list.first?.state == "failed/failed"); #expect(list.last?.provider == .compose)
}
@Test func authenticationAndCSRF() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    _ = try ConfigStore(home: home); let auth = Authentication(home: home)
    try await auth.bootstrap("a long test password")
    await #expect(throws: (any Error).self) { try await auth.bootstrap("another test password") }
    await #expect(throws: (any Error).self) { _ = try await auth.authorize(token: nil) }
    let session = try await auth.login("a long test password")
    _ = try await auth.authorize(token: session.token, csrf: session.csrf, mutation: true)
    await #expect(throws: (any Error).self) { _ = try await auth.authorize(token: session.token, csrf: "bad", mutation: true) }
    await auth.logout(session.token)
    await #expect(throws: (any Error).self) { _ = try await auth.authorize(token: session.token) }
}
@Test func singleUseOwnerBoundTerminalTickets() async throws {
    let registry = TerminalRegistry(); let id = try await registry.issue(TerminalLaunch(host: "a"), owner: "admin")
    await #expect(throws: (any Error).self) { _ = try await registry.consume(id, owner: "other") }
    #expect(try await registry.consume(id, owner: "admin").host == "a")
    await #expect(throws: (any Error).self) { _ = try await registry.consume(id, owner: "admin") }
    await registry.release()
}
@Test func boundedProcessAndTimeout() async throws {
    let result = try await ProcessRunner.run(executable: "/bin/sh", arguments: ["-c", "printf hello; printf denied >&2"])
    #expect(result.output == "hello"); #expect(result.error == "denied")
    let timeout = try await ProcessRunner.run(executable: "/bin/sleep", arguments: ["10"], timeout: 0.05)
    #expect(timeout.category == "timeout")
}

@Test func passwordKDFKnownVectorAndResetInvalidation() async throws {
    let result = PasswordRecord.derive("password", salt: Data("salt".utf8), iterations: 1)
    #expect(result.map { String(format: "%02x", $0) }.joined() == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    _ = try ConfigStore(home: home); let server = Authentication(home: home); let recovery = Authentication(home: home)
    try await server.bootstrap("a long test password")
    let session = try await server.login("a long test password")
    try await recovery.reset("a different test password")
    await #expect(throws: (any Error).self) { _ = try await server.authorize(token: session.token) }
}
@Test func configurationRejectsCrossHostToolAndInvalidPaths() throws {
    let data = Data(#"{"version":1,"hosts":[{"name":"a","destination":"a","projects":[{"name":"p","dir":"/srv/p"}],"services":[],"tools":[],"plugins":[]},{"name":"b","destination":"b","projects":[],"services":[],"tools":["t"],"plugins":[]}],"tools":[{"name":"t","executable":"sh","arguments":[]}],"plugins":[],"paths":[]}"#.utf8)
    let config = try JSONDecoder().decode(Configuration.self, from: data)
    #expect(throws: (any Error).self) { _ = try TerminalLaunch(host: "a", project: "p", tool: "t").resolve(config) }
    #expect(throws: (any Error).self) { try absolutePath("relative/path") }
    #expect(throws: (any Error).self) { try absolutePath("/srv/p\0bad") }
}
@Test func processOutputIsBounded() async throws {
    let result = try await ProcessRunner.run(executable: "/bin/sh", arguments: ["-c", "head -c 2097152 /dev/zero"])
    #expect(result.status == 0); #expect(result.output.utf8.count == 1_048_576); #expect(result.truncated)
}
@Test func terminalTicketResourceLimit() async throws {
    let registry = TerminalRegistry()
    for _ in 0..<64 { _ = try await registry.issue(TerminalLaunch(host: "a"), owner: "admin") }
    await #expect(throws: (any Error).self) { _ = try await registry.issue(TerminalLaunch(host: "a"), owner: "admin") }
}

@Test func cancelledCommandsDoNotLeaveSSHProcessesRunning() async throws {
    let task = Task { try await ProcessRunner.run(executable: "/bin/sleep", arguments: ["30"]) }
    try await Task.sleep(for: .milliseconds(50)); task.cancel()
    await #expect(throws: CancellationError.self) { _ = try await task.value }
}
@Test func inheritedOutputPipeDoesNotHangACompletedCommand() async throws {
    let started = Date()
    let result = try await ProcessRunner.run(executable: "/bin/sh", arguments: ["-c", "sleep 1 & printf complete"])
    #expect(result.output == "complete"); #expect(Date().timeIntervalSince(started) < 0.8)
}


#if os(Linux)
import Glibc
#else
import Darwin
#endif
import CPTY

@Test func nativePTYUnblocksSignalsAndResizes() throws {
    var blocked = sigset_t(); sigemptyset(&blocked); sigaddset(&blocked, SIGWINCH)
    var previous = sigset_t(); _ = pthread_sigmask(SIG_BLOCK, &blocked, &previous)
    defer { _ = pthread_sigmask(SIG_SETMASK, &previous, nil) }
    let args = ["/bin/sh", "-c", "trap 'stty size; exit' WINCH; printf READY; while :; do sleep 0.05; done"]
    let pointers = args.map { strdup($0) }; defer { pointers.forEach { free($0) } }
    var argv = pointers + [nil]; var fd: Int32 = -1
    let pid = argv.withUnsafeMutableBufferPointer { ae_spawn_pty("/bin/sh", $0.baseAddress, &fd) }
    #expect(pid > 0); guard pid > 0 else { return }
    defer { _ = kill(-pid, SIGTERM); _ = close(fd); var status: Int32 = 0; _ = waitpid(pid, &status, 0) }
    func receive() -> String {
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        guard poll(&descriptor, 1, 2000) > 0 else { return "" }
        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = read(fd, &bytes, bytes.count)
        return count > 0 ? String(decoding: bytes.prefix(count), as: UTF8.self) : ""
    }
    #expect(receive().contains("READY"))
    #expect(ae_resize_pty(fd, 101, 31) == 0); _ = kill(pid, SIGWINCH)
    #expect(receive().contains("31 101"))
}

@Test func deploymentInitializationSeedsLocalhostAndPreservesState() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let store = try ConfigStore(home: home)
    try await store.initializeIfNeeded()
    let initial = try await store.read()
    #expect(initial.config.hosts.first?.isLocal == true)
    try await store.initializeIfNeeded()
    #expect(try await store.read().revision == initial.revision)
    await #expect(throws: (any Error).self) { try await store.initialize() }
    var config = initial.config
    config.hosts = [Host(name: "custom", destination: "approved-host")]
    try await store.write(config, expected: initial.revision)
    let credential = home.appendingPathComponent("state/admin.json")
    try Data("existing credential".utf8).write(to: credential)
    try await store.initializeIfNeeded()
    let prepared = try await store.read()
    #expect(prepared.config.hosts.map(\.id) == ["custom", "localhost"])
    #expect(try Data(contentsOf: credential) == Data("existing credential".utf8))
    try await store.initializeIfNeeded()
    #expect(try await store.read().revision == prepared.revision)
    let path = home.appendingPathComponent("config/aelab.json")
    let invalid = Data("invalid config".utf8); try invalid.write(to: path)
    await #expect(throws: (any Error).self) { try await store.initializeIfNeeded() }
    #expect(try Data(contentsOf: path) == invalid)
}

@Test func nativePTYStartsWithNormalOutputProcessing() throws {
    let args = ["/bin/sh", "-c", "printf 'NORMAL_ONE\\nNORMAL_TWO\\n'"]
    let pointers = args.map { strdup($0) }; defer { pointers.forEach { free($0) } }
    var argv = pointers + [nil]; var fd: Int32 = -1
    let pid = argv.withUnsafeMutableBufferPointer { ae_spawn_pty("/bin/sh", $0.baseAddress, &fd) }
    #expect(pid > 0); guard pid > 0 else { return }
    defer { _ = close(fd); var status: Int32 = 0; _ = waitpid(pid, &status, 0) }
    var output = Data()
    var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
    while poll(&descriptor, 1, 2000) > 0 {
        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = read(fd, &bytes, bytes.count); if count <= 0 { break }
        output.append(contentsOf: bytes.prefix(count))
    }
    #expect(String(decoding: output, as: UTF8.self).contains("NORMAL_ONE\r\nNORMAL_TWO\r\n"))
}

@Test func hostTintConfigurationRoundTripAndValidation() throws {
    var config = Configuration()
    var host = Host(name: "h", destination: "approved-host")
    host.tint = "#c75b39"; config.hosts = [host]
    try config.validate()
    let copy = try JSONDecoder().decode(Configuration.self, from: jsonEncoder.encode(config))
    #expect(copy.hosts.first?.tint == "#c75b39")
    config.hosts[0].tint = "invalid-color"
    #expect(throws: (any Error).self) { try config.validate() }
}

@Test func explicitLocalTransportAndSafeArguments() async throws {
    let local = Host(name: "native", transport: .local)
    let remote = Host(name: "localhost", destination: "localhost")
    let execution = HostExecution()
    #expect(try execution.terminalCommand(remote, script: "true").executable == "/usr/bin/ssh")
    #expect(try execution.terminalCommand(local, script: "true").executable == "/bin/sh")
    let identity = try await execution.run(local, args: ["/usr/bin/id", "-u"])
    #expect(identity.status == 0); #expect(identity.output.trimmingCharacters(in: .whitespacesAndNewlines) == String(getuid()))
    let literal = "a'; $(touch /tmp/aelab-should-not-exist)\n`id`"
    #expect(try await execution.run(local, args: ["/usr/bin/printf", "%s", literal]).output == literal)
    let failure = try await execution.execute(local, script: "exit 255")
    #expect(failure.status == 255); #expect(failure.category == "command-failed")
    let timeout = try await execution.run(local, args: ["/bin/sleep", "2"], timeout: 0.05)
    #expect(timeout.status == 124)
    var config = Configuration(); config.hosts = [local, remote]; try config.validate()
    config.hosts[0].destination = "remote-host"
    #expect(throws: (any Error).self) { try config.validate() }
}

@Test func localPTYUsesRealTerminalAndCleansUp() async throws {
    let terminal = try TerminalPTY(host: Host(name: "local", transport: .local), script: "test -t 0 && test -t 1 && printf 'LOCAL_TTY_OK\\n'; /usr/bin/id -u", execution: HostExecution())
    defer { terminal.closeSession() }
    try terminal.resize(cols: 90, rows: 30)
    var output = Data()
    while let bytes = await terminal.readChunk() { output.append(bytes) }
    let text = String(decoding: output, as: UTF8.self)
    #expect(text.contains("LOCAL_TTY_OK\r\n")); #expect(text.contains(String(getuid())))
    terminal.closeSession()
    #expect(await terminal.readChunk() == nil)
}

@Test func rawConfigurationEditorPreservesTextRejectsConflictsAndInvalidData() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let first = try ConfigStore(home: home); let second = try ConfigStore(home: home)
    try await first.initialize()
    let loaded = try await first.readDocument()
    let edited = ConfigDocument(content: loaded.content + "\n  ", revision: loaded.revision)
    try await first.writeDocument(edited)
    #expect(try await second.readDocument().content == edited.content)
    await #expect(throws: (any Error).self) { try await second.writeDocument(loaded) }
    let current = try await first.readDocument()
    await #expect(throws: (any Error).self) { try await first.writeDocument(ConfigDocument(content: "{invalid", revision: current.revision)) }
    await #expect(throws: (any Error).self) { try await first.writeDocument(ConfigDocument(content: "{}", revision: current.revision)) }
    #expect(try await first.readDocument().revision == current.revision)
    let permissions = try FileManager.default.attributesOfItem(atPath: home.appendingPathComponent("config/aelab.json").path)[.posixPermissions] as? NSNumber
    #expect(permissions?.intValue == 0o600)
    // The exact-text editor can recover a malformed external edit without accepting a stale revision.
    try Data("malformed".utf8).write(to: home.appendingPathComponent("config/aelab.json"))
    let broken = try await first.readDocument()
    try await first.writeDocument(ConfigDocument(content: current.content, revision: broken.revision))
    #expect(try await first.read().config.hosts.first?.isLocal == true)
}

@Test func nestedHostConfigurationScopesIdentifiersAndReferences() throws {
    let text = #"{"version":1,"hosts":[{"name":"a","transport":"local","projects":[{"name":"app","dir":"/tmp"}],"services":[],"tools":["shell"],"plugins":[]},{"name":"b","transport":"local","projects":[],"services":[],"tools":["shell-b"],"plugins":[]}],"tools":[{"name":"shell","executable":"/bin/sh","arguments":[]},{"name":"shell-b","executable":"/bin/bash","arguments":[]}],"plugins":[],"paths":[]}"#
    var config = try ConfigStore.validateDocument(text)
    #expect(try TerminalLaunch(host: "b", tool: "shell-b").resolve(config).1.contains("/bin/bash"))
    #expect(throws: (any Error).self) { _ = try TerminalLaunch(host: "b", project: "app").resolve(config) }
    config.hosts[0].tools = []
    try config.validate()
    #expect(throws: (any Error).self) { _ = try ConfigStore.validateDocument(text.replacingOccurrences(of: "\"version\":1", with: "\"version\":9")) }
}
@Test func sectionStatePersistsOutsideConfigurationAndRejectsArbitraryKeys() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let store = try ConfigStore(home: home); try await store.initialize()
    let original = try await store.readDocument()
    try await store.saveSections(host: "localhost", sections: ["shells": false, "projects": true, "tools": false])
    let reopened = try ConfigStore(home: home)
    #expect(try await reopened.sectionState()["localhost"]?["shells"] == false)
    #expect(try await store.readDocument().revision == original.revision)
    try Data(#"{"localhost":{"obsolete-section":true,"shells":false}}"#.utf8).write(to: home.appendingPathComponent("state/sections.json"))
    #expect(try await reopened.sectionState()["localhost"] == ["shells": false])
    await #expect(throws: (any Error).self) { try await store.saveSections(host: "../../outside", sections: [:]) }
    await #expect(throws: (any Error).self) { try await store.saveSections(host: "localhost", sections: ["arbitrary": true]) }
    await #expect(throws: (any Error).self) { _ = try await Operations(store: store).renameSession(host: "localhost", session: "safe", name: "bad:target") }
    let permissions = try FileManager.default.attributesOfItem(atPath: home.appendingPathComponent("state/sections.json").path)[.posixPermissions] as? Int
    #expect(permissions == 0o600)
    await #expect(throws: (any Error).self) { _ = try await Operations(store: store).killSession(host: "localhost", session: "valid:other") }
    await #expect(throws: (any Error).self) { _ = try await Operations(store: store).killSession(host: "unknown", session: "safe") }
}

@Test func minimalHostsDefaultToEmptyCollectionsAndRetiredSchemasFailClearly() throws {
    let config = try ConfigStore.validateDocument(#"{"version":1,"hosts":[{"name":"local","transport":"local"}]}"#)
    #expect(throws: (any Error).self) { _ = try ConfigStore.validateDocument(#"{"version":1,"hosts":[],"projects":[{"id":"do-not-drop"}]}"#) }
    let host = try config.host("local")
    #expect(host.projects.isEmpty && host.services.isEmpty && host.tools.isEmpty && host.plugins.isEmpty)
    do {
        _ = try ConfigStore.validateDocument(#"{"version":9,"hosts":[{"name":"local","transport":"local"}]}"#)
        Issue.record("Unsupported version was accepted")
    } catch { #expect(String(describing: error).contains("expected 1")) }
    #expect(throws: (any Error).self) { _ = try ConfigStore.validateDocument(#"{"version":1,"hosts":[{"name":"local","transport":"local","projects":"invalid"}]}"#) }
}

@Test func ttyButtonsDefaultValidateAndPersist() throws {
    let minimal = #"{"version":1,"hosts":[]}"#
    let defaults = try ConfigStore.validateDocument(minimal)
    #expect(defaults.ttyButtons.isEmpty)
    let text = #"{"version":1,"hosts":[],"ttyButtons":[{"key":"ctrl-c","label":"Stop"}]}"#
    let custom = try ConfigStore.validateDocument(text)
    #expect(custom.ttyButtons.count == 1 && custom.ttyButtons[0].label == "Stop")
    #expect(try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(custom)).ttyButtons[0].key == "ctrl-c")
    #expect(throws: (any Error).self) { _ = try ConfigStore.validateDocument(text.replacingOccurrences(of: "ctrl-c", with: "exec")) }
    #expect(throws: (any Error).self) { _ = try ConfigStore.validateDocument(text.replacingOccurrences(of: "Stop", with: "")) }
    #expect(try ConfigStore.validateDocument(#"{"version":1,"hosts":[],"ttyButtons":[]}"#).ttyButtons.isEmpty)
}

@Test func namesAreTheOnlyPersistedIdentityAndCollisionsFail() throws {
    for (name, expected) in [(".aelab", ".aelab"), ("aelab", "aelab"), ("com.example.agent", "com.example.agent"), ("Dév Server", "dev-server"), ("DEV---Server", "dev-server"), ("ＡＢＣ 123", "abc-123"), ("✨", "")] {
        #expect(nameID(name) == expected)
    }
    var config = try ConfigStore.validateDocument(#"{"version":1,"hosts":[{"name":"Dev host","transport":"local","projects":[{"name":"My project","dir":"/tmp"}],"services":[{"name":"Web service","provider":"docker","target":"web","project":"my-project","tool":"shared-tool"}],"tools":["shared-tool"],"plugins":["shared-plugin"]}],"tools":[{"name":"Shared tool","executable":"sh","arguments":[]}],"plugins":[{"name":"Shared plugin","executable":"sh","arguments":[]}]}"#)
    #expect(config.hosts[0].id == "dev-host")
    #expect(config.hosts[0].projects[0].id == "my-project")
    #expect(config.hosts[0].services[0].id == "web-service")
    let data = try configurationData(config)
    #expect(!String(decoding: data, as: UTF8.self).contains("\"id\""))
    let roundTrip = try ConfigStore.validateDocument(String(decoding: data, as: UTF8.self))
    #expect(roundTrip.plugins[0].id == "shared-plugin")
    config.hosts.append(Host(name: "Dèv---host", transport: .local))
    #expect(throws: (any Error).self) { try config.validate() }
    config.hosts.removeLast()
    var tool = config.tools[0]; tool.name = "SHARED---TOOL"; config.tools.append(tool)
    #expect(throws: (any Error).self) { try config.validate() }
    config.tools.removeLast()
    config.hosts[0].projects[0].name = "Renamed project"
    #expect(config.hosts[0].projects[0].id == "renamed-project")
    try config.validate()
    config.hosts[0].name = String(repeating: "a", count: 65)
    #expect(throws: (any Error).self) { try config.validate() }
}

@Test func hostRenameMovesSectionStateWithoutCrossingConnections() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let store = try ConfigStore(home: home); try await store.initialize()
    try await store.saveSections(host: "localhost", sections: ["shells": false])
    let original = try await store.read(); var updated = original.config
    updated.hosts[0].name = "Local machine"; updated.hosts[0].tint = "#112233"
    #expect(original.config.renamedHosts(to: updated) == ["localhost": "local-machine"])
    try await store.write(updated, expected: original.revision)
    #expect(try await store.sectionState()["local-machine"] == ["shells": false])
    #expect(try await store.sectionState()["localhost"] == nil)
    try await store.initializeIfNeeded()
    #expect(try await store.read().config.hosts.count == 1) // A renamed local host is still the default machine.
    let local = try await store.read().config.host("local-machine")
    let execution = HostExecution()
    #expect(try execution.terminalCommand(local, script: "pwd").executable == "/bin/sh")
    #expect(try await execution.run(local, args: ["/usr/bin/printf", "%s", "LOCAL_WITH_ANY_NAME"]).output == "LOCAL_WITH_ANY_NAME")
    updated.hosts[0].name = "Another machine"; updated.hosts[0].transport = .ssh; updated.hosts[0].destination = "remote"
    #expect(original.config.renamedHosts(to: updated).isEmpty)
    var ambiguous = original.config; ambiguous.hosts.append(Host(name: "Also local", transport: .local))
    #expect(ambiguous.renamedHosts(to: Configuration()).isEmpty)
    var twoAdded = original.config; twoAdded.hosts = [Host(name: "One", transport: .local), Host(name: "Two", transport: .local)]
    #expect(original.config.renamedHosts(to: twoAdded).isEmpty)
}

@Test func terminalOwnerSurvivesBrowserLoginsButChangesWithCredentials() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    _ = try ConfigStore(home: home)
    let auth = Authentication(home: home), anotherLogin = Authentication(home: home)
    try await auth.bootstrap("a long test password")
    let first = try await auth.login("a long test password")
    await auth.logout(first.token)
    #expect(await auth.isCurrentOwner(first.owner))
    await #expect(throws: (any Error).self) { _ = try await auth.authorize(token: first.token) }
    let second = try await anotherLogin.login("a long test password")
    #expect(first.owner == second.owner); #expect(first.token != second.token)
    try await auth.reset("a different test password")
    #expect(!(await auth.isCurrentOwner(first.owner)))
    await #expect(throws: (any Error).self) { _ = try await anotherLogin.authorize(token: second.token) }
}

@Test func passwordConfirmationKeepsTheExistingSessionValid() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    _ = try ConfigStore(home: home); let auth = Authentication(home: home)
    try await auth.bootstrap("a long test password")
    let before = try await auth.login("a long test password")
    try await Task.sleep(for: .milliseconds(1050))
    try await auth.verifySessionPassword(token: before.token, csrf: before.csrf, password: "a long test password")
    let after = try await auth.authorize(token: before.token)
    #expect(after.token == before.token); #expect(after.csrf == before.csrf); #expect(after.expires == before.expires)
    try await Task.sleep(for: .milliseconds(1050))
    await #expect(throws: (any Error).self) { try await auth.verifySessionPassword(token: before.token, csrf: before.csrf, password: "wrong password") }
    #expect(try await auth.authorize(token: before.token).token == before.token)
    await #expect(throws: (any Error).self) { try await auth.verifySessionPassword(token: before.token, csrf: "wrong", password: "a long test password") }
}

@Test func passwordChangeRequiresCurrentPasswordAndRevokesOldCredentials() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    _ = try ConfigStore(home: home); let auth = Authentication(home: home)
    try await auth.bootstrap("a long test password")
    let session = try await auth.login("a long test password")
    try await Task.sleep(for: .milliseconds(1050))
    await #expect(throws: (any Error).self) { try await auth.changePassword(current: "wrong password", replacement: "a different password") }
    #expect(try await auth.authorize(token: session.token).token == session.token)
    try await Task.sleep(for: .milliseconds(2100))
    await #expect(throws: (any Error).self) { try await auth.changePassword(current: "a long test password", replacement: "short") }
    #expect(try await auth.authorize(token: session.token).token == session.token)
    try await Task.sleep(for: .milliseconds(1050))
    try await auth.changePassword(current: "a long test password", replacement: "a different password")
    await #expect(throws: (any Error).self) { _ = try await auth.authorize(token: session.token) }
    #expect(!(await auth.isCurrentOwner(session.owner)))
    try await Task.sleep(for: .milliseconds(1050))
    let fresh = try await auth.login("a different password")
    #expect(fresh.owner != session.owner)
}

@Test func dottedProjectNamesHaveDistinctValidURLs() throws {
    let config = try ConfigStore.validateDocument(#"{"version":1,"hosts":[{"name":"local","transport":"local","projects":[{"name":"aelab","dir":"/tmp/aelab"},{"name":".aelab","dir":"/tmp/.aelab"}]}]}"#)
    #expect(config.hosts[0].projects.map(\.id) == ["aelab", ".aelab"])
    #expect(validID(".aelab"))
    #expect(!validID(".")); #expect(!validID("..")); #expect(!validID("../aelab"))
    let (_, _, session) = try TerminalLaunch(host: "local", project: ".aelab", persistent: true).resolve(config)
    #expect(session?.hasPrefix("aelab-_aelab-") == true)
}

@Test func configurationPathsRemainReadableWithoutChangingStringValues() throws {
    let original = #"{"version":1,"paths":["/usr/local/bin"],"tools":[{"name":"Example","executable":"/usr/bin/printf","arguments":["/srv/my project","quote \"value\"","back\\slash"]}],"hosts":[{"name":"local","transport":"local","projects":[{"name":"Example","dir":"/srv/my project"}]}]}"#
    let config = try ConfigStore.validateDocument(original)
    let data = try configurationData(config)
    let text = String(decoding: data, as: UTF8.self)
    #expect(!text.contains(#"\/"#))
    #expect(text.contains("/usr/local/bin"))
    #expect(text.contains("/srv/my project"))
    let restored = try JSONDecoder().decode(Configuration.self, from: data)
    #expect(restored.paths == config.paths)
    #expect(restored.tools[0].arguments == config.tools[0].arguments)
    #expect(restored.hosts[0].projects[0].directory == config.hosts[0].projects[0].directory)
}

@Test func alternateToolArgumentsReplaceNormalArgumentsAndComposeWithYolo() throws {
    let config = try ConfigStore.validateDocument(#"{"version":1,"hosts":[{"name":"local","transport":"local","tools":["codex","plain"]}],"tools":[{"name":"codex","executable":"codex","arguments":["new"],"altArguments":["resume","space ' quote"],"yoloArguments":["--yolo"]},{"name":"plain","executable":"echo","arguments":[]}]}"#)
    let (_, normal, _) = try TerminalLaunch(host: "local", tool: "codex").resolve(config)
    #expect(normal.contains(command(["codex", "new"])))
    let (_, alternate, _) = try TerminalLaunch(host: "local", tool: "codex", yolo: true, alt: true).resolve(config)
    #expect(alternate.contains(command(["codex", "resume", "space ' quote", "--yolo"])))
    #expect(!alternate.contains("'new'"))
    #expect(throws: (any Error).self) { _ = try TerminalLaunch(host: "local", tool: "plain", alt: true).resolve(config) }
    #expect(throws: (any Error).self) { _ = try TerminalLaunch(host: "local", alt: true).resolve(config) }
}
