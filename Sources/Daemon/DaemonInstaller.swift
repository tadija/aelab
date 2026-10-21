import Core
import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

enum DaemonInstaller {
    static let usage = "Use ./.ae daemon-install --endpoint https://HOST:1984 [--bind ADDRESS] [--home PATH] [--prefix PATH] [--service]"
    static func run(arguments: [String], home defaultHome: URL) async throws {
        if arguments == ["--help"] || arguments == ["-h"] { print(usage); return }
        var options: [String: String] = [:]; var service = false; var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            if flag == "--service", !service { service = true; index += 1; continue }
            guard ["--endpoint", "--bind", "--home", "--prefix"].contains(flag), options[flag] == nil,
                  index + 1 < arguments.count, !arguments[index + 1].isEmpty else { throw AEError(usage) }
            options[flag] = arguments[index + 1]; index += 2
        }
        let fm = FileManager.default
        let home = options["--home"].map { URL(fileURLWithPath: $0).standardizedFileURL } ?? defaultHome
        let prefix = options["--prefix"].map { URL(fileURLWithPath: $0).standardizedFileURL } ?? fm.homeDirectoryForCurrentUser.appendingPathComponent(".local")
        guard [home.path, prefix.path].allSatisfy({ $0.rangeOfCharacter(from: .controlCharacters) == nil }) else { throw AEError("Installation paths must not contain control characters") }
        let command = prefix.appendingPathComponent("bin/aelab-daemon")
        let launcher = home.appendingPathComponent("aelab-daemon")
        // Refuse collisions before creating credentials or changing an installation.
        if fm.fileExists(atPath: command.path) || (try? fm.destinationOfSymbolicLink(atPath: command.path)) != nil {
            guard (try? fm.destinationOfSymbolicLink(atPath: command.path)) == launcher.path else { throw AEError("Refusing to replace an unrelated executable at " + command.path) }
        }
        if fm.fileExists(atPath: home.path) {
            let settings = try DaemonSetup.settings(home: home); _ = try DaemonSetup.pairing(home: home)
            if let endpoint = options["--endpoint"] {
                var url = URLComponents(string: endpoint); if url?.port == nil { url?.port = 1984 }
                guard url?.url?.absoluteString == settings.endpoint else { throw AEError("Endpoint differs from the existing installation; credentials and settings were preserved") }
            }
            if let bind = options["--bind"], bind != settings.bind { throw AEError("Bind differs from the existing installation; settings were preserved") }
        } else {
            guard let endpoint = options["--endpoint"] else { throw AEError("First installation requires --endpoint https://HOST:1984") }
            try await DaemonSetup.initialize(home: home, endpoint: endpoint, bind: options["--bind"] ?? "0.0.0.0")
        }
        // Require an explicit stop before replacing the executable. No background updater.
        do {
            let lock = try DaemonRunLock(home: home)
            defer { withExtendedLifetime(lock) {} }
            if let attributes = try? fm.attributesOfItem(atPath: launcher.path), attributes[.type] as? FileAttributeType != .typeRegular {
                throw AEError("Refusing to replace a non-regular daemon executable")
            }
            let temporary = home.appendingPathComponent(".install-" + UUID().uuidString)
            defer { try? fm.removeItem(at: temporary) }
            try fm.copyItem(at: RuntimePaths.executable, to: temporary)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temporary.path)
            guard rename(temporary.path, launcher.path) == 0 else { throw AEError("Cannot install daemon executable") }
        }
        // The installed command does not depend on the checkout.
        try fm.createDirectory(at: command.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: command.path) { try fm.createSymbolicLink(at: command, withDestinationURL: launcher) }
        if service {
            #if os(macOS)
            let macos = true
            #else
            let macos = false
            #endif
            let result = try await ProcessRunner.run(executable: "/bin/sh", arguments: ["-c", DaemonUserService.script(macos: macos), "aelab-daemon-service", home.path], timeout: 30)
            guard result.status == 0 else { throw AEError("Daemon installed; user service could not start: " + result.error) }
        }
        print("Installed: \(command.path)\nDaemon home: \(home.path)")
        if !service { print("Start: \(quote(command.path)) --home \(quote(home.path)) run") }
        print("Export pairing: \(quote(command.path)) --home \(quote(home.path)) pairing --output pairing.json")
    }
}

/// A process lock protects local installation from replacing a running daemon.
final class DaemonRunLock {
    let descriptor: Int32
    init(home: URL) throws {
        let fd = open(home.appendingPathComponent("run.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw AEError("Cannot open daemon run lock") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { _ = close(fd); throw AEError("Daemon is running; stop it before installing") }
        descriptor = fd
    }
    deinit { _ = close(descriptor) }
}
