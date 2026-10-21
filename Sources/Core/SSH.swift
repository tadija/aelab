import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

public struct CommandResult: Codable, Sendable {
    public let status: Int32
    public let output: String
    public let error: String
    public let truncated: Bool
    public var transport: HostTransport? = nil
    public var category: String {
        if status == 124 { return "timeout" }
        if status == 255 && transport != .local && transport != .daemon {
            if error.lowercased().contains("permission denied") { return "ssh-authentication-failed" }
            if error.lowercased().contains("host key verification failed") || error.contains("REMOTE HOST IDENTIFICATION HAS CHANGED") { return "ssh-host-key-failed" }
            return "ssh-failure"
        }
        if status == 127 { return "unsupported" }
        if error.lowercased().contains("permission denied") || error.lowercased().contains("authentication") || error.contains("password is required") { return "permission-denied" }
        return status == 0 ? "ok" : "command-failed"
    }
}
private final class Capture: @unchecked Sendable {
    let lock = NSLock(); var data = Data(); var truncated = false
    func add(_ bytes: Data) { lock.lock(); defer { lock.unlock() }; let remaining = max(0, 1_048_576 - data.count); data.append(bytes.prefix(remaining)); if bytes.count > remaining { truncated = true } }
}
private final class ProcessControl: @unchecked Sendable {
    let process: Process
    private let lock = NSLock()
    private var cancelled = false
    private var finished = false
    init(_ process: Process) { self.process = process }
    func start() throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }; try process.run()
    }
    func cancel() { lock.lock(); defer { lock.unlock() }; cancelled = true; if process.isRunning { process.terminate() } }
    func finish() { lock.lock(); finished = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    var isFinished: Bool { lock.lock(); defer { lock.unlock() }; return finished }
}
/// Bounded process output, timeout, cancellation, and no shell on the central host.
public enum ProcessRunner {
    public static func run(executable: String, arguments: [String], timeout: TimeInterval = 15) async throws -> CommandResult {
        try Task.checkCancellation()
        let process = Process(); let out = Pipe(); let err = Pipe(); let stdout = Capture(); let stderr = Capture()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        let control = ProcessControl(process)
        process.standardInput = FileHandle.nullDevice; process.standardOutput = out; process.standardError = err
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    do {
                        try control.start()
                        let readers = DispatchGroup()
                        for (pipe, capture) in [(out, stdout), (err, stderr)] {
                            readers.enter(); DispatchQueue.global().async {
                                let fd = pipe.fileHandleForReading.fileDescriptor
                                var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                                while true {
                                    let ready = poll(&descriptor, 1, 50)
                                    if ready == 0 { if control.isFinished { break }; continue }
                                    if ready < 0 { if errno == EINTR { continue }; break }
                                    var bytes = [UInt8](repeating: 0, count: 16384)
                                    let count = read(fd, &bytes, bytes.count)
                                    if count <= 0 { break }; capture.add(Data(bytes.prefix(count)))
                                }
                                readers.leave()
                            }
                        }
                        let deadline = Date().addingTimeInterval(timeout)
                        var timedOut = false
                        while process.isRunning {
                            if control.isCancelled || Date() >= deadline { timedOut = !control.isCancelled; process.terminate(); break }; Thread.sleep(forTimeInterval: 0.025)
                        }
                        if timedOut || control.isCancelled { Thread.sleep(forTimeInterval: 0.1); if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) } }
                        process.waitUntilExit(); control.finish(); readers.wait()
                        if control.isCancelled { continuation.resume(throwing: CancellationError()); return }
                        continuation.resume(returning: CommandResult(status: timedOut ? 124 : process.terminationStatus, output: String(decoding: stdout.data, as: UTF8.self), error: String(decoding: stderr.data, as: UTF8.self), truncated: stdout.truncated || stderr.truncated))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { control.cancel() }
    }
}
public actor ConnectionLimiter {
    private var active = 0
    public init() {}
    public func acquire() async throws {
        while active >= 8 { try await Task.sleep(for: .milliseconds(25)) }; try Task.checkCancellation(); active += 1
    }
    public func release() { active -= 1 }
}
public struct SSH: Sendable {
    public let limiter: ConnectionLimiter
    public let configFile: String?
    public init(configFile: String? = ProcessInfo.processInfo.environment["AELAB_SSH_CONFIG"]) { limiter = ConnectionLimiter(); self.configFile = configFile }
    public func arguments(_ host: Host, tty: Bool = false) -> [String] {
        var args = (configFile.map { ["-F", $0] } ?? []) + ["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=8", "-o", "ConnectionAttempts=1", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=2", "-o", "ForwardAgent=no", "-o", "ClearAllForwardings=yes", "-o", "PermitLocalCommand=no", "-o", "RemoteCommand=none"]
        if let port = host.port { args += ["-p", String(port)] }; if tty { args.append("-tt") }
        args += ["--", host.destination]; return args
    }
    public func execute(_ host: Host, script: String, timeout: TimeInterval = 15) async throws -> CommandResult {
        try await limiter.acquire()
        do { let result = try await ProcessRunner.run(executable: "/usr/bin/ssh", arguments: arguments(host) + [host.executionScript(script)], timeout: timeout); await limiter.release(); return result }
        catch { await limiter.release(); throw error }
    }
    public func run(_ host: Host, args: [String], timeout: TimeInterval = 15) async throws -> CommandResult { try await execute(host, script: command(args), timeout: timeout) }
}
