// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MenuBarAgent",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MenuBarAgent", targets: ["MenuBarAgent"])
    ],
    dependencies: [
        .package(path: "../CoreScanEngine"),
        .package(path: "../SafetyRules")
    ],
    targets: [
        .target(
            name: "MenuBarAgent",
            dependencies: ["CoreScanEngine", "SafetyRules"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MenuBarAgentTests",
            dependencies: ["MenuBarAgent"]
        )
    ]
)
