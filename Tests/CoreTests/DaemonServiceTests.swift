import Foundation
import Testing
@testable import Core

@Test func userServicesEscapeSettingsAndPreserveForeignDefinitions() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let fm = FileManager.default; defer { try? fm.removeItem(at: root) }
    for kind in [UserService.Kind.server, .daemon] {
        for macos in [false, true] {
            let home = root.appendingPathComponent("a & b % $ \"quoted\" \\home")
            let executable = root.appendingPathComponent("a & b % $ \"quoted\" \\bin")
            let arguments = kind == .daemon ? ["--home", home.path] : []
            let service = UserService(kind: kind, executable: executable, arguments: arguments, environment: ["PATH": "/custom/bin:/usr/bin:/bin", "AELAB_HOME": home.path, "SSH_AUTH_SOCK": home.appendingPathComponent("agent").path], home: home)
            let path = try service.write(macos: macos, userHome: root, environment: [:])
            let data = try Data(contentsOf: path)
            #expect((try fm.attributesOfItem(atPath: path.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            if macos {
                let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                #expect(plist?["ProgramArguments"] as? [String] == [executable.path] + arguments)
                #expect((plist?["EnvironmentVariables"] as? [String: String])?["AELAB_HOME"] == home.path)
                #expect(plist?["WorkingDirectory"] as? String == home.path)
            } else {
                let text = String(decoding: data, as: UTF8.self)
                #expect(text.contains("%%")); #expect(text.contains("$$")); #expect(text.contains("\\\"quoted\\\"")); #expect(text.contains("\\\\bin"))
                #expect(text.contains("Type=exec")); #expect(text.contains("Environment=\"PATH=/custom/bin:/usr/bin:/bin\""))
            }
            _ = try service.write(macos: macos, userHome: root, environment: [:])
            #expect(try Data(contentsOf: path) == data)
            let changed = UserService(kind: kind, executable: executable, arguments: arguments, environment: ["PATH": "/updated/bin:/usr/bin"], home: home)
            _ = try changed.write(macos: macos, userHome: root, environment: [:])
            #expect(try Data(contentsOf: path) != data)
            try Data("unrelated service".utf8).write(to: path)
            #expect(throws: (any Error).self) { try service.write(macos: macos, userHome: root, environment: [:]) }
            #expect(try String(contentsOf: path, encoding: .utf8) == "unrelated service")
            try fm.removeItem(at: path)
            let other = root.appendingPathComponent("other"); try data.write(to: other)
            try fm.createSymbolicLink(at: path, withDestinationURL: other)
            #expect(throws: (any Error).self) { try service.write(macos: macos, userHome: root, environment: [:]) }
            #expect(try Data(contentsOf: other) == data)
            try fm.removeItem(at: path)
        }
    }
}

private actor ServiceRecorder {
    var commands: [[String]] = []
    let fail: String?
    init(fail: String? = nil) { self.fail = fail }
    func run(_ tool: String, _ arguments: [String]) -> CommandResult {
        commands.append([tool] + arguments)
        return CommandResult(status: arguments.contains(fail ?? "unmatchable") ? 1 : 0, output: "", error: "fixture error", truncated: false)
    }
}
@Test func userServicesReloadAndRestartThroughTheNativeManager() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    for kind in [UserService.Kind.server, .daemon] {
        let service = UserService(kind: kind, executable: root.appendingPathComponent("aelab"), environment: [:], home: root.appendingPathComponent(kind.rawValue))
        for macos in [false, true] {
            let recorder = ServiceRecorder()
            try await service.start(macos: macos, userHome: root, managerEnvironment: [:], run: { await recorder.run($0, $1) })
            let commands = await recorder.commands
            if macos {
                #expect(commands.map { $0[1] } == ["print", "bootout", "enable", "bootstrap"])
                #expect(commands.last?.last == service.file(macos: true, userHome: root).path)
            } else { #expect(commands == [["systemctl", "--user", "daemon-reload"], ["systemctl", "--user", "enable", service.unit], ["systemctl", "--user", "restart", service.unit]]) }
        }
        let cold = ServiceRecorder(fail: "print")
        try await service.start(macos: true, userHome: root, managerEnvironment: [:], run: { await cold.run($0, $1) })
        #expect(await cold.commands.map { $0[1] } == ["print", "enable", "bootstrap"])
        let failure = ServiceRecorder(fail: "restart")
        await #expect(throws: (any Error).self) { try await service.start(macos: false, userHome: root, managerEnvironment: [:], run: { await failure.run($0, $1) }) }
        #expect(FileManager.default.fileExists(atPath: service.file(macos: false, userHome: root, environment: [:]).path))
    }
}

@Test func userServiceRejectsControlCharactersAndHonorsXDGConfig() throws {
    let service = UserService(kind: .server, executable: URL(fileURLWithPath: "/tmp/server"), environment: ["PATH": "/bin\ninjected"], home: URL(fileURLWithPath: "/tmp/home"))
    #expect(throws: (any Error).self) { try service.definition(macos: false) }
    #expect(service.file(macos: false, environment: ["XDG_CONFIG_HOME": "/tmp/config"]).path == "/tmp/config/systemd/user/aelab-server.service")
    #expect(service.file(macos: false, userHome: URL(fileURLWithPath: "/tmp/user"), environment: ["XDG_CONFIG_HOME": "relative"]).path == "/tmp/user/.config/systemd/user/aelab-server.service")
}
