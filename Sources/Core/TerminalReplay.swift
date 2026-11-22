import Foundation

/// Preserve scrolling modes established before the retained output window.
struct TerminalReplay {
    private let limit: Int
    private var bytes = Data()
    private var modes = Set<Int>()
    private enum State { case ground, escape, csi, string, stringEscape }
    private var state = State.ground
    private var parameters = [UInt8]()
    private var stringIntroducer: UInt8 = 93
    // Each group selects a single xterm state. Resetting any alias clears the group.
    private static let modeGroups = [[1], [9, 1000, 1002, 1003], [1006, 1016], [47, 1047, 1049]]

    init(limit: Int = 262_144) { self.limit = limit }

    mutating func append(_ data: Data) {
        bytes.append(data)
        guard bytes.count > limit else { return }
        var boundary = bytes.startIndex + bytes.count - limit
        for byte in bytes[..<boundary] { consume(byte) }
        // Start replay between escape sequences, even when one crosses the cut.
        while state != .ground && boundary < bytes.endIndex {
            consume(bytes[boundary])
            boundary += 1
        }
        bytes = Data(bytes[boundary...])
    }

    var snapshot: Data {
        var result = Data()
        for mode in modes.sorted() { result.append(contentsOf: "\u{1b}[?\(mode)h".utf8) }
        // A control string may have spanned the entire retained window.
        switch state {
        case .escape: result.append(27)
        case .csi: result.append(contentsOf: [27, 91] + parameters)
        case .string, .stringEscape:
            result.append(contentsOf: [27, stringIntroducer])
            if state == .stringEscape { result.append(27) }
        case .ground: break
        }
        result.append(bytes)
        return result
    }

    private mutating func consume(_ byte: UInt8) {
        switch state {
        case .ground: if byte == 27 { state = .escape }
        case .escape:
            switch byte {
            case 91: state = .csi; parameters.removeAll(keepingCapacity: true)
            case 80, 88, 93, 94, 95: stringIntroducer = byte; state = .string
            case 99: modes.removeAll(); state = .ground
            default: state = byte == 27 ? .escape : .ground
            }
        case .csi:
            if (64...126).contains(byte) {
                if parameters.first == 63, byte == 104 || byte == 108 {
                    for field in parameters.dropFirst().split(separator: 59) {
                        guard let mode = Int(String(decoding: field, as: UTF8.self)), let group = Self.modeGroups.first(where: { $0.contains(mode) }) else { continue }
                        modes.subtract(group)
                        if byte == 104 { modes.insert(mode) }
                    }
                }
                state = .ground
            } else if byte == 27 { state = .escape }
            else if parameters.count < 128 { parameters.append(byte) }
        case .string: if byte == 7 { state = .ground } else if byte == 27 { state = .stringEscape }
        case .stringEscape: state = byte == 92 ? .ground : .string
        }
    }
}
