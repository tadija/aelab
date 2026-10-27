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
    let (second, secondStream, replay) = try await retained.subscribe()
    defer { withExtendedLifetime(secondStream) {} }
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
    try await registry.reap { _ in false }
    #expect(await live.ended); #expect(await registry.pinned(host: "local", owner: "owner").isEmpty)
}
@Test func ordinaryDisconnectAndLogoutCloseOwnedPTYs() async throws {
    let registry = TerminalRegistry(); let ordinary = try terminal(); try await registry.register(ordinary)
    let (id, _, _) = try await ordinary.subscribe(); await ordinary.detach(id); #expect(await ordinary.ended)
    let pinned = try terminal(); try await registry.register(pinned)
    let (_, stream, _) = try await pinned.subscribe(); try await pinned.setPinned(true)
    try await registry.close(owner: "different"); #expect(!(await pinned.ended))
    try await registry.close(owner: "owner"); #expect(await pinned.ended)
    _ = stream
    let expired = try terminal(expires: .distantPast); try await registry.register(expired)
    try await registry.reap { _ in true }; #expect(await expired.ended)
}

@Test func hostRenamePreservesOwnedPinsAndPendingTickets() async throws {
    let registry = TerminalRegistry(); let live = try terminal()
    try await registry.register(live); let (subscription, _, _) = try await live.subscribe()
    try await registry.setPinned(live, value: true)
    let ticket = try await registry.issue(TerminalLaunch(host: "local"), owner: "owner")
    try await registry.renameHosts(["local": "renamed-local"])
    #expect(try await registry.retained(live.id, host: "renamed-local", owner: "owner").id == live.id)
    await #expect(throws: (any Error).self) { _ = try await registry.retained(live.id, host: "local", owner: "owner") }
    await #expect(throws: (any Error).self) { _ = try await registry.retained(live.id, host: "renamed-local", owner: "other") }
    #expect(try await registry.consume(ticket, owner: "owner").host == "renamed-local")
    #expect(await registry.pinned(host: "renamed-local", owner: "owner").count == 1)
    #expect(await live.metadata().launch.host == "renamed-local")
    await live.detach(subscription); #expect(!(await live.ended))
    await registry.closeAll(); await registry.release()
}

private struct NumberingProcess: TerminalProcess {
    func readChunk() async -> Data? { nil }
    func input(_ data: Data) async throws {}
    func resize(cols: Int, rows: Int) async throws {}
    func signal(_ signal: String) async throws {}
    func closeSession() async {}
}
private func numberingTerminal() -> LiveTerminal {
    LiveTerminal(pty: NumberingProcess(), owner: "owner", expires: Date().addingTimeInterval(3600), launch: TerminalLaunch(host: "local"), cwd: "/tmp")
}

@Test func pinNumbersReuseClosedGapsWithoutRenumberingLiveTerminals() async throws {
    let registry = TerminalRegistry()
    let first = numberingTerminal(), second = numberingTerminal(), third = numberingTerminal()
    for live in [first, second, third] { try await registry.register(live); try await registry.setPinned(live, value: true) }
    #expect(await first.number == 1); #expect(await second.number == 2); #expect(await third.number == 3)
    // A naturally ended PTY releases its number even before the periodic reaper runs.
    let replacement = numberingTerminal(); try await registry.register(replacement)
    await first.close()
    try await registry.setPinned(replacement, value: true)
    #expect(await replacement.number == 1)
    #expect(await second.number == 2); #expect(await third.number == 3)
    for live in [replacement, second, third] { try await registry.closePinned(live.id, host: "local", owner: "owner") }
    let fresh = numberingTerminal(); try await registry.register(fresh); try await registry.setPinned(fresh, value: true)
    #expect(await fresh.number == 1)
    await registry.closeAll()
}

