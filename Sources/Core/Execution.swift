import Foundation

extension Host {
    public func executionScript(_ script: String) -> String {
        let path = executionPaths
        guard !path.isEmpty else { return script }
        return "export PATH=" + quote(path.joined(separator: ":")) + ":\"$PATH\";\n" + script
    }
}

/// One execution boundary behind every native adapter, probe and terminal launch.
public struct HostExecution: Sendable {
    public let ssh: SSH
    public let daemon: DaemonPool
    private let localLimiter = ConnectionLimiter()
    public init(ssh: SSH = SSH(), home: URL? = nil) { self.ssh = ssh; daemon = DaemonPools.shared.pool(home: home ?? DaemonPairing.defaultHome) }
    public func terminal(_ host: Host, script: String) async throws -> any TerminalProcess {
        if host.transport == .daemon { return try await daemon.terminal(host, script: host.executionScript(script)) }
        return try TerminalPTY(host: host, script: script, execution: self)
    }
    public func terminalCommand(_ host: Host, script: String) throws -> (executable: String, arguments: [String]) {
        guard host.transport != .daemon else { throw AEError("Daemon terminals require the asynchronous terminal transport") }
        return host.isLocal ? ("/bin/sh", ["-c", host.executionScript(script)]) : ("/usr/bin/ssh", ssh.arguments(host, tty: true) + [host.executionScript(script)])
    }
    public func execute(_ host: Host, script: String, timeout: TimeInterval = 15) async throws -> CommandResult {
        if host.transport == .daemon { return try await daemon.execute(host, script: host.executionScript(script), timeout: timeout) }
        if !host.isLocal { return try await ssh.execute(host, script: script, timeout: timeout) }
        return try await local(executable: "/bin/sh", arguments: ["-c", host.executionScript(script)], timeout: timeout)
    }
    public func run(_ host: Host, args: [String], timeout: TimeInterval = 15) async throws -> CommandResult {
        return try await execute(host, script: command(args), timeout: timeout)
    }
    private func local(executable: String, arguments: [String], timeout: TimeInterval) async throws -> CommandResult {
        try await localLimiter.acquire()
        do {
            let result = try await ProcessRunner.run(executable: executable, arguments: arguments, timeout: timeout)
            await localLimiter.release(); return CommandResult(status: result.status, output: result.output, error: result.error, truncated: result.truncated, transport: .local)
        } catch { await localLimiter.release(); throw error }
    }
}
