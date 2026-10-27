import Core
import Foundation
import Hummingbird

struct ConfigurationAPI: Sendable {
    let store: ConfigStore
    let auth: Authentication
    let origin: String
    let terminals: TerminalRegistry
    private func sourceFormat(_ request: Request) throws -> Bool {
        switch request.uri.queryParameters["format"] {
        case nil, "json": return false
        case "source": return true
        default: throw AEError("format must be json or source")
        }
    }
    private func handle(_ request: Request, mutation: Bool = false, operation: @Sendable () async throws -> Response) async -> Response {
        do {
            _ = try await authorize(request, auth: auth, origin: origin, mutation: mutation)
            return try await operation()
        } catch { return failure(error) }
    }
    func register(on router: Router<BasicRequestContext>) {
        router.get("/api/config") { request, _ in
            await handle(request) {
                if try sourceFormat(request) { return try json(await store.readDocument()) }
                return try json(await store.read())
            }
        }
        router.put("/api/config") { request, _ in
            await handle(request, mutation: true) {
                let source = try sourceFormat(request)
                let previous = try? await store.read().config
                try await store.audit("config", host: "central", target: "aelab.json", outcome: "requested")
                if source {
                    try await store.writeDocument(try await decode(ConfigDocument.self, request))
                } else {
                    let snapshot = try await decode(ConfigSnapshot.self, request)
                    try await store.write(snapshot.config, expected: snapshot.revision)
                }
                let current = try await store.read().config
                if let previous { try await terminals.renameHosts(previous.renamedHosts(to: current)) }
                try await terminals.retainHosts(Set(current.hosts.map(\.id)))
                try await store.audit("config", host: "central", target: "aelab.json", outcome: "saved")
                if source { return try json(await store.readDocument()) }
                return try json(await store.read())
            }
        }
        router.post("/api/config/validation") { request, _ in
            await handle(request, mutation: true) {
                struct Draft: Decodable { let content: String }
                let draft = try await decode(Draft.self, request)
                _ = try ConfigStore.validateDocument(draft.content)
                return try json(["valid": true])
            }
        }
    }
}