@Test func unpinnedLiveTerminalsKeepTheirNumberReserved() async throws {
    let registry = TerminalRegistry(), first = numberingTerminal(), second = numberingTerminal()
    try await registry.register(first); let (_, stream, _) = try await first.subscribe()
    try await registry.setPinned(first, value: true); try await registry.setPinned(first, value: false)
    try await registry.register(second); try await registry.setPinned(second, value: true)
    #expect(await second.number == 2)
    try await registry.setPinned(first, value: true); #expect(await first.number == 1)
    _ = stream
    await registry.closeAll()
}

@Test func concurrentPinsReserveDistinctNumbers() async throws {
    let registry = TerminalRegistry()
    var sessions: [LiveTerminal] = []
    for _ in 0..<8 { let live = numberingTerminal(); try await registry.register(live); sessions.append(live) }
    try await withThrowingTaskGroup(of: Void.self) { group in
        for live in sessions { group.addTask { try await registry.setPinned(live, value: true) } }
        try await group.waitForAll()
    }
    let pins = await registry.pinned(host: "local", owner: "owner")
    #expect(pins.map(\.number) == Array(1...8))
    await registry.closeAll()
}

@Test func tmuxPinsShareShortcutNumbersWithoutRetainingPTYs() async throws {
    let registry = TerminalRegistry(), native = numberingTerminal()
    try await registry.register(native); try await registry.setPinned(native, value: true)
    let expires = Date().addingTimeInterval(3600)
    try await registry.setTmuxPinned(host: "local", session: "work", owner: "owner", expires: expires, value: true)
    try await registry.setTmuxPinned(host: "local", session: "work", owner: "owner", expires: expires, value: true)
    let pins = await registry.pinned(host: "local", owner: "owner")
    #expect(pins.map(\.number) == [1, 2]); #expect(pins.last?.session == "work")
    #expect(await registry.pinned(host: "other", owner: "owner").isEmpty)
    #expect(await registry.pinned(host: "local", owner: "stranger").isEmpty)
    await #expect(throws: (any Error).self) { _ = try await registry.retained(pins.last!.id, host: "local", owner: "owner") }
    // Model an observation that definitely predates the rename, even on coarse clocks.
    let observationStarted = Date().addingTimeInterval(-1)
    try await registry.updateTmuxSession(host: "local", session: "work", renamed: "renamed")
    try await registry.reconcileTmux(host: "local", sessions: ["work"], observedSince: observationStarted)
    #expect(await registry.pinned(host: "local", owner: "owner").last?.number == 2)
    #expect(await registry.pinned(host: "local", owner: "owner").last?.session == "renamed")
    try await registry.setTmuxPinned(host: "local", session: "renamed", owner: "owner", expires: expires, value: false)
    try await registry.setTmuxPinned(host: "local", session: "next", owner: "owner", expires: expires, value: true)
    #expect(await registry.pinned(host: "local", owner: "owner").last?.number == 2)
    try await registry.reconcileTmux(host: "local", sessions: [])
    #expect(await registry.pinned(host: "local", owner: "owner").count == 1)
    await registry.closeAll()
}

@Test func tmuxPinsFollowHostRenamesAndLoginLifetimes() async throws {
    let registry = TerminalRegistry(), expires = Date().addingTimeInterval(3600)
    try await registry.setTmuxPinned(host: "old", session: "work", owner: "owner", expires: expires, value: true)
    try await registry.renameHosts(["old": "new"])
    #expect(await registry.pinned(host: "new", owner: "owner").count == 1)
    try await registry.reap { _ in false }
    #expect(await registry.pinned(host: "new", owner: "owner").isEmpty)
    try await registry.setTmuxPinned(host: "new", session: "work", owner: "owner", expires: expires, value: true)
    try await registry.close(owner: "owner")
    #expect(await registry.pinned(host: "new", owner: "owner").isEmpty)
}

