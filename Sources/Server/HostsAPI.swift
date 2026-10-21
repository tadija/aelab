import Core
import Foundation
import Hummingbird

struct HostsAPI: Sendable {
    let store: ConfigStore
    let auth: Authentication
    let origin: String
    let operations: Operations
    let terminals: TerminalRegistry

    private func handle(_ request: Request, mutation: Bool = false, operation: @Sendable (LoginSession) async throws -> Response) async -> Response {
        do {
            let session = try await authorize(request, auth: auth, origin: origin, mutation: mutation)
            return try await operation(session)
        } catch { return failure(error) }
    }

    func register(on router: Router<BasicRequestContext>) {
        let sources = PluginSources(store: store)
        router.patch("/api/hosts/{host}/tmux/sessions/{session}") { request, context in
            await handle(request, mutation: true) { _ in
                struct Rename: Decodable { let name: String }
                let value = try await decode(Rename.self, request)
                return try json(await operations.renameSession(host: context.parameters.get("host")!, session: context.parameters.get("session")!, name: value.name))
            }
        }
        router.delete("/api/hosts/{host}/tmux/sessions/{session}") { request, context in
            await handle(request, mutation: true) { _ in
                return try json(await operations.killSession(host: context.parameters.get("host")!, session: context.parameters.get("session")!))
            }
        }
        router.get("/api/hosts/{host}/directories") { request, context in
            await handle(request) { _ in
                let path = request.uri.queryParameters["path"].map(String.init) ?? "~"
                return try json(await operations.directories(host: context.parameters.get("host")!, path: path))
            }
        }
        router.get("/api/hosts/{host}/plugins/{plugin}/source/deployment") { request, context in
            await handle(request) { _ in
                guard let source = request.uri.queryParameters["from"].map(String.init) else { throw AEError("A local source host is required") }
                return try json(await sources.deployment(host: context.parameters.get("host")!, plugin: context.parameters.get("plugin")!, from: source))
            }
        }
        router.post("/api/hosts/{host}/plugins/{plugin}/source/deployment") { request, context in
            await handle(request, mutation: true) { _ in
                let plan = try await decode(PluginDeployment.self, request)
                _ = try await sources.deploy(host: context.parameters.get("host")!, plugin: context.parameters.get("plugin")!, plan: plan)
                return try json(["ok": true])
            }
        }
        router.get("/api/hosts/{host}/plugins/{plugin}/source") { request, context in
            await handle(request) { _ in
                return try json(await sources.read(host: context.parameters.get("host")!, plugin: context.parameters.get("plugin")!))
            }
        }
        router.post("/api/hosts/{host}/plugins/{plugin}/source/validation") { request, context in
            await handle(request, mutation: true) { _ in
                let document = try await decode(ConfigDocument.self, request)
                _ = try await sources.edit(host: context.parameters.get("host")!, plugin: context.parameters.get("plugin")!, document: document, save: false)
                return try json(["valid": true])
            }
        }
        router.put("/api/hosts/{host}/plugins/{plugin}/source") { request, context in
            await handle(request, mutation: true) { _ in
                let document = try await decode(ConfigDocument.self, request)
                return try json(await sources.edit(host: context.parameters.get("host")!, plugin: context.parameters.get("plugin")!, document: document, save: true))
            }
        }
        router.post("/api/hosts/{host}/projects") { request, context in
            await handle(request, mutation: true) { _ in
                let project = try await decode(Project.self, request)
                try await operations.prepareProject(host: context.parameters.get("host")!, project: project)
                return try json(["ok": true])
            }
        }
        router.get("/api/hosts/{host}/tools") { request, context in
            await handle(request) { _ in
                return try json(await operations.discoverTools(context.parameters.get("host")!))
            }
        }
        router.post("/api/hosts/{host}/tools") { request, context in
            await handle(request, mutation: true) { _ in
                return try json(await operations.discoverTools(context.parameters.get("host")!, refresh: true))
            }
        }
        router.get("/api/hosts/{host}/plugins") { request, context in
            await handle(request) { _ in
                return try json(await operations.discoverPlugins(host: context.parameters.get("host")!))
            }
        }
        router.post("/api/hosts/{host}/plugins/{plugin}/runs") { request, context in
            await handle(request, mutation: true) { _ in
                return try json(await operations.probePlugin(host: context.parameters.get("host")!, plugin: context.parameters.get("plugin")!))
            }
        }
        router.get("/api/hosts/{host}/status") { request, context in
            await handle(request) { _ in
                return try json(await operations.observe(context.parameters.get("host")!))
            }
        }
        router.get("/api/hosts/{host}/services/{service}") { request, context in
            await handle(request) { _ in
                return try json(await operations.service(context.parameters.get("host")!, id: context.parameters.get("service")!, operation: "status"))
            }
        }
        router.get("/api/hosts/{host}/services/{service}/logs") { request, context in
            await handle(request) { _ in
                return try json(await operations.service(context.parameters.get("host")!, id: context.parameters.get("service")!, operation: "logs"))
            }
        }
        router.post("/api/hosts/{host}/services/{service}/actions") { request, context in
            await handle(request, mutation: true) { _ in
                let body = try await decode(ServiceAction.self, request)
                return try json(await operations.service(context.parameters.get("host")!, id: context.parameters.get("service")!, operation: body.action.rawValue))
            }
        }
        router.get("/api/hosts/{host}/terminals") { request, context in
            await handle(request) { session in
                let host = context.parameters.get("host")!; _ = try await store.read().config.host(host)
                return try json(await terminals.pinned(host: host, owner: session.token))
            }
        }
        router.delete("/api/hosts/{host}/terminals/{terminal}") { request, context in
            await handle(request, mutation: true) { session in
                let host = context.parameters.get("host")!, id = context.parameters.get("terminal")!
                _ = try await store.read().config.host(host)
                try await terminals.closePinned(id, host: host, owner: session.token)
                try await store.audit("terminal-delete", host: host, target: id, outcome: "closed")
                return try json(["ok": true])
            }
        }
        router.post("/api/hosts/{host}/terminal-tickets") { request, context in
            await handle(request, mutation: true) { session in
                var launch = try await decode(TerminalRequest.self, request).launch(host: context.parameters.get("host")!)
                let config = try await store.read().config
                if let pinned = launch.pinned {
                    _ = try config.host(launch.host)
                    _ = try await terminals.retained(pinned, host: launch.host, owner: session.token)
                    return try json(TerminalTicket(ticket: await terminals.issue(launch, owner: session.token), session: nil, prefix: "C-b"))
                }
                if launch.session == nil, launch.tool == nil, launch.persistent != false,
                   config.hosts.first(where: { $0.id == launch.host })?.projects.first(where: { $0.id == launch.project })?.session != nil { launch.persistent = true }
                try await operations.validateLaunch(launch, config: config)
                let (host, _, name) = try launch.resolve(config); launch.session = name
                var prefix = "C-b"
                if name != nil {
                    let result = try await operations.execution.run(host, args: ["tmux", "display-message", "-p", "-t", "=" + (name ?? "") + ":", "#{prefix}"], timeout: 5)
                    if result.status == 0, !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { prefix = result.output.trimmingCharacters(in: .whitespacesAndNewlines) }
                }
                let id = try await terminals.issue(launch, owner: session.token)
                return try json(TerminalTicket(ticket: id, session: name, prefix: prefix))
            }
        }
        router.post("/api/hosts/{host}/tmux/sessions/{session}/windows") { request, context in
            await handle(request, mutation: true) { _ in
                var launch = try await decode(TerminalRequest.self, request).launch(host: context.parameters.get("host")!)
                guard launch.session == nil, launch.pinned == nil, launch.window == nil, launch.persistent != true else { throw AEError("Window requests cannot specify session, pinned, window or persistent creation") }
                let session = context.parameters.get("session")!; launch.session = session
                return try json(await operations.tmuxWindow(launch, session: session))
            }
        }
    }
}
