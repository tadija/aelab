import Core
import Foundation
import Hummingbird
import HummingbirdWebSocket

struct TerminalWebSocket: Sendable {
    let store: ConfigStore
    let auth: Authentication
    let origin: String
    let operations: Operations
    let terminals: TerminalRegistry

    func register(on router: Router<BasicWebSocketRequestContext>) {
        router.ws("/ws/terminals/{ticket}") { request, _ in
            do { _ = try await authorize(request, auth: auth, origin: origin, websocket: true); return .upgrade() }
            catch { return .dontUpgrade }
        } onUpgrade: { inbound, outbound, context in
            var live: LiveTerminal?; var subscription: UUID?; var acquired = false
            do {
                let session = try await authorize(context.request, auth: auth, origin: origin, websocket: true)
                let ticket = String(context.request.uri.path.split(separator: "/").last ?? "")
                let launch = try await terminals.consume(ticket, owner: session.token); acquired = true
                let config = try await store.read().config
                let host = try config.host(launch.host)
                let terminal: LiveTerminal
                if let id = launch.pinned { terminal = try await terminals.retained(id, host: host.id, owner: session.token) }
                else {
                    let (_, script, name) = try launch.resolve(config)
                    let project = host.projects.first { $0.id == launch.project }
                    let tool = config.enabledTools(host).first { $0.id == launch.tool }
                    var cwd = launch.directory ?? project?.directory ?? tool?.directory ?? ""
                    if cwd.isEmpty {
                        let result = try await operations.execution.run(host, args: ["pwd"], timeout: 5)
                        if result.status == 0 { cwd = result.output.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                    let pty = try await operations.execution.terminal(host, script: script)
                    terminal = LiveTerminal(pty: pty, owner: session.token, expires: session.expires, launch: launch, cwd: cwd, identity: try? await operations.identity(host))
                    do { try await terminals.register(terminal) } catch { await terminal.close(); throw error }
                    live = terminal
                    try await store.audit("terminal", host: host.id, target: name ?? launch.project ?? launch.tool ?? "shell", outcome: "opened")
                }
                live = terminal
                let (id, stream, replay) = try await terminal.subscribe(); subscription = id
                await terminal.start()
                try await outbound.write(.text(String(decoding: JSONEncoder().encode(await terminal.metadata()), as: UTF8.self)))
                if !replay.isEmpty {
                    try await outbound.write(.text("{\"type\":\"replay\"}"))
                    try await outbound.write(.binary(.init(bytes: replay)))
                }
                let name = await terminal.launch.session
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        var prefixSent = name == nil; var prefixAttempts = 0
                        for await data in stream {
                            try Task.checkCancellation()
                            try await outbound.write(.binary(.init(bytes: data)))
                            if !prefixSent && prefixAttempts < 3 {
                                prefixAttempts += 1
                                let result = try await operations.execution.run(host, args: ["tmux", "display-message", "-p", "-t", "=" + (name ?? "") + ":", "#{prefix}"], timeout: 5)
                                if result.status == 0 {
                                    try await outbound.write(.text(String(decoding: JSONEncoder().encode(["type": "tmux-prefix", "prefix": result.output.trimmingCharacters(in: .whitespacesAndNewlines)]), as: UTF8.self)))
                                    prefixSent = true
                                }
                            }
                        }
                    }
                    group.addTask {
                        for try await message in inbound.messages(maxSize: 65536) {
                            _ = try await auth.authorize(token: session.token)
                            switch message {
                            case .text(let string):
                                struct Control: Decodable { var type: String; var cols: Int?; var rows: Int?; var data: String? }
                                let control = try JSONDecoder().decode(Control.self, from: Data(string.utf8))
                                switch control.type {
                                case "input": try await terminal.input(Data((control.data ?? "").utf8))
                                case "resize": try await terminal.resize(cols: control.cols ?? 80, rows: control.rows ?? 24)
                                case "signal": try await terminal.signal(control.data ?? "")
                                case "pin", "unpin":
                                    try await terminals.setPinned(terminal, value: control.type == "pin")
                                    try await store.audit("terminal-" + control.type, host: host.id, target: terminal.id, outcome: "changed")
                                    try await outbound.write(.text(String(decoding: JSONEncoder().encode(await terminal.metadata()), as: UTF8.self)))
                                default: throw AEError("Unsupported terminal message")
                                }
                            case .binary(let buffer): try await terminal.input(Data(buffer.readableBytesView))
                            }
                        }
                    }
                    group.addTask { while true { try await Task.sleep(for: .seconds(15)); _ = try await auth.authorize(token: session.token) } }
                    do { _ = try await group.next() } catch { await terminal.detach(id); group.cancelAll(); throw error }
                    await terminal.detach(id); group.cancelAll()
                }
            } catch { try? await outbound.write(.text("Terminal closed: \(error)")) }
            if let live { if let subscription { await live.detach(subscription) } else { await live.close() } }
            if acquired { await terminals.release() }
        }
    }
}
