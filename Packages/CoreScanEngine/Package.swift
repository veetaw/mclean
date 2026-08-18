// swift-tools-version: 6.0
import PackageDescription

// NOTE: The app itself targets macOS 26 (Tahoe) and later only — see root README.
// The SPM `platforms` field only affects what the *compiler* is allowed to assume
// while building this package in isolation; it is intentionally set to a lower
// floor so the package builds in CI/tooling that may not yet expose the macOS 26 SDK.
// The App targets pin the real minimum deployment target in the Xcode project.
let package = Package(
    name: "CoreScanEngine",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CoreScanEngine", targets: ["CoreScanEngine"])
    ],
    targets: [
        .target(
            name: "CoreScanEngine",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CoreScanEngineTests",
            dependencies: ["CoreScanEngine"]
        )
    ]
)
