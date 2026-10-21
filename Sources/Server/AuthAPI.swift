import Core
import Hummingbird

struct AuthAPI: Sendable {
    let auth: Authentication
    let terminals: TerminalRegistry
    let origin: String
    let insecure: Bool
    let cookiePath: String

    func register(on router: Router<BasicRequestContext>) {
        router.get("/api/auth/session") { request, _ in
            do { let session = try await authorize(request, auth: auth, origin: origin); return try json(["csrf": session.csrf]) }
            catch { return failure(error) }
        }
        router.post("/api/auth/session") { request, _ in
            guard request.headers[.origin] == origin else { return failure(APIError(status: .forbidden, code: "origin_rejected", message: "Origin rejected")) }
            do {
                struct Login: Decodable { let password: String }
                let body = try await decode(Login.self, request)
                let session: LoginSession
                do { session = try await auth.login(body.password) }
                catch { throw APIError(status: .unauthorized, code: "login_failed", message: "Login failed or rate limited") }
                var response = try json(["csrf": session.csrf])
                response.headers[.setCookie] = "aelab=\(session.token); Path=\(cookiePath); HttpOnly; SameSite=Strict; Max-Age=43200" + (insecure ? "" : "; Secure")
                return response
            } catch { return failure(error) }
        }
        router.delete("/api/auth/session") { request, _ in
            do {
                _ = try await authorize(request, auth: auth, origin: origin, mutation: true)
                await terminals.close(owner: cookie(request) ?? "")
                await auth.logout(cookie(request) ?? "")
                var response = try json(["ok": true]); response.headers[.setCookie] = "aelab=; Path=\(cookiePath); HttpOnly; SameSite=Strict; Max-Age=0" + (insecure ? "" : "; Secure"); return response
            } catch { return failure(error) }
        }
    }
}
