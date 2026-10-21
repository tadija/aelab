import Foundation

public struct DaemonSettings: Codable, Sendable {
    public let endpoint: String
    public let bind: String
    public var port: Int { URL(string: endpoint)?.port ?? 1984 }
    public init(endpoint: String, bind: String) { self.endpoint = endpoint; self.bind = bind }
}
public enum DaemonSetup {
    public static var defaultHome: URL { DaemonPairing.defaultHome.appendingPathComponent("daemon") }
    public static func initialize(home: URL, endpoint: String, bind: String) async throws {
        guard var components = URLComponents(string: endpoint) else { throw AEError("Provide an HTTPS endpoint") }
        if components.port == nil { components.port = 1984 }
        guard let endpoint = components.url?.absoluteString, let url = URL(string: endpoint), url.scheme == "https", url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/", let rawHost = url.host else { throw AEError("Provide an HTTPS endpoint") }
        let hostname = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard hostname.range(of: "^[A-Za-z0-9.:-]+$", options: .regularExpression) != nil,
              bind.range(of: "^[A-Za-z0-9.:-]+$", options: .regularExpression) != nil else { throw AEError("Invalid daemon endpoint/bind address") }
        let fm = FileManager.default
        guard !fm.fileExists(atPath: home.path) else { throw AEError("Daemon home already exists; credentials will not be overwritten") }
        try fm.createDirectory(at: home.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Only one initializer may own cleanup or create credentials in this directory.
        try fm.createDirectory(at: home, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var complete = false; defer { if !complete { try? fm.removeItem(at: home) } }
        let san = hostname.contains(":") || hostname.range(of: "^[0-9.]+$", options: .regularExpression) != nil ? "IP:" + hostname : "DNS:" + hostname
        let cert = home.appendingPathComponent("certificate.pem"); let key = home.appendingPathComponent("key.pem")
        let result = try await ProcessRunner.run(executable: "/usr/bin/openssl", arguments: ["req", "-x509", "-newkey", "rsa:3072", "-sha256", "-nodes", "-days", "365", "-subj", "/CN=aelab-daemon", "-addext", "subjectAltName=" + san, "-keyout", key.path, "-out", cert.path], timeout: 30)
        guard result.status == 0 else { throw AEError("Cannot generate daemon certificate: " + result.error) }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: key.path)
        let token = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
        let pairing = DaemonPairing(endpoint: endpoint, certificate: try String(contentsOf: cert, encoding: .utf8), token: token)
        try pairing.validate()
        try privateWrite(JSONEncoder().encode(pairing), to: home.appendingPathComponent("pairing.json"))
        try privateWrite(JSONEncoder().encode(DaemonSettings(endpoint: endpoint, bind: bind)), to: home.appendingPathComponent("daemon.json"))
        complete = true
    }
    public static func privateWrite(_ data: Data, to file: URL) throws {
        let fm = FileManager.default; let temp = file.deletingLastPathComponent().appendingPathComponent(".aelab-" + UUID().uuidString)
        guard fm.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw AEError("Cannot write private daemon file") }
        defer { try? fm.removeItem(at: temp) }
        try fm.linkItem(at: temp, to: file) // Atomic, never replaces an existing file or symlink.
    }
    private static func privateRead(_ file: URL) throws -> Data {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o777) & 0o077 == 0,
              ((attributes[.size] as? NSNumber)?.intValue ?? 32769) <= 32768 else { throw AEError("Daemon settings/pairing must be private regular files of at most 32 KiB") }
        return try Data(contentsOf: file)
    }
    public static func settings(home: URL) throws -> DaemonSettings { try JSONDecoder().decode(DaemonSettings.self, from: privateRead(home.appendingPathComponent("daemon.json"))) }
    public static func pairing(home: URL) throws -> DaemonPairing {
        let result = try JSONDecoder().decode(DaemonPairing.self, from: privateRead(home.appendingPathComponent("pairing.json")))
        try result.validate(); return result
    }
}
