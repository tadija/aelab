import Core
import Foundation
import Hummingbird
import HummingbirdWebSocket
import HTTPTypes

@main struct Server {
    static func main() async throws {
        if Array(CommandLine.arguments.dropFirst()) == ["--version"] { print(AelabVersion.display); return }
        if Array(CommandLine.arguments.dropFirst()) == ["--build"] { print(AelabVersion.build); return }
        let env = ProcessInfo.processInfo.environment
        let home = URL(fileURLWithPath: env["AELAB_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".aelab").path)
        let store = try ConfigStore(home: home); _ = try await store.read()
        let auth = Authentication(home: home); let operations = Operations(store: store); let terminals = try TerminalRegistry(home: home)
        try await terminals.retainHosts(Set(try await store.read().config.hosts.map(\.id)))
        try await terminals.reap { await auth.isCurrentOwner($0) }
        guard let port = Int(env["AELAB_PORT"] ?? "2108"), (1...65535).contains(port) else { throw AEError("Invalid AELAB_PORT") }
        let origin = env["AELAB_ORIGIN"] ?? "http://localhost:\(port)"
        guard let originURL = URL(string: origin), let scheme = originURL.scheme, ["http", "https"].contains(scheme), originURL.host != nil, originURL.path.isEmpty else { throw AEError("AELAB_ORIGIN must be an exact HTTP(S) origin without trailing slash") }
        let insecure = scheme == "http"
        let bind = env["AELAB_BIND"] ?? "127.0.0.1"
        guard !insecure || (["localhost", "127.0.0.1", "::1"].contains(originURL.host!) && ["localhost", "127.0.0.1", "::1"].contains(bind)) else { throw AEError("Non-loopback origins require HTTPS") }
        let base = try WebBasePath(env["AELAB_BASE_PATH"] ?? "")
        let assets = try DashboardAssets(directory: env["AELAB_PUBLIC"] ?? RuntimePaths.publicDirectory)
        let router = Router()
        router.get("/health") { _, _ in Response(status: .ok, body: .init(byteBuffer: .init(string: "ok"))) }
        AuthAPI(auth: auth, terminals: terminals, origin: origin, insecure: insecure, cookiePath: base.root).register(on: router)
        TerminalFilesAPI(store: store, auth: auth, origin: origin, terminals: terminals, execution: operations.execution).register(on: router)
        router.get("/api/docs/openapi.json") { request, _ in
            do {
                _ = try await authorize(request, auth: auth, origin: origin)
                var headers = HTTPFields(); headers[.contentType] = "application/json"; headers[.cacheControl] = "no-store"
                var document = try JSONSerialization.jsonObject(with: APIDocument.data) as! [String: Any]
                document["servers"] = [["url": base.value.isEmpty ? "/" : base.value]]
                return Response(status: .ok, headers: headers, body: .init(byteBuffer: .init(bytes: try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys]))))
            } catch { return failure(error) }
        }
        router.get("/api/docs") { request, _ in
            do {
                _ = try await authorize(request, auth: auth, origin: origin)
                var headers = HTTPFields(); headers[.contentType] = "text/html; charset=utf-8"; headers[.cacheControl] = "no-store"
                return Response(status: .ok, headers: headers, body: .init(byteBuffer: .init(string: APIReference.html(base: base.value))))
            } catch { return failure(error) }
        }
        router.get("/api/state/sections") { request, _ in
            do { _ = try await authorize(request, auth: auth, origin: origin); return try json(await store.sectionState()) }
            catch { return failure(error) }
        }
        router.put("/api/state/sections") { request, _ in
            do {
                _ = try await authorize(request, auth: auth, origin: origin, mutation: true)
                struct State: Decodable { let host: String; let sections: [String: Bool] }
                let state = try await decode(State.self, request)
                try await store.saveSections(host: state.host, sections: state.sections)
                return try json(["ok": true])
            } catch { return failure(error) }
        }
        ConfigurationAPI(store: store, auth: auth, origin: origin, terminals: terminals).register(on: router)
        HostsAPI(store: store, auth: auth, origin: origin, operations: operations, terminals: terminals).register(on: router)
        // Serve external compiled assets, with SPA routing for meaningful host/project/terminal URLs.
        let staticHandler: @Sendable (Request, BasicRequestContext) async throws -> Response = { request, _ in
            var path = request.uri.path.removingPercentEncoding ?? request.uri.path
            guard !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }), !path.contains("\0"), !path.hasPrefix("/api/"), !path.hasPrefix("/ws/") else { return Response(status: .notFound) }
            if path == "/" || path.hasPrefix("/hosts/") || !path.split(separator: "/").last!.contains(".") { path = "/index.html" }
            guard var data = assets.data(for: path) else { return Response(status: .notFound) }
            if path == "/index.html" {
                data = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "<base href=\"/\">", with: "<base href=\"" + base.root + "\">").utf8)
            }
            let types = ["html": "text/html; charset=utf-8", "js": "text/javascript", "css": "text/css", "svg": "image/svg+xml", "png": "image/png", "woff2": "font/woff2"]
            var headers = HTTPFields(); headers[.contentType] = types[URL(fileURLWithPath: path).pathExtension] ?? "application/octet-stream"
            headers[.cacheControl] = ["/index.html", "/theme.css"].contains(path) ? "no-store" : "public, max-age=3600"
            headers[HTTPField.Name("X-Content-Type-Options")!] = "nosniff"
            headers[HTTPField.Name("Content-Security-Policy")!] = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
            return Response(status: .ok, headers: headers, body: .init(byteBuffer: .init(bytes: data)))
        }
        router.get("/", use: staticHandler)
        router.get("/**", use: staticHandler)
        let wsRouter = Router(context: BasicWebSocketRequestContext.self)
        TerminalWebSocket(store: store, auth: auth, origin: origin, operations: operations, terminals: terminals).register(on: wsRouter)
        let app = Application(responder: MountedRouter(router: router, base: base).buildResponder(), server: .http1WebSocketUpgrade(webSocketRouter: MountedRouter(router: wsRouter, base: base)), configuration: .init(address: .hostname(bind, port: port)))
        let reaper = Task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { break }
                do { try await terminals.reap { await auth.isCurrentOwner($0) } }
                catch { print("Cannot update terminal state: \(error)") }
            }
        }
        defer { reaper.cancel() }
        do { try await app.runService() } catch { await terminals.closeAll(); throw error }
        await terminals.closeAll()
    }
}
