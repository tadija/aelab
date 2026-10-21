// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "aelab", platforms: [.macOS(.v14)], products: [
 .executable(name: "aelab-daemon", targets: ["Daemon"]), .executable(name: "aelab-server", targets: ["Server"]), .executable(name: "aelab", targets: ["Cli"])
], dependencies: [
 .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.14.0"),
 .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.5.0"),
 .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
 .package(url: "https://github.com/apple/swift-http-types.git", from: "1.0.0")
], targets: [
 .target(name: "CPTY", linkerSettings: [.linkedLibrary("util", .when(platforms: [.linux]))]),
 .target(name: "Core", dependencies: ["CPTY", .product(name: "HummingbirdWSClient", package: "hummingbird-websocket"), .product(name: "HummingbirdTLS", package: "hummingbird"), .product(name: "HTTPTypes", package: "swift-http-types"), .product(name: "Crypto", package: "swift-crypto"), .product(name: "_CryptoExtras", package: "swift-crypto")]),
 .executableTarget(name: "Server", dependencies: ["Core", .product(name: "Hummingbird", package: "hummingbird"), .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"), .product(name: "HTTPTypes", package: "swift-http-types")]),
 .executableTarget(name: "Daemon", dependencies: ["Core", .product(name: "HummingbirdCore", package: "hummingbird"), .product(name: "Hummingbird", package: "hummingbird"), .product(name: "HummingbirdTLS", package: "hummingbird"), .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket")]),
 .executableTarget(name: "Cli", dependencies: ["Core"]),
 .testTarget(name: "CoreTests", dependencies: ["Core", "CPTY"]),
 .testTarget(name: "CliTests", dependencies: ["Cli"])
])
