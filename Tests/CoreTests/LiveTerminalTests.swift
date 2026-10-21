import Foundation
import Testing
@testable import Core

private func terminal(owner: String = "owner", host: String = "local", script: String = "printf READY; read hold", expires: Date = Date().addingTimeInterval(3600)) throws -> LiveTerminal {
    let approved = Host(name: host, transport: .local)
    return LiveTerminal(pty: try TerminalPTY(host: approved, script: script, execution: HostExecution()), owner: owner, expires: expires, launch: TerminalLaunch(host: host), cwd: "/tmp")
}
@Test func nativePinRetainsSamePTYAndIsOwnerAndHostScoped() async throws {
    let registry = TerminalRegistry(); let live = try terminal(); try await registry.register(live)
    let (id, stream, _) = try await live.subscribe(); await live.start()
    var iterator = stream.makeAsyncIterator()
    #expect(String(decoding: await iterator.next() ?? Data(), as: UTF8.self).contains("READY"))
    try await registry.setPinned(live, value: true)
    let number = await live.number; #expect(number > 0)
    try await registry.setPinned(live, value: false); try await registry.setPinned(live, value: true)
    #expect(await live.number == number)
    await live.detach(id)
    #expect(!(await live.ended)); #expect(await registry.pinned(host: "local", owner: "owner").count == 1)
    await #expect(throws: (any Error).self) { _ = try await registry.retained(live.id, host: "other", owner: "owner") }
    await #expect(throws: (any Error).self) { _ = try await registry.retained(live.id, host: "local", owner: "intruder") }
    let retained = try await registry.retained(live.id, host: "local", owner: "owner")
    let (second, _, replay) = try await retained.subscribe()
    #expect(String(decoding: replay, as: UTF8.self).contains("READY"))
    try await retained.setPinned(false); #expect(!(await retained.ended))
    await retained.detach(second); #expect(await retained.ended)
    await registry.closeAll()
}
@Test func terminalReplayIsBoundedAndRevocationClosesPins() async throws {
    let registry = TerminalRegistry(); let live = try terminal(script: "head -c 300000 /dev/zero; printf READY; read hold")
    try await registry.register(live)
    let (id, stream, _) = try await live.subscribe(); await live.start()
    var received = Data(); var input = stream.makeAsyncIterator()
    while let chunk = await input.next() { received.append(chunk); if received.suffix(5) == Data("READY".utf8) { break } }
    #expect(received.count >= 300005)
    try await registry.setPinned(live, value: true); await live.detach(id)
    let (_, _, buffered) = try await live.subscribe()
    #expect(buffered.count <= 262144); #expect(buffered.suffix(5) == Data("READY".utf8))
    await registry.reap { _ in false }
    #expect(await live.ended); #expect(await registry.pinned(host: "local", owner: "owner").isEmpty)
}
@Test func ordinaryDisconnectAndLogoutCloseOwnedPTYs() async throws {
    let registry = TerminalRegistry(); let ordinary = try terminal(); try await registry.register(ordinary)
    let (id, _, _) = try await ordinary.subscribe(); await ordinary.detach(id); #expect(await ordinary.ended)
    let pinned = try terminal(); try await registry.register(pinned)
    let (_, stream, _) = try await pinned.subscribe(); try await pinned.setPinned(true)
    await registry.close(owner: "different"); #expect(!(await pinned.ended))
    await registry.close(owner: "owner"); #expect(await pinned.ended)
    _ = stream
    let expired = try terminal(expires: .distantPast); try await registry.register(expired)
    await registry.reap { _ in true }; #expect(await expired.ended)
}

@Test func hostRenamePreservesOwnedPinsAndPendingTickets() async throws {
    let registry = TerminalRegistry(); let live = try terminal()
    try await registry.register(live); let (subscription, _, _) = try await live.subscribe()
    try await registry.setPinned(live, value: true)
    let ticket = try await registry.issue(TerminalLaunch(host: "local"), owner: "owner")
    await registry.renameHosts(["local": "renamed-local"])
    #expect(try await registry.retained(live.id, host: "renamed-local", owner: "owner").id == live.id)
    await #expect(throws: (any Error).self) { _ = try await registry.retained(live.id, host: "local", owner: "owner") }
    await #expect(throws: (any Error).self) { _ = try await registry.retained(live.id, host: "renamed-local", owner: "other") }
    #expect(try await registry.consume(ticket, owner: "owner").host == "renamed-local")
    #expect(await registry.pinned(host: "renamed-local", owner: "owner").count == 1)
    #expect(await live.metadata().launch.host == "renamed-local")
    await live.detach(subscription); #expect(!(await live.ended))
    await registry.closeAll(); await registry.release()
}
