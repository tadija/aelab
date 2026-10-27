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
        let binaries = ["aelab-cli", "aelab-server", "aelab-daemon"]
        let build = source.appendingPathComponent(".build/release")
        let assets = source.appendingPathComponent("Frontend/dist")
        guard binaries.allSatisfy({ fm.isExecutableFile(atPath: build.appendingPathComponent($0).path) }),
              fm.fileExists(atPath: assets.appendingPathComponent("index.html").path) else {
            throw AEError("Build the release binaries and frontend first, or use ./.ae install")
        }
        let current = application.appendingPathComponent("current")
        let links = binaries.map { (name: $0, target: current.appendingPathComponent("bin/" + $0).path) } + [(name: "aelab", target: "aelab-cli")]
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
        return true
    }
}
