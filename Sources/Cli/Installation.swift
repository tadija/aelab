import Core
import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

struct Installation {
    let bin: URL
    let application: URL

    static func location(prefix: URL?, environment: [String: String] = ProcessInfo.processInfo.environment) -> Installation {
        if let prefix { return Installation(bin: prefix.appendingPathComponent("bin"), application: prefix.appendingPathComponent("share/aelab")) }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let data = environment["XDG_DATA_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil } ?? home.appendingPathComponent(".local/share")
        return Installation(bin: home.appendingPathComponent(".local/bin"), application: data.appendingPathComponent("aelab"))
    }

    /// Copies a complete release before switching the stable executable links.
    /// Never touches the runtime home or overwrites unrelated executable files.
    @discardableResult func install(source: URL) throws -> Bool {
        let fm = FileManager.default
        let binaries = ["aelab"]
        let build = source.appendingPathComponent(".build/release")
        let assets = source.appendingPathComponent("Frontend/dist")
        guard binaries.allSatisfy({ fm.isExecutableFile(atPath: build.appendingPathComponent($0).path) }),
              fm.fileExists(atPath: assets.appendingPathComponent("index.html").path) else {
            throw AEError("Build the release binaries and frontend first, or use ./.ae install")
        }
        let current = application.appendingPathComponent("current")
        let links = ["aelab"].map { (name: $0, target: current.appendingPathComponent("bin/" + $0).path) }
        for link in links {
            let destination = bin.appendingPathComponent(link.name)
            if let target = try? fm.destinationOfSymbolicLink(atPath: destination.path) {
                let managed = URL(fileURLWithPath: target, relativeTo: bin.appendingPathComponent("", isDirectory: true)).standardizedFileURL.path.hasPrefix(current.appendingPathComponent("bin").path + "/")
                guard target == link.target || managed else { throw AEError("Refusing to replace unrelated executable: \(destination.path)") }
            } else if fm.fileExists(atPath: destination.path) {
                throw AEError("Refusing to replace unrelated executable: \(destination.path)")
            }
        }
        if let target = try? fm.destinationOfSymbolicLink(atPath: current.path) {
            guard target.hasPrefix("releases/"), target.split(separator: "/").count == 2, !target.contains("..") else { throw AEError("Unrecognized installation link: \(current.path)") }
        } else if fm.fileExists(atPath: current.path) {
            throw AEError("Refusing to replace an unrelated installation directory: \(current.path)")
        }
        do { try fm.createDirectory(at: bin, withIntermediateDirectories: true) }
        catch { throw AEError("Cannot create install directory \(bin.path); use a writable --prefix or install with explicitly granted permissions") }
        func publishLinks() throws {
            for link in links {
                let destination = bin.appendingPathComponent(link.name)
                if (try? fm.destinationOfSymbolicLink(atPath: destination.path)) != link.target {
                    let temporary = bin.appendingPathComponent(".aelab-link-" + UUID().uuidString)
                    defer { try? fm.removeItem(at: temporary) }
                    try fm.createSymbolicLink(atPath: temporary.path, withDestinationPath: link.target)
                    guard rename(temporary.path, destination.path) == 0 else { throw AEError("Cannot publish executable link: " + destination.path) }
                }
            }
        }
        let template = source.appendingPathComponent("Docs/Config/aelab.example.json")
        let installedTemplate = current.appendingPathComponent("config/aelab.example.json")
        let matchingTemplate = fm.fileExists(atPath: template.path) == fm.fileExists(atPath: installedTemplate.path) && (!fm.fileExists(atPath: template.path) || fm.contentsEqual(atPath: template.path, andPath: installedTemplate.path))
        if binaries.allSatisfy({ fm.isExecutableFile(atPath: current.appendingPathComponent("bin/" + $0).path) && fm.contentsEqual(atPath: build.appendingPathComponent($0).path, andPath: current.appendingPathComponent("bin/" + $0).path) }),
           matchingTemplate, fm.contentsEqual(atPath: assets.path, andPath: current.appendingPathComponent("public").path) {
            try publishLinks()
            _ = try cleanup()
            return false
        }
        let releases = application.appendingPathComponent("releases")
        try fm.createDirectory(at: releases, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let name = UUID().uuidString
        let release = releases.appendingPathComponent(name)
        try fm.createDirectory(at: release.appendingPathComponent("bin"), withIntermediateDirectories: true)
        var activated = false
        defer { if !activated { try? fm.removeItem(at: release) } }
        for binary in binaries {
            let destination = release.appendingPathComponent("bin/" + binary)
            try fm.copyItem(at: build.appendingPathComponent(binary), to: destination)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        }
        if fm.fileExists(atPath: template.path) {
            try fm.createDirectory(at: release.appendingPathComponent("config"), withIntermediateDirectories: true)
            try fm.copyItem(at: template, to: release.appendingPathComponent("config/aelab.example.json"))
        }
        try fm.copyItem(at: assets, to: release.appendingPathComponent("public"))
        let temporaryLink = application.appendingPathComponent(".current-" + name)
        try fm.createSymbolicLink(atPath: temporaryLink.path, withDestinationPath: "releases/" + name)
        defer { try? fm.removeItem(at: temporaryLink) }
        guard rename(temporaryLink.path, current.path) == 0 else { throw AEError("Cannot activate installed release") }
        activated = true
        try publishLinks()
        _ = try cleanup()
        return true
    }
    /// Keep current, the newest fallback, and any release with open files.
    /// If process inspection is unavailable, leave releases intact.
    @discardableResult func cleanup(protected: Set<String>? = nil) throws -> Int {
        let fm = FileManager.default
        let releases = application.appendingPathComponent("releases")
        guard let target = try? fm.destinationOfSymbolicLink(atPath: application.appendingPathComponent("current").path),
              target.hasPrefix("releases/"), target.split(separator: "/").count == 2,
              UUID(uuidString: String(target.dropFirst(9))) != nil else { return 0 }
        func timestamp(_ url: URL) throws -> Date {
            let values = try url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            return values.creationDate ?? values.contentModificationDate ?? .distantPast
        }
        let entries = try fm.contentsOfDirectory(at: releases, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .creationDateKey, .contentModificationDateKey])
            .filter { url in
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                return UUID(uuidString: url.lastPathComponent) != nil && values.isDirectory == true && values.isSymbolicLink != true
            }.sorted { try timestamp($0) > timestamp($1) }
        let active: Set<String>
        if let protected { active = protected }
        else {
            let candidates = ["/usr/sbin/lsof", "/usr/bin/lsof", "/bin/lsof"]
            guard let tool = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) else { return 0 }
            let process = Process(); let output = Pipe()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = ["-n", "-P", "-Fn", "+D", releases.path]
            process.standardOutput = output; process.standardError = FileHandle.nullDevice
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            guard process.terminationStatus == 0 || process.terminationStatus == 1 else { return 0 }
            let paths = String(decoding: data, as: UTF8.self).split(separator: "\n").filter { $0.hasPrefix("n") }.map { String($0.dropFirst()) }
            active = Set(entries.filter { entry in paths.contains { $0.hasPrefix(entry.path + "/") } }.map(\.lastPathComponent))
        }
        let current = String(target.dropFirst(9))
        var keep = active; keep.insert(current)
        if let previous = entries.first(where: { $0.lastPathComponent != current }) { keep.insert(previous.lastPathComponent) }
        var removed = 0
        for entry in entries where !keep.contains(entry.lastPathComponent) { try fm.removeItem(at: entry); removed += 1 }
        return removed
    }

}
