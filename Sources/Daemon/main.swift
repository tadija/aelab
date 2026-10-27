import Core
import Foundation
import Hummingbird
import HummingbirdCore
import HummingbirdTLS
import HummingbirdWebSocket
#if os(Linux)
import Glibc
#else
import Darwin
#endif

@main struct Daemon {
    static func main() async {
        if Array(CommandLine.arguments.dropFirst()) == ["--version"] { print(AelabVersion.display); return }
        if Array(CommandLine.arguments.dropFirst()) == ["--build"] { print(AelabVersion.build); return }
        do { try await run() }
        catch { FileHandle.standardError.write(Data("aelab-daemon: \(error)\n".utf8)); exit(1) }
    }
    static func run() async throws {
        var args = Array(CommandLine.arguments.dropFirst()); var home = DaemonSetup.defaultHome
        if args.first == "--home" {
            guard args.count >= 2, !args[1].isEmpty, !args[1].hasPrefix("--") else { throw AEError("--home requires a path") }
            home = URL(fileURLWithPath: args[1]); args.removeFirst(2)
        }
        let action = args.isEmpty ? "" : args.removeFirst()
        if ["help", "--help", "-h"].contains(action) { print("aelab-daemon [--home PATH] [init --endpoint https://HOST:1984 [--bind ADDRESS] | pairing --output FILE]"); return }
        if action == "init" {
            var endpoint: String?; var bind = "0.0.0.0"
            while args.count >= 2 { let flag = args.removeFirst(); let value = args.removeFirst(); if flag == "--endpoint" { endpoint = value } else if flag == "--bind" { bind = value } else { throw AEError("Unknown init option") } }
            guard args.isEmpty, let endpoint else { throw AEError("An HTTPS endpoint is required") }
            try await DaemonSetup.initialize(home: home, endpoint: endpoint, bind: bind)
            print("Daemon initialized at \(home.path). Export pairing with: aelab-daemon --home \(home.path) pairing --output FILE")
            return
        }
        if action == "pairing" {
            let pairing = try DaemonSetup.pairing(home: home); let data = try JSONEncoder().encode(pairing)
            guard args.count == 2, args[0] == "--output" else { throw AEError("Use pairing --output FILE; transfer the private file securely") }
            try DaemonSetup.privateWrite(data, to: URL(fileURLWithPath: args[1])); return
        }
        guard action.isEmpty, args.isEmpty else { throw AEError("Unknown daemon command") }
        let lock = try DaemonRunLock(home: home)
        defer { withExtendedLifetime(lock) {} }
        let settings = try DaemonSetup.settings(home: home); let pairing = try DaemonSetup.pairing(home: home)
        var tls = TLSConfiguration.makeServerConfiguration(certificateChain: try NIOSSLCertificate.fromPEMFile(home.appendingPathComponent("certificate.pem").path).map { .certificate($0) }, privateKey: .privateKey(try NIOSSLPrivateKey(file: home.appendingPathComponent("key.pem").path, format: .pem)))
        tls.minimumTLSVersion = .tlsv12
        let router = Router(); let sockets = Router(context: BasicWebSocketRequestContext.self); let admission = DaemonAdmission()
        sockets.ws("/connect") { request, _ in
            // WSClient emits a wss:// Origin; browser origins are HTTP(S) and remain refused.
            let nativeOrigin = "wss://" + (URL(string: pairing.endpoint)?.host ?? "")
            guard request.headers[.origin] == nil || request.headers[.origin] == nativeOrigin,
                  secureToken(request.headers[.authorization], pairing.token), await admission.acquire() else { return .dontUpgrade }
            return .upgrade()
        } onUpgrade: { inbound, outbound, _ in
            let session = DaemonSession(outbound: outbound)
            do {
                for try await frame in inbound.messages(maxSize: 262144) {
                    guard case .text(let text) = frame else { throw AEError("Text messages required") }
                    let message = try JSONDecoder().decode(DaemonMessage.self, from: Data(text.utf8)); try message.validate()
                    try await session.handle(message)
                }
            } catch { /* Close the entire connection on malformed protocol input. */ }
            await session.close(); await admission.release()
        }
        let app = try Application(router: router, server: .tls(HTTPServerBuilder.http1WebSocketUpgrade(webSocketRouter: sockets, configuration: .init(ws: .init(maxFrameSize: 262144))), tlsConfiguration: tls), configuration: .init(address: .hostname(settings.bind, port: settings.port)))
        try await app.runService()
    }
    static func secureToken(_ header: String?, _ expected: String) -> Bool {
        let supplied = Array((header ?? "").utf8); let expected = Array(("Bearer " + expected).utf8)
        guard supplied.count == expected.count else { return false }
        return zip(supplied, expected).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
actor DaemonAdmission {
    var active = 0
    func acquire() -> Bool { guard active < 4 else { return false }; active += 1; return true }
    func release() { active = max(0, active - 1) }
}
actor DaemonSession {
    let outbound: WebSocketOutboundWriter
    let files = TerminalFileStore()
    var commands: [String: Task<Void, Never>] = [:]
    var terminals: [String: TerminalPTY] = [:]
    var readers: [String: Task<Void, Never>] = [:]
    init(outbound: WebSocketOutboundWriter) { self.outbound = outbound }
    func reply(_ message: DaemonMessage) async throws { try await outbound.write(.text(String(decoding: JSONEncoder().encode(message), as: UTF8.self))) }
    func handle(_ message: DaemonMessage) async throws {
        switch message.operation {
        case "file-begin", "file-write", "file-finish", "file-abort":
            do {
                switch message.operation {
                case "file-begin":
                    guard let name = message.name, let size = message.size else { throw AEError("Missing file metadata") }
                    let id = try await files.begin(name: name, size: size, id: message.id)
                    try await reply(DaemonMessage(id: message.id, operation: "result", upload: id))
                case "file-write":
                    guard let upload = message.upload, let offset = message.offset, let data = message.data else { throw AEError("Missing file chunk") }
                    try await files.append(upload, offset: offset, data: data)
                    try await reply(DaemonMessage(id: message.id, operation: "result"))
                case "file-finish":
                    guard let upload = message.upload else { throw AEError("Missing file transfer") }
                    let file = try await files.finish(upload)
                    try await reply(DaemonMessage(id: message.id, operation: "result", file: file))
                default:
                    guard let upload = message.upload else { throw AEError("Missing file transfer") }
                    await files.abort(upload)
                    try await reply(DaemonMessage(id: message.id, operation: "result"))
                }
            } catch { try await reply(DaemonMessage(id: message.id, operation: "result", error: String(describing: error))) }
        case "execute":
            guard commands.count < 8, commands[message.id] == nil, let script = message.script, let timeout = message.timeout else { try await reply(DaemonMessage(id: message.id, operation: "result", error: "Daemon command limit or invalid command")); return }
            commands[message.id] = Task {
                let response: DaemonMessage
                do {
                    let result = try await ProcessRunner.run(executable: "/bin/sh", arguments: ["-c", script], timeout: timeout)
                    response = DaemonMessage(id: message.id, operation: "result", result: result)
                } catch { response = DaemonMessage(id: message.id, operation: "result", error: "Command cancelled or failed") }
                self.completed(message.id)
                try? await self.reply(response)
            }
        case "cancel": commands.removeValue(forKey: message.id)?.cancel(); await files.abort(message.id)
        case "open":
            guard terminals.count < 16, terminals[message.id] == nil, let script = message.script else { try await reply(DaemonMessage(id: message.id, operation: "result", error: "Daemon terminal limit or invalid terminal")); return }
            let pty = try TerminalPTY(host: Host(name: "daemon", transport: .local), script: script, execution: HostExecution())
            terminals[message.id] = pty
            try await reply(DaemonMessage(id: message.id, operation: "opened"))
            readers[message.id] = Task {
                while let data = await pty.readChunk() { do { try await self.reply(DaemonMessage(id: message.id, operation: "output", data: data)) } catch { break } }
                pty.closeSession(); self.terminalEnded(message.id)
                try? await self.reply(DaemonMessage(id: message.id, operation: "ended"))
            }
        case "input": guard let pty = terminals[message.id], let data = message.data else { throw AEError("Unknown terminal") }; try pty.input(data)
        case "resize": guard let pty = terminals[message.id], let cols = message.cols, let rows = message.rows else { throw AEError("Unknown terminal") }; try pty.resize(cols: cols, rows: rows)
        case "close": terminals.removeValue(forKey: message.id)?.closeSession(); readers.removeValue(forKey: message.id)?.cancel()
        default: throw AEError("Unknown daemon operation")
        }
    }
    func completed(_ id: String) { commands.removeValue(forKey: id) }
    func terminalEnded(_ id: String) { terminals.removeValue(forKey: id); readers.removeValue(forKey: id) }
    func close() async {
        await files.close()
        for task in commands.values { task.cancel() }; commands.removeAll()
        for pty in terminals.values { pty.closeSession() }; terminals.removeAll()
        for task in readers.values { task.cancel() }; readers.removeAll()
    }
}
