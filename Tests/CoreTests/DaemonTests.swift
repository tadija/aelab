import Foundation
import Testing
@testable import Core

@Test func daemonMessagesEnforceVersionsBoundsAndTerminalGeometry() throws {
    try DaemonMessage(operation: "execute", script: "true", timeout: 5).validate()
    var message = DaemonMessage(operation: "resize", cols: 80, rows: 24)
    message.version = 2; #expect(throws: (any Error).self) { try message.validate() }
    message.version = 1; message.cols = 501; #expect(throws: (any Error).self) { try message.validate() }
    #expect(throws: (any Error).self) { try DaemonMessage(operation: "execute", script: String(repeating: "x", count: 131073)).validate() }
    #expect(throws: (any Error).self) { try DaemonMessage(operation: "input", data: Data(repeating: 0, count: 65537)).validate() }
    #expect(throws: (any Error).self) { try DaemonMessage(operation: "execute", timeout: .nan).validate() }
    #expect(throws: (any Error).self) { try DaemonMessage(operation: "execute", timeout: 121).validate() }
}
@Test func daemonHostsAreExplicitRemoteAndNeedPairing() throws {
    var config = Configuration(); var host = Host(name: "Laptop", transport: .daemon)
    config.hosts = [host]; #expect(throws: (any Error).self) { try config.validate() }
    host.daemon = UUID().uuidString; config.hosts = [host]; try config.validate()
    #expect(!host.isLocal)
    #expect(throws: (any Error).self) { _ = try HostExecution().terminalCommand(host, script: "true") }
    host.destination = "-evil"; config.hosts = [host]; #expect(throws: (any Error).self) { try config.validate() }
    #expect(CommandResult(status: 255, output: "", error: "remote failure", truncated: false, transport: .daemon).category == "command-failed")
}
@Test func daemonPrivateFilesNeverOverwriteAndPairingRejectsTraversal() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    let file = home.appendingPathComponent("credentials")
    try DaemonSetup.privateWrite(Data("original".utf8), to: file)
    #expect(throws: (any Error).self) { try DaemonSetup.privateWrite(Data("new".utf8), to: file) }
    #expect(try String(contentsOf: file, encoding: .utf8) == "original")
    #expect((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    #expect(throws: (any Error).self) { _ = try DaemonPairing.file(home: home, id: "../../config") }
    let id = UUID().uuidString; let target = try DaemonPairing.file(home: home, id: id)
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: target, withDestinationURL: file)
    #expect(throws: (any Error).self) { _ = try DaemonPairing.load(home: home, id: id) }
    #expect(throws: (any Error).self) { try DaemonPairing(endpoint: "http://localhost:1984", certificate: "invalid", token: String(repeating: "a", count: 64)).validate() }
}

@Test func daemonHostRenamesNeverCrossPairedIdentities() {
    var old = Configuration(); var host = Host(name: "Laptop", transport: .daemon); host.daemon = UUID().uuidString
    old.hosts = [host]; var updated = old; updated.hosts[0].name = "Notebook"
    #expect(old.renamedHosts(to: updated) == ["laptop":"notebook"])
    updated.hosts[0].daemon = UUID().uuidString
    #expect(old.renamedHosts(to: updated).isEmpty)
}

@Test func daemonInitializationDefaultsTo1984AndPreservesExistingCredentials() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let home = root.appendingPathComponent("daemon")
    try await DaemonSetup.initialize(home: home, endpoint: "https://laptop.invalid", bind: "127.0.0.1")
    let pairing = try DaemonSetup.pairing(home: home)
    #expect(pairing.endpoint == "https://laptop.invalid:1984")
    #expect(try DaemonSetup.settings(home: home).port == 1984)
    await #expect(throws: (any Error).self) { try await DaemonSetup.initialize(home: home, endpoint: "https://other.invalid", bind: "127.0.0.1") }
    #expect(try DaemonSetup.pairing(home: home).token == pairing.token)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: home.appendingPathComponent("pairing.json").path)
    #expect(throws: (any Error).self) { _ = try DaemonSetup.pairing(home: home) }
    let invalid = root.appendingPathComponent("invalid")
    await #expect(throws: (any Error).self) { try await DaemonSetup.initialize(home: invalid, endpoint: "http://untrusted.invalid", bind: "127.0.0.1") }
    #expect(!FileManager.default.fileExists(atPath: invalid.path))
}