@Test func tmuxHeaderMetadataReflectsShortcutWithoutRetainingAttachment() async throws {
    let registry = TerminalRegistry()
    let attachment = LiveTerminal(pty: NumberingProcess(), owner: "owner", expires: Date().addingTimeInterval(3600), launch: TerminalLaunch(host: "local", session: "work"), cwd: "/tmp")
    #expect(!(await registry.metadata(for: attachment).pinned))
    try await registry.setTmuxPinned(host: "local", session: "work", owner: "owner", expires: Date().addingTimeInterval(3600), value: true)
    #expect(await registry.metadata(for: attachment).pinned)
    #expect(!(await attachment.pinned))
    try await registry.setTmuxPinned(host: "local", session: "work", owner: "owner", expires: Date().addingTimeInterval(3600), value: false)
    #expect(!(await registry.metadata(for: attachment).pinned))
    await registry.closeAll()
}

@Test func logoutDisconnectsOnlyItsClientsAndKeepsPinnedProcess() async throws {
    let registry = TerminalRegistry(), pinned = numberingTerminal(), ordinary = numberingTerminal()
    try await registry.register(pinned); try await registry.register(ordinary)
    let (_, first, _) = try await pinned.subscribe(login: "first-login")
    let (_, other, _) = try await pinned.subscribe(login: "other-login")
    let (_, temporary, _) = try await ordinary.subscribe(login: "first-login")
    try await registry.setPinned(pinned, value: true)
    let ticket = try await registry.issue(TerminalLaunch(host: "local"), owner: "first-login")
    await registry.disconnect(login: "first-login")
    var firstReader = first.makeAsyncIterator(), temporaryReader = temporary.makeAsyncIterator()
    #expect(await firstReader.next() == nil); #expect(await temporaryReader.next() == nil)
    #expect(!(await pinned.ended)); #expect(await ordinary.ended)
    #expect(await registry.pinned(host: "local", owner: "owner").first?.id == pinned.id)
    await #expect(throws: (any Error).self) { _ = try await registry.consume(ticket, owner: "first-login") }
    // Unpin with another login still connected: its attachment must remain live.
    try await registry.setPinned(pinned, value: false)
    #expect(!(await pinned.ended))
    await registry.disconnect(login: "other-login")
    var otherReader = other.makeAsyncIterator(); #expect(await otherReader.next() == nil)
    #expect(await pinned.ended)
    await registry.closeAll()
}

@Test func tmuxPinsRestoreIDsAndNumbersWithoutRestoringNativeShells() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    _ = try ConfigStore(home: home)
    let first = try TerminalRegistry(home: home), native = numberingTerminal()
    try await first.register(native); try await first.setPinned(native, value: true)
    try await first.setTmuxPinned(host: "local", session: "work", owner: "owner", expires: .distantFuture, value: true)
    let saved = await first.pinned(host: "local", owner: "owner").last!
    #expect(saved.number == 2)
    await first.closeAll() // Graceful shutdown must leave tmux shortcuts on disk.
    let restored = try TerminalRegistry(home: home)
    let pins = await restored.pinned(host: "local", owner: "owner")
    #expect(pins.count == 1); #expect(pins[0].id == saved.id); #expect(pins[0].number == 2)
    let replacement = numberingTerminal()
    try await restored.register(replacement); try await restored.setPinned(replacement, value: true)
    #expect(await replacement.number == 1)
    try await restored.renameHosts(["local": "renamed"])
    try await restored.updateTmuxSession(host: "renamed", session: "work", renamed: "next")
    let renamed = try TerminalRegistry(home: home)
    #expect(await renamed.pinned(host: "renamed", owner: "owner").first?.session == "next")
    #expect(await renamed.pinned(host: "renamed", owner: "owner").first?.number == 2)
    let mode = try FileManager.default.attributesOfItem(atPath: home.appendingPathComponent("state/tmux-pins.json").path)[.posixPermissions] as? NSNumber
    #expect(mode?.intValue == 0o600)
    try await renamed.setTmuxPinned(host: "renamed", session: "next", owner: "owner", expires: .distantFuture, value: false)
    let unpinned = try TerminalRegistry(home: home)
    #expect(await unpinned.pinned(host: "renamed", owner: "owner").isEmpty)
    await restored.closeAll()
}

