import Foundation
import Testing
@testable import Core

@Test func uploadedFilesPreserveBytesNamesAndPrivatePermissions() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = TerminalFileStore(directory: root.appendingPathComponent("uploads"))
    let bytes = Data((0..<180000).map { UInt8($0 % 256) }), name = "an image ' $(no-command); 🐈.png"
    let id = try await store.begin(name: name, size: bytes.count)
    for offset in stride(from: 0, to: bytes.count, by: 65536) { try await store.append(id, offset: offset, data: bytes.subdata(in: offset..<min(offset + 65536, bytes.count))) }
    let file = try await store.finish(id)
    #expect(file.name == name); #expect(file.size == bytes.count)
    #expect(try Data(contentsOf: URL(fileURLWithPath: file.path)) == bytes)
    #expect((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    #expect((try FileManager.default.attributesOfItem(atPath: URL(fileURLWithPath: file.path).deletingLastPathComponent().path)[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    await store.close()
    #expect(FileManager.default.fileExists(atPath: file.path)) // Completed user files outlive connections.
    let second = try await store.begin(name: name, size: 0)
    #expect(try await store.finish(second).path != file.path)
}

@Test func terminalFileTransfersRejectInvalidMetadataAndCleanPartialWrites() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = TerminalFileStore(directory: root.appendingPathComponent("uploads"))
    for name in ["", ".", "..", "../outside", "path/file", "path\\file", "line\nbreak", "escape\u{1b}", String(repeating: "a", count: 256)] {
        #expect(throws: (any Error).self) { try TerminalFiles.validate(name: name, size: 0) }
    }
    #expect(throws: (any Error).self) { try TerminalFiles.validate(name: "big", size: TerminalFiles.maximumSize + 1) }
    let id = try await store.begin(name: "file", size: 2)
    await #expect(throws: (any Error).self) { try await store.append(id, offset: 1, data: Data([1])) }
    await #expect(throws: (any Error).self) { try await store.append(id, offset: 0, data: Data([1, 2, 3])) }
    try await store.append(id, offset: 0, data: Data([1]))
    await #expect(throws: (any Error).self) { try await store.finish(id) }
    await store.abort(id)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("uploads").path).isEmpty)
    var ids: [String] = []
    for _ in 0..<4 { ids.append(try await store.begin(name: "file", size: 0)) }
    await #expect(throws: (any Error).self) { try await store.begin(name: "file", size: 0) }
    await store.close()
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("uploads").path).isEmpty)
}

@Test func terminalFilesRefuseSymlinkStorageDirectories() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root.appendingPathComponent("outside"), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("uploads"), withDestinationURL: root.appendingPathComponent("outside"))
    let store = TerminalFileStore(directory: root.appendingPathComponent("uploads"))
    await #expect(throws: (any Error).self) { try await store.begin(name: "file", size: 0) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("outside").path).isEmpty)
}

@Test func sshFileTransferStreamsBinaryStdinAndQuotesTheDestination() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let bytes = Data((0..<200000).map { UInt8($0 % 256) }), source = root.appendingPathComponent("source")
    try bytes.write(to: source)
    let name = "my ' image $(touch BAD);.png", script = try TerminalFiles.sshScript(name: name, size: bytes.count)
    let result = try await ProcessRunner.run(executable: "/usr/bin/env", arguments: ["HOME=" + root.path, "/bin/sh", "-c", script], inputFile: source)
    #expect(result.status == 0, Comment(rawValue: result.error))
    #expect(URL(fileURLWithPath: result.output).lastPathComponent == name)
    #expect(try Data(contentsOf: URL(fileURLWithPath: result.output)) == bytes)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("BAD").path))
    let broken = try await ProcessRunner.run(executable: "/usr/bin/env", arguments: ["HOME=" + root.path, "/bin/sh", "-c", TerminalFiles.sshScript(name: "short", size: bytes.count + 1)], inputFile: source)
    #expect(broken.status != 0)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(".aelab/uploads").path).count == 1)
}

private actor FileTestProcess: TerminalProcess {
    func readChunk() async -> Data? { nil }
    func input(_ data: Data) async throws {}
    func resize(cols: Int, rows: Int) async throws {}
    func signal(_ signal: String) async throws {}
    func closeSession() async {}
}
@Test func uploadsRequireTheLiveTerminalOwnerAndUseItsOriginalExecutionHost() async throws {
    let registry = TerminalRegistry(), target = Host(name: "Remote", destination: "original", transport: .ssh)
    let terminal = LiveTerminal(pty: FileTestProcess(), owner: "owner", expires: .distantFuture, launch: TerminalLaunch(host: "remote"), cwd: "/tmp", fileHost: target)
    try await registry.register(terminal)
    #expect(try await registry.fileHost(terminal.id, host: "remote", owner: "owner").destination == "original")
    await #expect(throws: (any Error).self) { try await registry.fileHost(terminal.id, host: "other", owner: "owner") }
    await #expect(throws: (any Error).self) { try await registry.fileHost(terminal.id, host: "remote", owner: "intruder") }
    await terminal.close()
    await #expect(throws: (any Error).self) { try await registry.fileHost(terminal.id, host: "remote", owner: "owner") }
    await registry.closeAll()
}
