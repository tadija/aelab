import Foundation
import Testing
import Core
@testable import Cli

@Test func launchOptionsSelectTheCorrectHomeAndValidateRoleSpecificFlags() throws {
    let env = ["AELAB_HOME": "/tmp/custom lab", "AELAB_PORT": "1234"]
    let server = try LaunchOptions(kind: .server, arguments: ["--service", "--port", "4321"], home: nil, environment: env)
    #expect(server.home.path == "/tmp/custom lab"); #expect(server.port == "4321"); #expect(server.service)
    let daemon = try LaunchOptions(kind: .daemon, arguments: ["--endpoint", "https://host:1984", "--bind", "127.0.0.1"], home: nil, environment: env)
    #expect(daemon.home.path == "/tmp/custom lab/daemon"); #expect(daemon.endpoint == "https://host:1984")
    #expect(try LaunchOptions(kind: .daemon, arguments: [], home: "/tmp/explicit", environment: env).home.path == "/tmp/explicit")
    for args in [["--port", "0"], ["--port", "65536"], ["--port"], ["--home", ""], ["--service", "--service"], ["--endpoint", "https://host"]] {
        #expect(throws: (any Error).self) { try LaunchOptions(kind: .server, arguments: args, home: nil, environment: env) }
    }
    #expect(throws: (any Error).self) { try LaunchOptions(kind: .daemon, arguments: ["--port", "1234"], home: nil, environment: env) }
}
@Test func installedLaunchesFollowTheCurrentRelease() {
    #expect(LaunchCommand.binary("aelab-server", cli: URL(fileURLWithPath: "/prefix/share/aelab/releases/uuid/bin/aelab-cli")).path == "/prefix/share/aelab/current/bin/aelab-server")
    #expect(LaunchCommand.binary("aelab-daemon", cli: URL(fileURLWithPath: "/repo/.build/debug/aelab-cli")).path == "/repo/.build/debug/aelab-daemon")
}
