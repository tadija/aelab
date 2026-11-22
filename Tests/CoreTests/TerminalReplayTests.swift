import Foundation
import Testing
@testable import Core

@Test func retainedTerminalRestoresScrollingModesAfterHistoryRollsOver() {
    var replay = TerminalReplay(limit: 12)
    replay.append(Data("\u{1b}[?1049h\u{1b}[?1000;1006h".utf8))
    replay.append(Data(repeating: 65, count: 24))
    #expect(String(decoding: replay.snapshot, as: UTF8.self) == "\u{1b}[?1000h\u{1b}[?1006h\u{1b}[?1049hAAAAAAAAAAAA")
    replay.append(Data("\u{1b}[?1049l\u{1b}[?1000;1006l".utf8))
    replay.append(Data(repeating: 66, count: 24))
    #expect(replay.snapshot == Data(repeating: 66, count: 12))
}
