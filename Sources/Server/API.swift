import Core
import Foundation
import Hummingbird
import HTTPTypes

func cookie(_ request: Request) -> String? {
    request.headers[.cookie]?.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.first(where: { $0.hasPrefix("aelab=") }).map { String($0.dropFirst(6)) }
}
func authorize(_ request: Request, auth: Authentication, origin: String, mutation: Bool = false, websocket: Bool = false) async throws -> LoginSession {
    if mutation || websocket { guard request.headers[.origin] == origin else { throw APIError(status: .forbidden, code: "origin_rejected", message: "Origin rejected") } }
    let session: LoginSession
    do { session = try await auth.authorize(token: cookie(request)) }
    catch { throw APIError(status: .unauthorized, code: "authentication_required", message: "Authentication required") }
    if mutation {
        guard let csrf = request.headers[HTTPField.Name("X-CSRF-Token")!], constantTimeEqual(Data(csrf.utf8), Data(session.csrf.utf8)) else { throw APIError(status: .forbidden, code: "csrf_required", message: "CSRF token required") }
    }
    return session
}
func decode<T: Decodable>(_ type: T.Type, _ request: Request) async throws -> T { let buffer = try await request.body.collect(upTo: 1_048_576); return try JSONDecoder().decode(type, from: Data(buffer.readableBytesView)) }
func json<T: Encodable>(_ value: T) throws -> Response {
    let data = try JSONEncoder().encode(value); var headers = HTTPFields(); headers[.contentType] = "application/json"; headers[.cacheControl] = "no-store"
    return Response(status: .ok, headers: headers, body: .init(byteBuffer: .init(bytes: data)))
}
struct APIError: Error, CustomStringConvertible {
    let status: HTTPResponse.Status
    let code: String
    let message: String
    var description: String { message }
}
func failure(_ error: Error) -> Response {
    let status = (error as? APIError)?.status ?? (error is RevisionConflict ? .conflict : .badRequest)
    let code = (error as? APIError)?.code ?? (error is RevisionConflict ? "revision_conflict" : "invalid_request")
    return (try? json(["error": ["code": code, "message": String(describing: error)]])).map { var response = $0; response.status = status; return response } ?? Response(status: .internalServerError)
}
