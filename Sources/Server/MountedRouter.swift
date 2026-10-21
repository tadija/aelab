import Core
import Hummingbird

/// Mount the HTTP and WebSocket routers at the same literal prefix.
struct MountedRouter<Context: RequestContext>: HTTPResponderBuilder {
    let router: Router<Context>
    let base: WebBasePath
    func buildResponder() -> MountedResponder<Context> { .init(router: router.buildResponder(), base: base) }
}
struct MountedResponder<Context: RequestContext>: HTTPResponder {
    let router: RouterResponder<Context>
    let base: WebBasePath
    func respond(to request: Request, context: Context) async throws -> Response {
        guard let path = base.relative(request.uri.path) else { return Response(status: .notFound) }
        let raw = request.head.path ?? request.uri.path
        let query = raw.firstIndex(of: "?").map { String(raw[$0...]) } ?? ""
        if path.isEmpty {
            guard request.method == .get || request.method == .head else { return Response(status: .notFound) }
            return Response(status: .permanentRedirect, headers: [.location: base.root + query])
        }
        var head = request.head; head.path = path + query
        return try await router.respond(to: Request(head: head, body: request.body), context: context)
    }
}
