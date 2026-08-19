// swift-tools-version: 6.0
import PackageDescription

// HTTP server library: Swifter (https://github.com/httpswift/swifter).
// Decided in ARCHITECTURE.md checkpoint 1 — small, embeddable, no heavy
// async-networking stack for what is a single-client-at-a-time, LAN-only
// server. Kept to a narrow usage surface (routing + request/response only,
// see Sources/RemoteControlServer/HTTP) so it stays cheap to swap later.
let package = Package(
    name: "RemoteControlServer",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "RemoteControlServer", targets: ["RemoteControlServer"])
    ],
    dependencies: [
        .package(path: "../CoreScanEngine"),
        .package(path: "../SafetyRules"),
        .package(url: "https://github.com/httpswift/swifter.git", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "RemoteControlServer",
            dependencies: [
                "CoreScanEngine",
                "SafetyRules",
                .product(name: "Swifter", package: "swifter")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RemoteControlServerTests",
            dependencies: ["RemoteControlServer"]
        )
    ]
)
