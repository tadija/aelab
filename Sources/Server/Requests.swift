import Core
import Foundation

/// Host identity belongs to the URL, never to an independently supplied body field.
struct TerminalRequest: Decodable, Sendable {
    let project: String?
    let tool: String?
    let session: String?
    let pinned: String?
    let directory: String?
    let persistent: Bool?
    let yolo: Bool?
    let window: String?
    enum CodingKeys: String, CodingKey, CaseIterable { case project, tool, session, pinned, directory, persistent, yolo, window }
    private struct Key: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    init(from decoder: any Decoder) throws {
        let keys = try decoder.container(keyedBy: Key.self).allKeys.map(\.stringValue)
        guard Set(keys).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))) else { throw AEError("Unknown terminal request field") }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        project = try c.decodeIfPresent(String.self, forKey: .project)
        tool = try c.decodeIfPresent(String.self, forKey: .tool)
        session = try c.decodeIfPresent(String.self, forKey: .session)
        pinned = try c.decodeIfPresent(String.self, forKey: .pinned)
        directory = try c.decodeIfPresent(String.self, forKey: .directory)
        persistent = try c.decodeIfPresent(Bool.self, forKey: .persistent)
        yolo = try c.decodeIfPresent(Bool.self, forKey: .yolo)
        window = try c.decodeIfPresent(String.self, forKey: .window)
    }
    func launch(host: String) -> TerminalLaunch {
        var launch = TerminalLaunch(host: host, project: project, tool: tool, session: session, persistent: persistent, yolo: yolo)
        launch.pinned = pinned; launch.directory = directory; launch.window = window
        return launch
    }
}
struct TerminalTicket: Encodable, Sendable {
    let ticket: String
    let session: String?
    let prefix: String
}
struct ServiceAction: Decodable, Sendable {
    enum Action: String, Decodable, Sendable { case start, stop, restart }
    let action: Action
}
