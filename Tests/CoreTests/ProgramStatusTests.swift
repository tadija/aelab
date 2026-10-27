import Foundation
import Testing
@testable import Core

private func report(_ body: String, end: String = "\u{1b}\\") -> Data { Data(("\u{1b}]7501;" + body + end).utf8) }
@Test func programStatusStreamsAcrossChunksAndPrioritizesChildren() {
    var status = ProgramStatusObserver()
    let bytes = report("state=working:app=deploy:progress=40")
    for byte in bytes { status.feed(Data([byte])) }
    #expect(status.primary?.state == "working"); #expect(status.primary?.progress == 40)
    status.feed(report("state=blocked:id=build/test:kind=permission:msg=QXBwcm92ZT8=", end: "\u{7}"))
    #expect(status.primary?.id == "build/test"); #expect(status.primary?.app == "deploy")
    #expect(status.primary?.msg == "Approve?"); #expect(status.primary?.kind == "permission")
    status.feed(report("state=clear:id=build")); #expect(status.primary?.state == "working")
    status.feed(report("state=clear")); #expect(status.primary == nil)
}
@Test func programStatusRejectsMalformedAndOversizedReportsAtomically() {
    var status = ProgramStatusObserver(); status.feed(report("state=working"))
    let invalid = ["state=done:msg=Cg==", "state=done:msg=/w==", "state=done:id=bad!id", "state=future", "state=done:title=" + String(repeating: "eA==", count: 65), "state=done:app=" + String(repeating: "x", count: 33), "state=done:" + String(repeating: "x", count: 5000)]
    for body in invalid { status.feed(report(body)); #expect(status.primary?.state == "working") }
    status.feed(report("?:states=idle,working,done,blocked,error")); #expect(status.primary?.state == "working")
    status.feed(report("state=done:msg=SGVsbG8")); #expect(status.primary?.msg == "Hello")
    status.feed(report("state=done:msg=Cg==:msg=SGVsbG8=")); #expect(status.primary?.msg == "Hello")
}
@Test func programStatusLifetimesIgnoreAlternateAndSoftResets() {
    var status = ProgramStatusObserver()
    status.feed(report("state=working")); status.feed(Data("\u{1b}[?1049h\u{1b}[?1049l\u{1b}[!p".utf8))
    #expect(status.primary?.state == "working")
    status.feed(report("state=done:id=result")); status.feed(Data("\u{1b}]133;A\u{7}".utf8))
    #expect(status.primary?.state == "done"); status.acknowledge(); #expect(status.primary == nil)
    status.feed(report("state=blocked")); status.commandFinished(); #expect(status.primary == nil)
    status.feed(report("state=error")); status.feed(Data("\u{1b}c".utf8)); #expect(status.primary == nil)
    // OSC-looking bytes inside another terminal string are not reports.
    status.feed(Data("\u{1b}P".utf8) + report("state=error")); #expect(status.primary == nil)
}
@Test func programStatusEvictsOldestAndUsesNewestAtEqualPriority() {
    var status = ProgramStatusObserver()
    for n in 0..<257 { status.feed(report("state=working:id=r\(n)")) }
    #expect(status.primary?.id == "r256")
    status.feed(report("state=clear:id=r256")); #expect(status.primary?.id == "r255")
    for n in 1..<256 { status.feed(report("state=clear:id=r\(n)")) }
    #expect(status.primary == nil)
}
