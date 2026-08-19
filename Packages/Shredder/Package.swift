// swift-tools-version: 6.0
import PackageDescription

// Depends on SafetyRules for `Denylist` ONLY — Shredder is the one
// deliberate exception to the quarantine flow (see ARCHITECTURE.md), so it
// does not depend on CoreScanEngine's Detector pipeline or
// FileSystemQuarantineManager. It still MUST re-check Denylist itself
// before ever touching a file, as defense in depth.
let package = Package(
    name: "Shredder",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Shredder", targets: ["Shredder"])
    ],
    dependencies: [
        .package(path: "../SafetyRules")
    ],
    targets: [
        .target(
            name: "Shredder",
            dependencies: ["SafetyRules"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ShredderTests",
            dependencies: ["Shredder"]
        )
    ]
)
