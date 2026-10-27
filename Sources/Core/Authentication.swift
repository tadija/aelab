import Foundation
import Crypto
import _CryptoExtras

public struct PasswordRecord: Codable, Sendable {
    public let salt: String
    public let hash: String
    public let iterations: Int
    public static func derive(_ password: String, salt: Data, iterations: Int) -> Data {
        // Library-backed PBKDF2-HMAC-SHA256; no bespoke cryptographic primitive.
        guard let key = try? KDF.Insecure.PBKDF2.deriveKey(from: Data(password.utf8), salt: salt, using: .sha256, outputByteCount: 32, unsafeUncheckedRounds: iterations) else { return Data() }
        return key.withUnsafeBytes { Data($0) }
    }
    public init(password: String) throws {
        guard password.count >= 12, password.utf8.count <= 1024 else { throw AEError("Use a password of 12–1024 characters") }
        let bytes = randomBytes(32); salt = bytes.base64EncodedString(); iterations = 600_000
        hash = Self.derive(password, salt: bytes, iterations: iterations).base64EncodedString()
    }
    public func verify(_ password: String) -> Bool {
        guard password.utf8.count <= 1024, (600_000...1_000_000).contains(iterations), let salt = Data(base64Encoded: salt), salt.count == 32,
              let hash = Data(base64Encoded: hash), hash.count == 32 else { return false }
        return constantTimeEqual(Self.derive(password, salt: salt, iterations: iterations), hash)
    }
}
public func randomBytes(_ count: Int) -> Data { var rng = SystemRandomNumberGenerator(); return Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &rng) }) }
public func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
    guard lhs.count == rhs.count else { return false }; var diff: UInt8 = 0
    for i in lhs.indices { diff |= lhs[i] ^ rhs[i] }; return diff == 0
}
public struct LoginSession: Codable, Sendable { public let token: String; public let csrf: String; public let expires: Date; public let owner: String }
public actor Authentication {
    private let file: URL
    private var sessions: [String: LoginSession] = [:]
    private var credentialsRevision: String?
    private var failures = 0
    private var retryAt = Date.distantPast
    public init(home: URL) { file = home.appendingPathComponent("state/admin.json") }
    public func bootstrap(_ password: String) async throws {
        guard !FileManager.default.fileExists(atPath: file.path) else { throw AEError("Administrator already exists; use local password reset") }
        let record = try await Task.detached { try PasswordRecord(password: password) }.value
        try atomicPrivateWrite(jsonEncoder.encode(record), to: file, overwrite: false)
        sessions.removeAll()
    }
    public func reset(_ password: String) async throws {
        let record = try await Task.detached { try PasswordRecord(password: password) }.value
        try atomicPrivateWrite(jsonEncoder.encode(record), to: file); sessions.removeAll(); credentialsRevision = nil
    }
    private func verify(_ password: String) async throws -> String {
        guard Date() >= retryAt else { throw AEError("Login rate limit; try again later") }
        // Reserve a slot before yielding to password hashing, including concurrent requests.
        retryAt = Date().addingTimeInterval(1)
        let credentialData = try Data(contentsOf: file)
        let record = try JSONDecoder().decode(PasswordRecord.self, from: credentialData)
        let valid = await Task.detached { record.verify(password) }.value
        guard valid else { failures += 1; retryAt = Date().addingTimeInterval(min(60, pow(2, Double(min(failures, 6))))); throw AEError("Invalid password") }
        guard try Data(contentsOf: file) == credentialData else { throw AEError("Credentials changed; sign in again") }
        failures = 0
        return revision(credentialData)
    }
    public func verifySessionPassword(token: String, csrf: String, password: String) async throws {
        _ = try authorize(token: token, csrf: csrf, mutation: true)
        _ = try await verify(password)
        // Recheck expiry and credential changes after password hashing yields.
        _ = try authorize(token: token, csrf: csrf, mutation: true)
    }
    public func changePassword(current: String, replacement: String) async throws {
        let expected = try await verify(current)
        let record = try await Task.detached { try PasswordRecord(password: replacement) }.value
        guard revision(try Data(contentsOf: file)) == expected else { throw AEError("Credentials changed; try again") }
        try atomicPrivateWrite(jsonEncoder.encode(record), to: file)
        sessions.removeAll(); credentialsRevision = nil
    }
    public func login(_ password: String) async throws -> LoginSession {
        let currentRevision = try await verify(password)
        if credentialsRevision != currentRevision { sessions.removeAll(); credentialsRevision = currentRevision }
        failures = 0
        sessions = sessions.filter { $0.value.expires > Date() }
        guard sessions.count < 32 else { throw AEError("Too many login sessions") }
        let session = LoginSession(token: randomBytes(32).base64EncodedString(), csrf: randomBytes(32).base64EncodedString(), expires: Date().addingTimeInterval(12 * 3600), owner: currentRevision)
        sessions[session.token] = session; return session
    }
    public func authorize(token: String?, csrf: String? = nil, mutation: Bool = false) throws -> LoginSession {
        guard let credentialsRevision, let data = try? Data(contentsOf: file), revision(data) == credentialsRevision else { sessions.removeAll(); throw AEError("Authentication required") }
        guard let token, let session = sessions[token], session.expires > Date() else { throw AEError("Authentication required") }
        if mutation { guard let csrf, constantTimeEqual(Data(csrf.utf8), Data(session.csrf.utf8)) else { throw AEError("CSRF token required") } }
        return session
    }
    /// Pins belong to the administrator's current credentials, independently of browser logins.
    public func isCurrentOwner(_ owner: String) -> Bool {
        guard let data = try? Data(contentsOf: file) else { return false }
        return revision(data) == owner
    }
    public func logout(_ token: String) { sessions.removeValue(forKey: token) }
}
