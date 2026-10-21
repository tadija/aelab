import Foundation
import Testing
@testable import Core

@Test func daemonUserServicesPreserveDefinitionsAndEscapeCustomHomes() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let fm = FileManager.default; defer { try? fm.removeItem(at: root) }
    let bin = root.appendingPathComponent("bin"); try fm.createDirectory(at: bin, withIntermediateDirectories: true)
    for name in ["systemctl", "launchctl"] {
        let file = bin.appendingPathComponent(name)
        try Data("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$HOME/commands\"\nif test \"$1\" = print; then exit 1; fi\n".utf8).write(to: file)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
    }
    for macos in [false, true] {
        let home = root.appendingPathComponent(macos ? "mac" : "linux")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        let daemon = home.appendingPathComponent("a & b % $ \"quoted\" \\daemon")
        let service = home.appendingPathComponent(macos ? "Library/LaunchAgents/dev.aelab.daemon.plist" : ".config/systemd/user/aelab-daemon.service")
        func run() async throws -> CommandResult {
            try await ProcessRunner.run(executable: "/usr/bin/env", arguments: ["HOME=" + home.path, "PATH=" + bin.path + ":/usr/bin:/bin", "/bin/sh", "-c", DaemonUserService.script(macos: macos), "service-test", daemon.path])
        }
        let first = try await run(); #expect(first.status == 0, Comment(rawValue: first.error))
        let data = try Data(contentsOf: service)
        #expect((try fm.attributesOfItem(atPath: service.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        if macos {
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            #expect(plist?["ProgramArguments"] as? [String] == [daemon.appendingPathComponent("aelab-daemon").path, "--home", daemon.path, "run"])
        } else {
            let text = String(decoding: data, as: UTF8.self)
            #expect(text.contains("%%")); #expect(text.contains("$$")); #expect(text.contains("\\\"quoted\\\"")); #expect(text.contains("\\\\daemon"))
        }
        #expect(try await run().status == 0)
        #expect(try Data(contentsOf: service) == data)
        try Data("unrelated service".utf8).write(to: service)
        #expect(try await run().status != 0)
        #expect(try String(contentsOf: service, encoding: .utf8) == "unrelated service")
        try fm.removeItem(at: service)
        let other = home.appendingPathComponent("other"); try data.write(to: other)
        try fm.createSymbolicLink(at: service, withDestinationURL: other)
        #expect(try await run().status != 0)
        #expect(try Data(contentsOf: other) == data)
    }
}
