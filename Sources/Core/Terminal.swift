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
    private var pinNumbers: [String: Int] = [:]
    private var live: [String: LiveTerminal] = [:]
    private struct TmuxPin: Codable, Sendable, Equatable {
        let id: String; let owner: String; let expires: Date; var host: String; var session: String; let number: Int; var changed: Date = Date()
        var summary: PinnedSession { PinnedSession(id: id, host: host, cwd: "", number: number, project: nil, tool: nil, session: session, programStatus: nil) }
    }
    private var tmuxPins: [String: TmuxPin] = [:]
    private let tmuxFile: URL?
    private func saveTmuxPins(_ next: [String: TmuxPin]) throws {
        guard next != tmuxPins else { return }
        if let tmuxFile { try atomicPrivateWrite(jsonEncoder.encode(next.values.sorted { $0.number < $1.number }), to: tmuxFile) }
        for id in tmuxPins.keys { pinNumbers.removeValue(forKey: id) }
        tmuxPins = next
        for pin in next.values { pinNumbers[pin.id] = pin.number }
    }
    public func setTmuxPinned(host: String, session: String, owner: String, expires: Date, value: Bool) async throws {
        try validateSession(session)
        await removeEnded()
        if let existing = tmuxPins.values.first(where: { $0.host == host && $0.session == session && $0.owner == owner }) {
            if !value { var next = tmuxPins; next.removeValue(forKey: existing.id); try saveTmuxPins(next) }
            return
        }
        guard value else { return }
        guard tmuxPins.count < 256 else { throw AEError("Too many pinned tmux sessions") }
        let id = UUID().uuidString
        let used = Set(pinNumbers.values); var number = 1
        while used.contains(number) { number += 1 }
        var next = tmuxPins
        next[id] = TmuxPin(id: id, owner: owner, expires: expires, host: host, session: session, number: number)
        try saveTmuxPins(next)
    }
    public func updateTmuxSession(host: String, session: String, renamed: String? = nil) throws {
        var next = tmuxPins
        for (id, var pin) in next where pin.host == host && pin.session == session {
            if let renamed { pin.session = renamed; pin.changed = Date(); next[id] = pin }
            else { next.removeValue(forKey: id) }
        }
        try saveTmuxPins(next)
    }
    public func reconcileTmux(host: String, sessions: Set<String>, observedSince: Date = .distantFuture) throws {
        try saveTmuxPins(tmuxPins.filter { $0.value.host != host || $0.value.changed > observedSince || sessions.contains($0.value.session) })
    }
    public func retainHosts(_ hosts: Set<String>) throws {
        try saveTmuxPins(tmuxPins.filter { hosts.contains($0.value.host) })
    }
    public init() { tmuxFile = nil }
    public init(home: URL) throws {
        let file = home.appendingPathComponent("state/tmux-pins.json")
        tmuxFile = file
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let data = try Data(contentsOf: file)
        guard data.count <= 1_048_576 else { throw AEError("Tmux pin state is too large") }
        let pins = try JSONDecoder().decode([TmuxPin].self, from: data)
        guard pins.count <= 256, Set(pins.map(\.id)).count == pins.count,
              Set(pins.map(\.number)).count == pins.count,
              Set(pins.map { [$0.owner, $0.host, $0.session] }).count == pins.count else { throw AEError("Invalid or duplicate tmux pin state") }
        for pin in pins {
            try validateSession(pin.session)
            guard UUID(uuidString: pin.id) != nil, (1...4096).contains(pin.number),
                  !pin.host.isEmpty, !pin.owner.isEmpty else { throw AEError("Invalid tmux pin state") }
            tmuxPins[pin.id] = pin; pinNumbers[pin.id] = pin.number
        }
    }
    public func issue(_ launch: TerminalLaunch, owner: String) throws -> String {
        tickets = tickets.filter { $0.value.expires > Date() }
        guard tickets.count < 64 else { throw AEError("Too many pending terminals") }
        let id = UUID().uuidString; tickets[id] = Ticket(launch: launch, owner: owner, expires: Date().addingTimeInterval(30)); return id
    }
    public func consume(_ id: String, owner: String) throws -> TerminalLaunch {
        guard let ticket = tickets[id], ticket.owner == owner, ticket.expires > Date(), active < 16 else { throw AEError("Invalid/expired terminal ticket or session limit reached") }
        tickets.removeValue(forKey: id); active += 1; return ticket.launch
    }
    private func removeEnded() async {
        for (id, terminal) in live where await terminal.ended {
            live.removeValue(forKey: id); pinNumbers.removeValue(forKey: id)
        }
    }
    public func register(_ terminal: LiveTerminal) async throws {
        await removeEnded()
        guard live.count < 16 else { throw AEError("Terminal process limit reached") }
        live[terminal.id] = terminal
    }
    public func setPinned(_ terminal: LiveTerminal, value: Bool) async throws {
        await removeEnded()
        guard live[terminal.id] != nil else { throw AEError("Unknown terminal") }
        let existing = await terminal.number
        var number = pinNumbers[terminal.id] ?? existing
        if value && number == 0 {
            let used = Set(pinNumbers.values)
            number = 1
            while used.contains(number) { number += 1 }
            // Reserve before awaiting the terminal actor so concurrent pins cannot collide.
            pinNumbers[terminal.id] = number
        }
        do { try await terminal.setPinned(value, number: number) }
        catch { pinNumbers.removeValue(forKey: terminal.id); throw error }
    }
    public func metadata(for terminal: LiveTerminal) async -> TerminalMetadata {
        let metadata = await terminal.metadata()
        guard let session = metadata.launch.session else { return metadata }
        let pinned = tmuxPins.values.contains { $0.host == metadata.launch.host && $0.session == session && $0.owner == terminal.owner && $0.expires > Date() }
        return TerminalMetadata(identity: metadata.identity, id: metadata.id, pinned: pinned, cwd: metadata.cwd, launch: metadata.launch)
    }
    public func fileHost(_ id: String, host: String, owner: String) async throws -> Host {
        guard let terminal = live[id], terminal.owner == owner, await terminal.launch.host == host,
              terminal.expires > Date(), !(await terminal.ended), let target = terminal.fileHost else { throw AEError("Unknown or closed terminal") }
        return target
    }
    public func retained(_ id: String, host: String, owner: String, allowTemporary: Bool = false) async throws -> LiveTerminal {
        guard let terminal = live[id], terminal.owner == owner else { throw AEError("Unknown terminal") }
        let launch = await terminal.launch
        let pinned = await terminal.pinned
        guard launch.host == host,
              terminal.expires > Date(), (pinned || (allowTemporary && launch.session == nil)), !(await terminal.ended) else { throw AEError("Unknown or expired pinned terminal") }
        return terminal
    }
    public func temporary(host: String, owner: String) async -> [PinnedSession] {
        var result: [PinnedSession] = []
        for terminal in live.values where terminal.owner == owner && terminal.expires > Date() {
            let launch = await terminal.launch
            if launch.host == host, launch.session == nil, !(await terminal.pinned), !(await terminal.ended) {
                result.append(await terminal.summary())
            }
        }
        return result.sorted { $0.id < $1.id }
    }
    public func pinned(host: String, owner: String) async -> [PinnedSession] {
        var result = tmuxPins.values.filter { $0.host == host && $0.owner == owner && $0.expires > Date() }.map(\.summary)
        for terminal in live.values where terminal.owner == owner && terminal.expires > Date() {
            if await terminal.launch.host == host, await terminal.pinned, !(await terminal.ended) { result.append(await terminal.summary()) }
        }
        return result.sorted { $0.number < $1.number }
    }
    public func closePinned(_ id: String, host: String, owner: String, allowTemporary: Bool = false) async throws {
        let terminal = try await retained(id, host: host, owner: owner, allowTemporary: allowTemporary)
        await terminal.close(); live.removeValue(forKey: id); pinNumbers.removeValue(forKey: id)
    }
    public func disconnect(login: String) async {
        tickets = tickets.filter { $0.value.owner != login }
        for terminal in live.values { await terminal.disconnect(login: login) }
    }
    public func close(owner: String) async throws {
        try saveTmuxPins(tmuxPins.filter { $0.value.owner != owner })
        for (id, terminal) in live where terminal.owner == owner { await terminal.close(); live.removeValue(forKey: id); pinNumbers.removeValue(forKey: id) }
    }
    public func reap(authorized: @Sendable (String) async -> Bool) async throws {
        for (id, terminal) in live {
            if await terminal.ended { live.removeValue(forKey: id); pinNumbers.removeValue(forKey: id) }
            else {
                let valid = await authorized(terminal.owner)
                if terminal.expires <= Date() || !valid { await terminal.close(); live.removeValue(forKey: id); pinNumbers.removeValue(forKey: id) }
            }
        }
        // Collect IDs before yielding, then remove from the current state so concurrent pins are preserved.
        var removed: Set<String> = []
        for (id, pin) in tmuxPins {
            let valid = await authorized(pin.owner)
            if pin.expires <= Date() || !valid { removed.insert(id) }
        }
        try saveTmuxPins(tmuxPins.filter { !removed.contains($0.key) })
    }
    public func renameHosts(_ renames: [String: String]) async throws {
        var next = tmuxPins
        for (id, var pin) in next { if let host = renames[pin.host] { pin.host = host; next[id] = pin } }
        try saveTmuxPins(next)
        for (from, to) in renames {
            for (id, ticket) in tickets where ticket.launch.host == from {
                var launch = ticket.launch; launch.host = to
                tickets[id] = Ticket(launch: launch, owner: ticket.owner, expires: ticket.expires)
            }
            for terminal in live.values { await terminal.renameHost(from: from, to: to) }
        }
    }
    public func closeAll() async { for terminal in live.values { await terminal.close() }; live.removeAll(); tmuxPins.removeAll(); pinNumbers.removeAll() }
    public func release() { active = max(0, active - 1) }
}
