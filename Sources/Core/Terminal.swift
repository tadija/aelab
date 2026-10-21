import Foundation
import CPTY
#if os(Linux)
import Glibc
#else
import Darwin
#endif

public protocol TerminalProcess: Sendable {
    func readChunk() async -> Data?
    func input(_ data: Data) async throws
    func resize(cols: Int, rows: Int) async throws
    func signal(_ signal: String) async throws
    func closeSession() async
}

public final class TerminalPTY: TerminalProcess, @unchecked Sendable {
    private let fd: Int32
    private let pid: Int32
    private let lock = NSLock()
    private var closed = false
    private let local: Bool
    public init(host: Host, script: String, execution: HostExecution) throws {
        let launch = try execution.terminalCommand(host, script: script)
        let args = [launch.executable] + launch.arguments
        local = host.isLocal
        let pointers = args.map { strdup($0) }; defer { pointers.forEach { free($0) } }
        var argv = pointers + [nil]; var master: Int32 = -1
        let pid = argv.withUnsafeMutableBufferPointer { ae_spawn_pty(launch.executable, $0.baseAddress, &master) }
        guard pid > 0 else { throw AEError("Cannot launch terminal PTY") }; self.pid = pid; fd = master
        _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
    }
    public func readChunk() async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                var pollFD = pollfd(fd: self.fd, events: Int16(POLLIN), revents: 0)
                while true {
                    self.lock.lock(); let closed = self.closed; self.lock.unlock()
                    if closed { continuation.resume(returning: nil); return }
                    let result = poll(&pollFD, 1, 250)
                    if result == 0 { continue }
                    if result < 0 { if errno == EINTR { continue }; continuation.resume(returning: nil); return }
                    var bytes = [UInt8](repeating: 0, count: 16384)
                    self.lock.lock()
                    let count = self.closed ? -1 : read(self.fd, &bytes, bytes.count)
                    self.lock.unlock()
                    continuation.resume(returning: count > 0 ? Data(bytes.prefix(count)) : nil); return
                }
            }
        }
    }
    public func input(_ data: Data) throws {
        guard data.count <= 65536 else { throw AEError("Input too large") }
        lock.lock(); defer { lock.unlock() }; guard !closed else { throw AEError("Terminal closed") }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < data.count {
                let count = write(fd, buffer.baseAddress!.advanced(by: offset), data.count - offset)
                guard count > 0 else { throw AEError("PTY write failed") }; offset += count
            }
        }
    }
    public func resize(cols: Int, rows: Int) throws {
        guard (2...500).contains(cols), (2...300).contains(rows) else { throw AEError("Invalid terminal size") }
        lock.lock(); defer { lock.unlock() }; if !closed {
            _ = ae_resize_pty(fd, UInt16(cols), UInt16(rows))
            // Also notify OpenSSH directly; it forwards local geometry to the remote PTY.
            _ = kill(pid, SIGWINCH)
        }
    }
    public func signal(_ signal: String) throws {
        switch signal { case "INT": try input(Data([3])); case "EOF": try input(Data([4])); default: throw AEError("Unsupported terminal signal") }
    }
    public func closeSession() {
        lock.lock(); if closed { lock.unlock(); return }; closed = true
        _ = kill(local ? -pid : pid, SIGHUP); _ = close(fd); lock.unlock()
        let child = pid; let local = local
        DispatchQueue.global().async {
            var status: Int32 = 0
            for _ in 0..<20 { if waitpid(child, &status, WNOHANG) != 0 { return }; usleep(50_000) }
            _ = kill(local ? -child : child, SIGKILL); _ = waitpid(child, &status, 0)
        }
    }
    deinit { closeSession() }
}
public actor TerminalRegistry {
    public struct Ticket: Sendable { public let launch: TerminalLaunch; public let owner: String; public let expires: Date }
    private var tickets: [String: Ticket] = [:]
    private var active = 0
    private var nextNumber = 1
    private var live: [String: LiveTerminal] = [:]
    public init() {}
    public func issue(_ launch: TerminalLaunch, owner: String) throws -> String {
        tickets = tickets.filter { $0.value.expires > Date() }
        guard tickets.count < 64 else { throw AEError("Too many pending terminals") }
        let id = UUID().uuidString; tickets[id] = Ticket(launch: launch, owner: owner, expires: Date().addingTimeInterval(30)); return id
    }
    public func consume(_ id: String, owner: String) throws -> TerminalLaunch {
        guard let ticket = tickets[id], ticket.owner == owner, ticket.expires > Date(), active < 16 else { throw AEError("Invalid/expired terminal ticket or session limit reached") }
        tickets.removeValue(forKey: id); active += 1; return ticket.launch
    }
    public func register(_ terminal: LiveTerminal) async throws {
        for (id, value) in live where await value.ended { live.removeValue(forKey: id) }
        guard live.count < 16 else { throw AEError("Terminal process limit reached") }
        live[terminal.id] = terminal
    }
    public func setPinned(_ terminal: LiveTerminal, value: Bool) async throws {
        guard live[terminal.id] != nil else { throw AEError("Unknown terminal") }
        let existing = await terminal.number
        var number = existing
        if value && existing == 0 { number = nextNumber; nextNumber += 1 }
        try await terminal.setPinned(value, number: number)
    }
    public func retained(_ id: String, host: String, owner: String) async throws -> LiveTerminal {
        guard let terminal = live[id], terminal.owner == owner,
              await terminal.launch.host == host,
              terminal.expires > Date(), await terminal.pinned, !(await terminal.ended) else { throw AEError("Unknown or expired pinned terminal") }
        return terminal
    }
    public func pinned(host: String, owner: String) async -> [PinnedSession] {
        var result: [PinnedSession] = []
        for terminal in live.values where terminal.owner == owner && terminal.expires > Date() {
            if await terminal.launch.host == host, await terminal.pinned, !(await terminal.ended) { result.append(await terminal.summary()) }
        }
        return result.sorted { $0.number < $1.number }
    }
    public func closePinned(_ id: String, host: String, owner: String) async throws {
        let terminal = try await retained(id, host: host, owner: owner)
        await terminal.close(); live.removeValue(forKey: id)
    }
    public func close(owner: String) async {
        for (id, terminal) in live where terminal.owner == owner { await terminal.close(); live.removeValue(forKey: id) }
    }
    public func reap(authorized: @Sendable (String) async -> Bool) async {
        for (id, terminal) in live {
            if await terminal.ended { live.removeValue(forKey: id) }
            else {
                let valid = await authorized(terminal.owner)
                if terminal.expires <= Date() || !valid { await terminal.close(); live.removeValue(forKey: id) }
            }
        }
    }
    public func renameHosts(_ renames: [String: String]) async {
        for (from, to) in renames {
            for (id, ticket) in tickets where ticket.launch.host == from {
                var launch = ticket.launch; launch.host = to
                tickets[id] = Ticket(launch: launch, owner: ticket.owner, expires: ticket.expires)
            }
            for terminal in live.values { await terminal.renameHost(from: from, to: to) }
        }
    }
    public func closeAll() async { for terminal in live.values { await terminal.close() }; live.removeAll() }
    public func release() { active = max(0, active - 1) }
}
