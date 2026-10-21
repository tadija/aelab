import Foundation
import HummingbirdWSClient
import HummingbirdTLS
import HTTPTypes

/// Private pairing material, stored outside the editable/public host configuration.
public struct DaemonPairing: Codable, Sendable {
    public var endpoint: String
    public var certificate: String
    public var token: String
    public init(endpoint: String, certificate: String, token: String) { self.endpoint = endpoint; self.certificate = certificate; self.token = token }
    public static var defaultHome: URL { URL(fileURLWithPath: ProcessInfo.processInfo.environment["AELAB_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".aelab").path) }
    public func validate() throws {
        guard let url = URL(string: endpoint), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/", url.port == nil || (1...65535).contains(url.port!),
              token.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              certificate.utf8.count <= 16384 else { throw AEError("Invalid daemon pairing; require an HTTPS origin, certificate and 256-bit token") }
        _ = try NIOSSLCertificate(bytes: Array(certificate.utf8), format: .pem)
    }
    public static func file(home: URL, id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw AEError("Invalid daemon connection ID") }
        return home.appendingPathComponent("state/daemons/" + id.lowercased() + ".json")
    }
    public static func load(home: URL, id: String) throws -> DaemonPairing {
        let file = try file(home: home, id: id)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o777) & 0o077 == 0 else { throw AEError("Daemon pairing file must be a private regular file (0600)") }
        guard ((attributes[.size] as? NSNumber)?.intValue ?? 32769) <= 32768 else { throw AEError("Daemon pairing is too large") }
        let data = try Data(contentsOf: file); guard data.count <= 32768 else { throw AEError("Daemon pairing is too large") }
        let pairing = try JSONDecoder().decode(DaemonPairing.self, from: data); try pairing.validate(); return pairing
    }
    public func save(home: URL, id: String) throws {
        try validate(); let file = try Self.file(home: home, id: id)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard !FileManager.default.fileExists(atPath: file.path) else { throw AEError("Pairing already exists; use a new connection ID") }
        try DaemonSetup.privateWrite(JSONEncoder().encode(self), to: file)
    }
}

/// Versioned, bounded messages on a single authenticated TLS WebSocket per host.
public struct DaemonMessage: Codable, Sendable {
    public var version: Int = 1
    public var id: String
    public var operation: String
    public var script: String?
    public var timeout: Double?
    public var data: Data?
    public var cols: Int?
    public var rows: Int?
    public var result: CommandResult?
    public var error: String?
    public init(id: String = UUID().uuidString, operation: String, script: String? = nil, timeout: Double? = nil, data: Data? = nil, cols: Int? = nil, rows: Int? = nil, result: CommandResult? = nil, error: String? = nil) {
        self.id = id; self.operation = operation; self.script = script; self.timeout = timeout; self.data = data; self.cols = cols; self.rows = rows; self.result = result; self.error = error
    }
    public func validate() throws {
        guard version == 1, UUID(uuidString: id) != nil, (script?.utf8.count ?? 0) <= 131072,
              (data?.count ?? 0) <= 65536, timeout == nil || (timeout!.isFinite && timeout! > 0 && timeout! <= 120),
              cols == nil || (2...500).contains(cols!), rows == nil || (2...300).contains(rows!) else { throw AEError("Invalid daemon message") }
    }
}

public actor DaemonPool {
    let home: URL
    private let limiter = ConnectionLimiter()
    private var connections: [String: DaemonConnection] = [:]
    public init(home: URL) { self.home = home }
    public func connection(_ host: Host) throws -> DaemonConnection {
        guard let id = host.daemon else { throw AEError("Host has no daemon pairing") }
        if let connection = connections[id] { return connection }
        guard connections.count < 64 else { throw AEError("Daemon connection limit reached; restart after removing old pairings") }
        let connection = DaemonConnection(pairing: try DaemonPairing.load(home: home, id: id))
        connections[id] = connection; return connection
    }
    public func execute(_ host: Host, script: String, timeout: TimeInterval) async throws -> CommandResult {
        try await limiter.acquire()
        do {
            let response = try await connection(host).request(DaemonMessage(operation: "execute", script: script, timeout: timeout), timeout: timeout + 10)
            guard let result = response.result else { throw AEError("Invalid daemon command response") }
            await limiter.release()
            return CommandResult(status: result.status, output: result.output, error: result.error, truncated: result.truncated, transport: .daemon)
        } catch { await limiter.release(); throw error }
    }
    public func terminal(_ host: Host, script: String) async throws -> any TerminalProcess {
        let connection = try connection(host); let terminal = DaemonTerminal(connection: connection)
        try await connection.open(terminal, script: script); return terminal
    }
}

public actor DaemonConnection {
    let pairing: DaemonPairing
    private var task: Task<Void, Never>?
    private var writer: WebSocketOutboundWriter?
    private var failure: String?
    private var pending: [String: CheckedContinuation<DaemonMessage, any Error>] = [:]
    private var timers: [String: Task<Void, Never>] = [:]
    private var terminals: [String: DaemonTerminal] = [:]
    public init(pairing: DaemonPairing) { self.pairing = pairing }
    private func start() {
        guard task == nil else { return }; failure = nil
        let pairing = pairing
        task = Task {
            do {
                try pairing.validate()
                var tls = TLSConfiguration.makeClientConfiguration()
                tls.trustRoots = .certificates([try NIOSSLCertificate(bytes: Array(pairing.certificate.utf8), format: .pem)])
                tls.certificateVerification = .fullVerification
                var headers = HTTPFields(); headers[.authorization] = "Bearer " + pairing.token
                let url = "wss" + pairing.endpoint.dropFirst(5).trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/connect"
                try await WebSocketClient.connect(url: url, configuration: .init(maxFrameSize: 16 << 20, additionalHeaders: headers, autoPing: .enabled(timePeriod: .seconds(15))), tlsConfiguration: tls, logger: .init(label: "aelab.daemon-client")) { inbound, outbound, _ in
                    await self.ready(outbound)
                    for try await frame in inbound.messages(maxSize: 16 << 20) {
                        guard case .text(let text) = frame else { throw AEError("Invalid daemon response") }
                        let message = try JSONDecoder().decode(DaemonMessage.self, from: Data(text.utf8))
                        guard message.version == 1 else { throw AEError("Unsupported daemon protocol") }
                        await self.receive(message)
                    }
                }
                await self.disconnected("Daemon disconnected")
            } catch { await self.disconnected("Daemon connection failed: " + String(describing: error).replacingOccurrences(of: pairing.token, with: "[redacted]")) }
        }
    }
    private func ready(_ writer: WebSocketOutboundWriter) { self.writer = writer }
    private func disconnected(_ message: String) async {
        writer = nil; task = nil; failure = message
        let requests = pending.values; pending.removeAll(); for timer in timers.values { timer.cancel() }; timers.removeAll()
        for request in requests { request.resume(throwing: AEError(message)) }
        let sessions = terminals.values; terminals.removeAll(); for terminal in sessions { terminal.finish() }
    }
    private func receive(_ message: DaemonMessage) {
        if message.operation == "output", let data = message.data { terminals[message.id]?.receive(data); return }
        if message.operation == "ended" { terminals.removeValue(forKey: message.id)?.finish(); return }
        timers.removeValue(forKey: message.id)?.cancel()
        if let continuation = pending.removeValue(forKey: message.id) {
            if let error = message.error { continuation.resume(throwing: AEError(error)) }
            else { continuation.resume(returning: message) }
        }
    }
    public func send(_ message: DaemonMessage) async throws {
        try message.validate(); guard let writer else { throw AEError("Daemon is disconnected") }
        let data = try JSONEncoder().encode(message)
        guard data.count <= 262144 else { throw AEError("Daemon request exceeds 256 KiB") }
        try await writer.write(.text(String(decoding: data, as: UTF8.self)))
    }
    public func request(_ message: DaemonMessage, timeout: Double = 15) async throws -> DaemonMessage {
        try message.validate(); start()
        let deadline = Date().addingTimeInterval(10)
        while writer == nil {
            if let failure { throw AEError(failure) }
            guard Date() < deadline else { task?.cancel(); throw AEError("Daemon connection timed out") }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard pending.count < 32, pending[message.id] == nil else { throw AEError("Daemon command limit or duplicate request ID") }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                pending[message.id] = continuation
                timers[message.id] = Task {
                    do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                    await self.cancel(message.id, reason: "Daemon request timed out")
                }
                Task { do { try await self.sendRequest(message) } catch { await self.cancel(message.id, reason: "Daemon request failed") } }
            }
        } onCancel: { Task { await self.cancel(message.id, reason: "Daemon request cancelled") } }
    }
    private func sendRequest(_ message: DaemonMessage) async throws {
        guard pending[message.id] != nil else { return } // Do not send a request cancelled before its writer ran.
        try await send(message)
    }
    private func cancel(_ id: String, reason: String) async {
        timers.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(throwing: AEError(reason))
        try? await send(DaemonMessage(id: id, operation: "cancel"))
    }
    public func open(_ terminal: DaemonTerminal, script: String) async throws {
        guard terminals.count < 16 else { throw AEError("Daemon terminal limit reached") }
        terminals[terminal.id] = terminal
        do { _ = try await request(DaemonMessage(id: terminal.id, operation: "open", script: script)) }
        catch { terminals.removeValue(forKey: terminal.id)?.finish(); throw error }
    }
    public func closeTerminal(_ id: String) async {
        terminals.removeValue(forKey: id)?.finish()
        try? await send(DaemonMessage(id: id, operation: "close"))
    }
    public func close() async { task?.cancel(); await disconnected("Daemon connection closed") }
}