@Test func tmuxPinCleanupPersistsAndFailedWritesKeepMemoryUnchanged() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    _ = try ConfigStore(home: home)
    let registry = try TerminalRegistry(home: home)
    try await registry.setTmuxPinned(host: "local", session: "work", owner: "owner", expires: .distantFuture, value: true)
    try await registry.reap { _ in false }
    let revoked = try TerminalRegistry(home: home)
    #expect(await revoked.pinned(host: "local", owner: "owner").isEmpty)
    try await registry.setTmuxPinned(host: "local", session: "work", owner: "owner", expires: .distantFuture, value: true)
    try await registry.reconcileTmux(host: "local", sessions: [])
    let vanished = try TerminalRegistry(home: home)
    #expect(await vanished.pinned(host: "local", owner: "owner").isEmpty)
    try await registry.setTmuxPinned(host: "local", session: "work", owner: "owner", expires: .distantFuture, value: true)
    try await registry.retainHosts([])
    let removedHost = try TerminalRegistry(home: home)
    #expect(await removedHost.pinned(host: "local", owner: "owner").isEmpty)
    try await registry.setTmuxPinned(host: "local", session: "work", owner: "owner", expires: .distantFuture, value: true)
    let file = home.appendingPathComponent("state/tmux-pins.json")
    let valid = try Data(contentsOf: file)
    var records = try JSONSerialization.jsonObject(with: valid) as! [[String: Any]]
    records.append(records[0])
    try JSONSerialization.data(withJSONObject: records).write(to: file)
    #expect(throws: (any Error).self) { _ = try TerminalRegistry(home: home) }
    try FileManager.default.removeItem(at: file)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
    await #expect(throws: (any Error).self) { try await registry.setTmuxPinned(host: "local", session: "work", owner: "owner", expires: .distantFuture, value: false) }
    #expect(await registry.pinned(host: "local", owner: "owner").count == 1)
}

@Test func temporaryShellsAreScopedResumableAndDisappearWhenPinnedOrClosed() async throws {
    let registry = TerminalRegistry()
    let live = try terminal()
    try await registry.register(live)
    let terminalID = await live.id
    let (first, firstStream, _) = try await live.subscribe()
    defer { withExtendedLifetime(firstStream) {} }
    #expect(await registry.temporary(host: "local", owner: "owner").map(\.id) == [terminalID])
    #expect(await registry.temporary(host: "other", owner: "owner").isEmpty)
    #expect(await registry.temporary(host: "local", owner: "other").isEmpty)
    await #expect(throws: (any Error).self) { _ = try await registry.retained(live.id, host: "local", owner: "owner") }
    await #expect(throws: (any Error).self) { _ = try await registry.retained(live.id, host: "local", owner: "other", allowTemporary: true) }
    let resumed = try await registry.retained(live.id, host: "local", owner: "owner", allowTemporary: true)
    #expect(await resumed.id == terminalID)
    let (second, secondStream, _) = try await resumed.subscribe()
    defer { withExtendedLifetime(secondStream) {} }
    try await registry.setPinned(live, value: true)
    #expect(await registry.temporary(host: "local", owner: "owner").isEmpty)
    try await registry.setPinned(live, value: false)
    await live.detach(first)
    #expect(!(await live.ended))
    #expect(await registry.temporary(host: "local", owner: "owner").count == 1)
    await live.detach(second)
    #expect(await live.ended)
    #expect(await registry.temporary(host: "local", owner: "owner").isEmpty)
    await #expect(throws: (any Error).self) { _ = try await registry.retained(live.id, host: "local", owner: "owner", allowTemporary: true) }
    await registry.closeAll()
}
