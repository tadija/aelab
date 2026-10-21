import Foundation
import Testing
@testable import Core

private func nativeService(_ provider: String, target: String, extra: [String: Any] = [:]) throws -> Service {
    var value: [String: Any] = ["name":"Job", "provider":provider, "target":target]
    value.merge(extra) { _, new in new }
    return try JSONDecoder().decode(Service.self, from: JSONSerialization.data(withJSONObject: value))
}
@Test func launchdDiscoveryUsesDocumentedColumnsAndFullDomainTargets() {
    let list = LaunchdDiscovery.parse("@aelab-domain:gui/502\nPID\tStatus\tLabel\n123\t0\tcom.example.running\n-\t0\tcom.example.idle\n-\t-15\tcom.example.failed\ninvalid line\n")
    #expect(list.map(\.state) == ["running", "stopped", "failed"])
    #expect(list.first?.target == "gui/502/com.example.running")
    #expect(list.allSatisfy { $0.provider == .launchd })
    #expect(LaunchdDiscovery.parse("PID Status Label\n123 0 com.example").isEmpty)
    #expect(LaunchdDiscovery.parse("@aelab-domain:gui\n123 0 com.example").isEmpty)
}
@Test func launchdOperationsCannotTargetWholeDomainsOrOtherCommands() throws {
    for target in ["system", "gui/502", "gui/502/", "gui/self/job", "system/job;kill", "system/job/child", "user/502/../job"] {
        #expect(throws: (any Error).self) { try ServiceCommands.validateLaunchdTarget(target) }
    }
    let job = try nativeService("launchd", target: "gui/502/com.example.job")
    #expect(try ServiceCommands.arguments(job, operation: "status") == ["/bin/launchctl", "print", job.target])
    #expect(try ServiceCommands.arguments(job, operation: "restart") == ["/bin/launchctl", "kickstart", "-k", job.target])
    #expect(throws: (any Error).self) { _ = try ServiceCommands.script(job, operation: "stop") }
    #expect(throws: (any Error).self) { _ = try ServiceCommands.arguments(job, operation: "disable") }
}
@Test func launchdReloadPlansAndLogsPreservePrivilegeBoundaries() throws {
    var job = try nativeService("launchd", target: "system/com.example.job", extra: ["plist":"/Library/LaunchDaemons/job ' file.plist", "sudo":true])
    let start = try ServiceCommands.script(job, operation: "start")
    #expect(start.contains("'bootstrap' 'system' '/Library/LaunchDaemons/job '\\'' file.plist'"))
    #expect(start.contains("Plist Label does not match"))
    #expect(start.contains("'sudo' '-n' '/bin/launchctl' 'kickstart'"))
    #expect(try ServiceCommands.arguments(job, operation: "status").first == "/bin/launchctl")
    #expect(try !ServiceCommands.script(job, operation: "stop").contains("'disable'"))
    #expect(try ServiceCommands.arguments(job, operation: "logs").prefix(2) == ["/usr/bin/log", "show"])
    job.logFiles = ["/var/log/job ' output.log"]
    #expect(try ServiceCommands.arguments(job, operation: "logs") == ["/usr/bin/tail", "-n", "200", "/var/log/job ' output.log"])
}
@Test func dockerContextAppliesToEveryDockerAndComposeOperation() throws {
    for provider in ["docker", "compose"] {
        let job = try nativeService(provider, target: "app", extra: ["directory":"/srv/app"])
        for operation in ["status", "logs", "start", "stop", "restart"] {
            let arguments = try ServiceCommands.arguments(job, operation: operation, dockerContext: "desktop-linux")
            #expect(arguments.prefix(3) == ["docker", "--context", "desktop-linux"])
            #expect(!arguments.contains("use")); #expect(!arguments.contains("up")); #expect(!arguments.contains("down"))
        }
    }
    #expect(try ServiceCommands.dockerArguments(["ps"], context: nil) == ["docker", "ps"])
    for invalid in ["", "--host", "bad\ncontext", "bad\0context"] { #expect(throws: (any Error).self) { try ServiceCommands.validateDockerContext(invalid) } }
}
@Test func launchdAndDockerSettingsPersistAndValidate() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try ConfigStore(home: root); try await store.initialize()
    var snapshot = try await store.read()
    snapshot.config.hosts[0].dockerContext = "colima"
    snapshot.config.hosts[0].services = [try nativeService("launchd", target: "user/502/com.example.job", extra: ["plist":"~/Library/LaunchAgents/job.plist", "logFiles":["~/Library/Logs/job.log"]])]
    try await store.write(snapshot.config, expected: snapshot.revision)
    let saved = try await store.read()
    #expect(saved.config.hosts[0].dockerContext == "colima")
    #expect(saved.config.hosts[0].services[0].plist == "~/Library/LaunchAgents/job.plist")
    snapshot.config.hosts[0].services[0].userUnit = true
    #expect(throws: (any Error).self) { try snapshot.config.validate() }
}
#if os(macOS)
@Test func launchdLifecycleScriptReloadsOnlyItsApprovedFixtureJob() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let plist = root.appendingPathComponent("test ' job.plist")
    let label = "com.aelab.fixture"
    try PropertyListSerialization.data(fromPropertyList: ["Label": label], format: .xml, options: 0).write(to: plist)
    let loaded = root.appendingPathComponent("loaded").path, log = root.appendingPathComponent("calls").path
    let fixture = root.appendingPathComponent("launchctl-fixture")
    let script = "#!/bin/sh\nset -eu\nprintf '%s\\n' \"$*\" >> " + quote(log) + "\ncase $1 in print) test -f " + quote(loaded) + ";; bootstrap) touch " + quote(loaded) + ";; kickstart) test -f " + quote(loaded) + ";; bootout) rm " + quote(loaded) + ";; *) exit 99;; esac\n"
    try Data(script.utf8).write(to: fixture); try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
    let job = try nativeService("launchd", target: "gui/502/" + label, extra: ["plist":plist.path])
    for operation in ["start", "stop", "restart"] {
        let plan = try ServiceCommands.script(job, operation: operation).replacingOccurrences(of: quote("/bin/launchctl"), with: quote(fixture.path))
        let result = try await ProcessRunner.run(executable: "/bin/sh", arguments: ["-c", plan], timeout: 5)
        #expect(result.status == 0)
    }
    let calls = try String(contentsOfFile: log, encoding: .utf8)
    #expect(calls.components(separatedBy: "bootstrap gui/502").count == 3)
    #expect(calls.contains("bootout gui/502/" + label))
    #expect(calls.contains("kickstart -k gui/502/" + label))
    try PropertyListSerialization.data(fromPropertyList: ["Label":"com.other.job"], format: .xml, options: 0).write(to: plist)
    let badPlan = try ServiceCommands.script(job, operation: "stop").replacingOccurrences(of: quote("/bin/launchctl"), with: quote(fixture.path))
    let result = try await ProcessRunner.run(executable: "/bin/sh", arguments: ["-c", badPlan], timeout: 5)
    #expect(result.status != 0)
    #expect(try String(contentsOfFile: log, encoding: .utf8) == calls)
}
#endif

@Test func systemdUserScopeAndSudoAreExplicitAndReadsNeverElevate() throws {
    var service = try nativeService("systemd", target: "example.service")
    service.userUnit = true
    #expect(try ServiceCommands.arguments(service, operation: "restart") == ["systemctl", "--user", "--no-ask-password", "restart", "--", "example.service"])
    #expect(try ServiceCommands.arguments(service, operation: "logs") == ["journalctl", "--user", "--no-pager", "-n", "200", "-u", "example.service"])
    service.userUnit = false; service.sudo = true
    for operation in ["start", "stop", "restart"] {
        #expect(try ServiceCommands.arguments(service, operation: operation) == ["sudo", "-n", "systemctl", "--no-ask-password", operation, "--", "example.service"])
    }
    for operation in ["status", "logs"] { #expect(try !ServiceCommands.arguments(service, operation: operation).contains("sudo")) }
}