/// Same lifecycle contract as a local PTY; no browser-visible daemon credentials.
public final class DaemonTerminal: TerminalProcess, Sendable {
    public let id = UUID().uuidString
    private let connection: DaemonConnection
    private let stream: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    init(connection: DaemonConnection) {
        self.connection = connection
        (stream, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(64))
    }
    func receive(_ data: Data) { if case .dropped = continuation.yield(data) { finish(); Task { await connection.closeTerminal(id) } } }
    func finish() { continuation.finish() }
    public func readChunk() async -> Data? { var iterator = stream.makeAsyncIterator(); return await iterator.next() }
    public func input(_ data: Data) async throws { try await connection.send(DaemonMessage(id: id, operation: "input", data: data)) }
    public func resize(cols: Int, rows: Int) async throws { try await connection.send(DaemonMessage(id: id, operation: "resize", cols: cols, rows: rows)) }
    public func signal(_ signal: String) async throws { guard ["INT", "EOF"].contains(signal) else { throw AEError("Unsupported terminal signal") }; try await input(Data([signal == "INT" ? 3 : 4])) }
    public func closeSession() async { await connection.closeTerminal(id) }
}

final class DaemonPools: @unchecked Sendable {
    static let shared = DaemonPools()
    private let lock = NSLock()
    private var pools: [String: DaemonPool] = [:]
    func pool(home: URL) -> DaemonPool {
        lock.withLock {
            if let pool = pools[home.standardizedFileURL.path] { return pool }
            let pool = DaemonPool(home: home); pools[home.standardizedFileURL.path] = pool; return pool
        }
    }
}
