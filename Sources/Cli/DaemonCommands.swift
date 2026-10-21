import Core
import Foundation

enum DaemonCommands {
    static func run(_ args: [String], store: ConfigStore) async throws {
        guard args.count == 4, args[0] == "pair", args[2] == "--file" else { throw AEError("Use daemon pair HOST --file FILE") }
        let data = try Data(contentsOf: URL(fileURLWithPath: args[3]))
        guard data.count <= 32768 else { throw AEError("Pairing file exceeds 32 KiB") }
        try await pair(JSONDecoder().decode(DaemonPairing.self, from: data), host: args[1], store: store)
    }
    static func pair(_ pairing: DaemonPairing, host name: String, store: ConfigStore) async throws {
        try pairing.validate()
        let snapshot = try await store.read(); var config = snapshot.config
        let index = config.hosts.firstIndex { $0.id == name }
        if let index, config.hosts[index].isLocal { throw AEError("Keep the central local host local; choose a different host name") }
        let connection = DaemonConnection(pairing: pairing)
        do {
            let response = try await connection.request(DaemonMessage(operation: "execute", script: "printf aelab-daemon-ready", timeout: 5))
            guard response.result?.status == 0, response.result?.output == "aelab-daemon-ready" else { throw AEError("Daemon readiness check failed") }
        } catch { await connection.close(); throw error }
        await connection.close()
        let id = UUID().uuidString.lowercased()
        let home = await store.home
        try pairing.save(home: home, id: id)
        var saved = false; defer { if !saved { try? FileManager.default.removeItem(at: DaemonPairing.file(home: home, id: id)) } }
        if let index { config.hosts[index].transport = .daemon; config.hosts[index].daemon = id }
        else { var host = Host(name: name, transport: .daemon); host.daemon = id; config.hosts.append(host) }
        try await store.write(config, expected: snapshot.revision); saved = true
        try await store.audit("daemon-pair", host: index.map { config.hosts[$0].id } ?? nameID(name), target: id, outcome: "paired", initiator: "local-cli")
        print("Daemon paired: \(name). Direct TLS execution is active; connection ID \(id).")
    }
}
