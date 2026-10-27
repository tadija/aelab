import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

public struct TerminalFile: Codable, Sendable {
    public let name: String
    public let path: String
    public let size: Int
}
public enum TerminalFiles {
    public static let maximumSize = 20 * 1024 * 1024
    public static func validate(name: String, size: Int) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), name.utf8.count <= 255,
              name.rangeOfCharacter(from: .controlCharacters) == nil, (0...maximumSize).contains(size) else { throw AEError("Use a file name without path separators or control characters; files must be at most 20 MiB") }
    }
    public static var directory: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path).appendingPathComponent(".aelab/uploads")
    }
    /// One stdin stream over SSH; no bytes or base64 payloads are put in argv or the PTY.
    public static func sshScript(name: String, size: Int) throws -> String {
        try validate(name: name, size: size)
        return """
        set -eu
        umask 077
        test ! -L "$HOME/.aelab" && test ! -L "$HOME/.aelab/uploads"
        mkdir -p "$HOME/.aelab/uploads"
        chmod 700 "$HOME/.aelab/uploads"
        work=$(mktemp -d "$HOME/.aelab/uploads/file.XXXXXXXX")
        trap 'rm -rf "$work"' EXIT HUP INT TERM
        file="$work"/\(quote(name))
        cat > "$file"
        count=$(wc -c < "$file" | tr -d '[:space:]')
        test "$count" = \(size)
        chmod 600 "$file"
        trap - EXIT HUP INT TERM
        printf '%s' "$file"
        """
    }
}

/// Private, unique destinations. Only complete, length-checked files become visible to callers.
/// Completed uploads are user files: they survive terminal disconnects, pins, tmux and restarts.
public actor TerminalFileStore {
    private struct Transfer { let name: String; let size: Int; let folder: URL; let partial: URL; let handle: FileHandle; var received = 0 }
    private var transfers: [String: Transfer] = [:]
    private let directory: URL
    public init(directory: URL = TerminalFiles.directory) { self.directory = directory }
    public func begin(name: String, size: Int, id: String = UUID().uuidString) throws -> String {
        try TerminalFiles.validate(name: name, size: size)
        guard UUID(uuidString: id) != nil, transfers[id] == nil else { throw AEError("Invalid or duplicate file transfer") }
        guard transfers.count < 4 else { throw AEError("Too many file transfers") }
        let fm = FileManager.default
        for folder in [directory.deletingLastPathComponent(), directory] {
            if !fm.fileExists(atPath: folder.path) { try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
            let attributes = try fm.attributesOfItem(atPath: folder.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory, (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw AEError("Uploads require an owned directory without symlinks") }
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let folder = directory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let partial = folder.appendingPathComponent(name == ".partial" ? ".partial-" + UUID().uuidString : ".partial")
        let fd = open(partial.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { try? fm.removeItem(at: folder); throw AEError("Cannot create upload") }
        transfers[id] = Transfer(name: name, size: size, folder: folder, partial: partial, handle: FileHandle(fileDescriptor: fd, closeOnDealloc: true))
        return id
    }
    public func append(_ id: String, offset: Int, data: Data) throws {
        guard var transfer = transfers[id], offset == transfer.received, data.count <= 65536, data.count <= transfer.size - transfer.received else { throw AEError("Invalid file transfer chunk") }
        try transfer.handle.write(contentsOf: data); transfer.received += data.count; transfers[id] = transfer
    }
    public func finish(_ id: String) throws -> TerminalFile {
        guard let transfer = transfers[id], transfer.received == transfer.size else { throw AEError("Incomplete file transfer") }
        try transfer.handle.synchronize(); try transfer.handle.close()
        let destination = transfer.folder.appendingPathComponent(transfer.name)
        try FileManager.default.moveItem(at: transfer.partial, to: destination)
        transfers.removeValue(forKey: id)
        return TerminalFile(name: transfer.name, path: destination.path, size: transfer.size)
    }
    public func abort(_ id: String) { if let transfer = transfers.removeValue(forKey: id) { try? transfer.handle.close(); try? FileManager.default.removeItem(at: transfer.folder) } }
    public func close() { for id in Array(transfers.keys) { abort(id) } }
}

extension HostExecution {
    public func upload(_ host: Host, name: String, size: Int, source: URL) async throws -> TerminalFile {
        try TerminalFiles.validate(name: name, size: size)
        if host.transport == .daemon { return try await daemon.upload(host, name: name, size: size, source: source) }
        if !host.isLocal {
            let result = try await ssh.execute(host, script: TerminalFiles.sshScript(name: name, size: size), timeout: 120, inputFile: source)
            guard result.status == 0, !result.truncated else { throw AEError("File transfer failed: " + result.error) }
            try absolutePath(result.output)
            return TerminalFile(name: name, path: result.output, size: size)
        }
        let store = TerminalFileStore(), id = try await store.begin(name: name, size: size)
        do {
            let input = try FileHandle(forReadingFrom: source); defer { try? input.close() }
            var offset = 0
            while let chunk = try input.read(upToCount: 65536), !chunk.isEmpty {
                try Task.checkCancellation(); try await store.append(id, offset: offset, data: chunk); offset += chunk.count
            }
            return try await store.finish(id)
        } catch { await store.abort(id); throw error }
    }
}
