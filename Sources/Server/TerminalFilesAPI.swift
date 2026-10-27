import Core
import Foundation
import Hummingbird

private actor FileAdmission {
    var active = 0
    func acquire() -> Bool { guard active < 4 else { return false }; active += 1; return true }
    func release() { active -= 1 }
}
struct TerminalFilesAPI: Sendable {
    let store: ConfigStore
    let auth: Authentication
    let origin: String
    let terminals: TerminalRegistry
    let execution: HostExecution
    private let admission = FileAdmission()
    init(store: ConfigStore, auth: Authentication, origin: String, terminals: TerminalRegistry, execution: HostExecution) {
        self.store = store; self.auth = auth; self.origin = origin; self.terminals = terminals; self.execution = execution
    }
    func register(on router: Router<BasicRequestContext>) {
        router.post("/api/hosts/{host}/terminals/{terminal}/files") { request, context in
            do {
                let session = try await authorize(request, auth: auth, origin: origin, mutation: true)
                let host = context.parameters.get("host")!, terminal = context.parameters.get("terminal")!
                _ = try await store.read().config.host(host)
                _ = try await terminals.fileHost(terminal, host: host, owner: session.owner)
                guard let name = request.uri.queryParameters["name"].map(String.init) else { throw AEError("A file name is required") }
                try TerminalFiles.validate(name: name, size: 0)
                if let length = request.headers[.contentLength] {
                    guard let size = Int(length), size >= 0 else { throw AEError("Invalid file length") }
                    guard size <= TerminalFiles.maximumSize else { throw APIError(status: .contentTooLarge, code: "file_too_large", message: "Files must be at most 20 MiB") }
                }
                guard await admission.acquire() else { throw APIError(status: .tooManyRequests, code: "upload_limit", message: "Too many file transfers; try again shortly") }
                do {
                    let response = try await upload(request, host: host, terminal: terminal, owner: session.owner, name: name)
                    await admission.release(); return response
                } catch { await admission.release(); throw error }
            } catch { return failure(error) }
        }
    }
    private func upload(_ request: Request, host: String, terminal: String, owner: String, name: String) async throws -> Response {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aelab-transfer-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("data")
        guard FileManager.default.createFile(atPath: path.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw AEError("Cannot prepare file transfer") }
        let output = try FileHandle(forWritingTo: path); defer { try? output.close() }
        var size = 0
        for try await chunk in request.body {
            try Task.checkCancellation()
            guard chunk.readableBytes <= TerminalFiles.maximumSize - size else { throw APIError(status: .contentTooLarge, code: "file_too_large", message: "Files must be at most 20 MiB") }
            try output.write(contentsOf: Data(chunk.readableBytesView)); size += chunk.readableBytes
        }
        try output.close()
        _ = try await authorize(request, auth: auth, origin: origin, mutation: true)
        let target = try await terminals.fileHost(terminal, host: host, owner: owner)
        let file = try await execution.upload(target, name: name, size: size, source: path)
        _ = try await authorize(request, auth: auth, origin: origin, mutation: true)
        try await store.audit("terminal-file", host: host, target: terminal, outcome: "saved")
        return try json(file)
    }
}
