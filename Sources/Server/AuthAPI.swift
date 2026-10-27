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
            do { let session = try await authorize(request, auth: auth, origin: origin); return try json(["csrf": session.csrf, "version": AelabVersion.current, "build": AelabVersion.build]) }
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
                var response = try json(["csrf": session.csrf, "version": AelabVersion.current, "build": AelabVersion.build])
                response.headers[.setCookie] = "aelab=\(session.token); Path=\(cookiePath); HttpOnly; SameSite=Strict; Max-Age=43200" + (insecure ? "" : "; Secure")
                return response
            } catch { return failure(error) }
        }
        router.post("/api/auth/session/verify") { request, _ in
            do {
                let session = try await authorize(request, auth: auth, origin: origin, mutation: true)
                struct Verify: Decodable { let password: String }
                let body = try await decode(Verify.self, request)
                do { try await auth.verifySessionPassword(token: session.token, csrf: session.csrf, password: body.password) }
                catch { throw APIError(status: .forbidden, code: "password_rejected", message: "Password rejected or rate limited") }
                return try json(["ok": true])
            } catch { return failure(error) }
        }
        router.post("/api/auth/password") { request, _ in
            guard request.headers[.origin] == origin else { return failure(APIError(status: .forbidden, code: "origin_rejected", message: "Origin rejected")) }
            do {
                struct Change: Decodable { let password: String; let replacement: String }
                let body = try await decode(Change.self, request)
                do { try await auth.changePassword(current: body.password, replacement: body.replacement) }
                catch { throw APIError(status: .forbidden, code: "password_rejected", message: "Password change rejected; check the current password, use 12–1024 bytes for the new password, or try again later") }
                return try json(["ok": true])
            } catch { return failure(error) }
        }
        router.delete("/api/auth/session") { request, _ in
            do {
                _ = try await authorize(request, auth: auth, origin: origin, mutation: true)
                let token = cookie(request) ?? ""
                await auth.logout(token)
                await terminals.disconnect(login: token)
                var response = try json(["ok": true]); response.headers[.setCookie] = "aelab=; Path=\(cookiePath); HttpOnly; SameSite=Strict; Max-Age=0" + (insecure ? "" : "; Secure"); return response
            } catch { return failure(error) }
        }
    }
}
