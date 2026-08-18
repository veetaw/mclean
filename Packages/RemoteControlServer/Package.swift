// swift-tools-version: 6.0
import PackageDescription

// NOTE: no HTTP server dependency is declared yet. PROMPT MASTER §10
// checkpoint 1 requires the user to confirm the local HTTP server library
// choice before it's added here. Once decided, add it to `dependencies`
// and to this target's `dependencies` array.
let package = Package(
    name: "RemoteControlServer",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "RemoteControlServer", targets: ["RemoteControlServer"])
    ],
    dependencies: [
        .package(path: "../CoreScanEngine"),
        .package(path: "../SafetyRules")
    ],
    targets: [
        .target(
            name: "RemoteControlServer",
            dependencies: ["CoreScanEngine", "SafetyRules"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RemoteControlServerTests",
            dependencies: ["RemoteControlServer"]
        )
    ]
)
