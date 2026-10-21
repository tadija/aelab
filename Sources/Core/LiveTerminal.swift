import Foundation

public struct PinnedSession: Codable, Sendable {
    public let id: String
    public let host: String
    public let cwd: String
    public let number: Int
    public let project: String?
    public let tool: String?
}
public struct TerminalMetadata: Encodable, Sendable {
    public let identity: HostIdentity?
    public let type: String = "terminal"
    public let id: String
    public let pinned: Bool
    public let cwd: String
    public let launch: TerminalLaunch
}
/// One reader owns the PTY; central replay and subscriptions support reconnects across transports.
public actor LiveTerminal {
    public let id = UUID().uuidString
    public let owner: String
    public let expires: Date
    public private(set) var launch: TerminalLaunch
    public let cwd: String
    private let identity: HostIdentity?
    private let pty: any TerminalProcess
    private var reader: Task<Void, Never>?
    private var clients: [UUID: AsyncStream<Data>.Continuation] = [:]
    private var replay = Data()
    public private(set) var ended = false
    public private(set) var pinned = false
    public private(set) var number = 0
    public init(pty: any TerminalProcess, owner: String, expires: Date, launch: TerminalLaunch, cwd: String, identity: HostIdentity? = nil) {
        self.pty = pty; self.owner = owner; self.expires = expires; self.launch = launch; self.cwd = cwd; self.identity = identity
    }
    public func start() {
        guard reader == nil, !ended else { return }
        reader = Task {
            while let chunk = await pty.readChunk() { publish(chunk) }
            await close()
        }
    }
    private func publish(_ data: Data) {
        replay.append(data); if replay.count > 262_144 { replay = Data(replay.suffix(262_144)) }
        for (id, client) in clients {
            if case .dropped = client.yield(data) { client.finish(); clients.removeValue(forKey: id) }
        }
    }
    public func subscribe() throws -> (UUID, AsyncStream<Data>, Data) {
        guard !ended else { throw AEError("Terminal has ended") }
        let id = UUID()
        let (stream, continuation) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(64))
        clients[id] = continuation
        continuation.onTermination = { _ in Task { await self.detach(id) } }
        return (id, stream, replay)
    }
    public func detach(_ id: UUID) async {
        clients.removeValue(forKey: id)?.finish()
        if clients.isEmpty && !pinned { await close() }
    }
    public func setPinned(_ value: Bool, number: Int? = nil) async throws {
        guard !ended, launch.session == nil else { throw AEError("Only a live temporary terminal can be pinned") }
        if let number, self.number == 0 { self.number = number }
        pinned = value
        if clients.isEmpty && !value { await close() }
    }
    public func renameHost(from: String, to: String) { if launch.host == from { launch.host = to } }
    public func metadata() -> TerminalMetadata { TerminalMetadata(identity: identity, id: id, pinned: pinned, cwd: cwd, launch: launch) }
    public func summary() -> PinnedSession { PinnedSession(id: id, host: launch.host, cwd: cwd, number: number, project: launch.project, tool: launch.tool) }
    public func input(_ data: Data) async throws { guard !ended else { throw AEError("Terminal has ended") }; try await pty.input(data) }
    public func resize(cols: Int, rows: Int) async throws { try await pty.resize(cols: cols, rows: rows) }
    public func signal(_ value: String) async throws { try await pty.signal(value) }
    public func close() async {
        guard !ended else { return }; ended = true; pinned = false; await pty.closeSession()
        reader?.cancel(); reader = nil
        let subscribers = clients.values; clients.removeAll(); for subscriber in subscribers { subscriber.finish() }
    }
}
