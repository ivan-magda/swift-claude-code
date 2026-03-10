// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "swift-claude-code",
  platforms: [.macOS(.v10_15)],
  products: [
    .executable(name: "claude", targets: ["cli"]),
    .library(name: "Core", targets: ["Core"]),
  ],
  dependencies: [
    .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.32.0")
  ],
  targets: [
    .executableTarget(
      name: "cli",
      dependencies: ["Core"],
      path: "Sources/cli"
    ),
    .target(
      name: "Core",
      dependencies: [
        .product(name: "AsyncHTTPClient", package: "async-http-client")
      ],
      path: "Sources/Core"
    ),
    .testTarget(
      name: "CoreTests",
      dependencies: ["Core"],
      path: "Tests/CoreTests"
    ),
  ]
)
