import Foundation

public struct ProgramStatus: Codable, Sendable, Equatable {
    public var id: String
    public var state: String
    public var app: String?
    public var title: String?
    public var msg: String?
    public var kind: String?
    public var progress: Int?
}

/// Bounded OSC observer; PTY bytes still pass unchanged to every terminal client.
struct ProgramStatusObserver: Sendable {
    private enum Mode { case ground, escape, osc, oscEscape, discard, discardEscape, string, stringEscape }
    private var mode = Mode.ground
    private var buffer = Data()
    private var records: [ProgramStatus] = []
    private static let priorities = ["blocked": 0, "error": 1, "working": 2, "done": 3, "idle": 4]

    var primary: ProgramStatus? {
        guard var record = records.reversed().min(by: { Self.priorities[$0.state, default: 5] < Self.priorities[$1.state, default: 5] }) else { return nil }
        var parent = record.id
        while record.app == nil && !parent.isEmpty {
            parent = parent.lastIndex(of: "/").map { String(parent[..<$0]) } ?? ""
            record.app = records.first(where: { $0.id == parent })?.app
        }
        return record
    }
    mutating func commandFinished() { records.removeAll { ["working", "blocked"].contains($0.state) } }
    mutating func acknowledge() { records.removeAll { ["done", "error"].contains($0.state) } }
    mutating func feed(_ data: Data) {
        for byte in data {
            if byte == 0x18 || byte == 0x1a { mode = .ground; buffer.removeAll(keepingCapacity: true); continue }
            switch mode {
            case .ground: if byte == 0x1b { mode = .escape }
            case .escape:
                switch byte {
                case 0x5d: buffer.removeAll(keepingCapacity: true); mode = .osc
                case 0x50, 0x5f, 0x5e: mode = .string
                case 0x63: records.removeAll(); mode = .ground
                case 0x1b: break
                default: mode = .ground
                }
            case .osc:
                if byte == 7 { finish(); mode = .ground }
                else if byte == 0x1b { mode = .oscEscape }
                else if buffer.count < 4092 { buffer.append(byte) }
                else { buffer.removeAll(keepingCapacity: true); mode = .discard }
            case .oscEscape:
                if byte == 0x5c { finish(); mode = .ground }
                else { buffer.removeAll(keepingCapacity: true); mode = .escape; feed(Data([byte])) }
            case .discard:
                if byte == 7 { mode = .ground }
                else if byte == 0x1b { mode = .discardEscape }
            case .discardEscape: mode = byte == 0x5c || byte == 7 ? .ground : .discard
            case .string: if byte == 0x1b { mode = .stringEscape }
            case .stringEscape: mode = byte == 0x5c ? .ground : .string
            }
        }
    }
    private mutating func finish() {
        defer { buffer.removeAll(keepingCapacity: true) }
        guard let value = String(data: buffer, encoding: .utf8) else { return }
        if value == "133;A" || value.hasPrefix("133;A;") { commandFinished(); return }
        guard value.hasPrefix("7501;"), let report = Self.parse(String(value.dropFirst(5))) else { return }
        if report.state == "clear" {
            records.removeAll { report.id.isEmpty || $0.id == report.id || $0.id.hasPrefix(report.id + "/") }
        } else {
            records.removeAll { $0.id == report.id }
            if records.count >= 256 { records.removeFirst() }
            records.append(report)
        }
    }
    private static func matches(_ value: String, _ pattern: String) -> Bool { value.range(of: pattern, options: .regularExpression) != nil }
    private static func text(_ value: String, encoded: Int, decoded: Int) throws -> String {
        guard value.utf8.count <= encoded,
              matches(value, "^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}(?:==)?|[A-Za-z0-9+/]{3}=?)?$"),
              let bytes = Data(base64Encoded: value + String(repeating: "=", count: (4 - value.count % 4) % 4)), bytes.count <= decoded,
              let string = String(data: bytes, encoding: .utf8),
              !string.unicodeScalars.contains(where: { $0.value < 32 || (127...159).contains($0.value) }) else { throw AEError("Invalid program status text") }
        return String(String.UnicodeScalarView(string.unicodeScalars.filter { $0.properties.generalCategory != .format }))
    }
    private static func parse(_ body: String) -> ProgramStatus? {
        guard body.utf8.count + 9 <= 4096 else { return nil }
        var fields: [String: String] = [:]
        do {
            for pair in body.split(separator: ":", omittingEmptySubsequences: false) {
                guard let separator = pair.firstIndex(of: "=") else { continue }
                let key = String(pair[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(pair[pair.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard matches(key, "^[a-z]+$") else { continue }
                if key == "id" && !value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ matches(String($0), "^[A-Za-z0-9_.+-]{1,32}$") }) { return nil }
                guard matches(value, "^[A-Za-z0-9_.,+/=-]*$") else { continue }
                guard key.count <= 16 else { return nil }
                switch key {
                case "msg": _ = try text(value, encoded: 2732, decoded: 2048)
                case "title": _ = try text(value, encoded: 256, decoded: 192)
                case "app": if value.count > 32 { return nil }
                case "id": if value.count > 128 || value.split(separator: "/").count > 8 { return nil }
                default: break
                }
                fields[key] = value
            }
            guard let state = fields["state"], state == "clear" || priorities[state] != nil else { return nil }
            var record = ProgramStatus(id: fields["id"] ?? "", state: state)
            if let app = fields["app"], matches(app, "^[A-Za-z0-9_.+-]{1,32}$") { record.app = app }
            if let title = fields["title"] { record.title = try text(title, encoded: 256, decoded: 192) }
            if let msg = fields["msg"] { record.msg = try text(msg, encoded: 2732, decoded: 2048) }
            if state == "blocked", let kind = fields["kind"], ["permission", "question", "auth"].contains(kind) { record.kind = kind }
            if ["working", "blocked"].contains(state), let value = fields["progress"], matches(value, "^[0-9]+$"), let progress = Int(value), (0...100).contains(progress) { record.progress = progress }
            return record
        } catch { return nil }
    }
}
