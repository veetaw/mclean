// swift-tools-version: 6.0
import PackageDescription

// This package is the Phase 2 "Agent:MainAppUI" assembly point: it depends
// on UIDesignSystem plus every feature package so the SwiftUI app (and the
// Capabilities/AppEnvironment composition root) can be built and tested
// independently of the generated Xcode project. See ARCHITECTURE.md.
//
// NOTE: the `#if APPSTORE` compilation condition that `Capabilities`
// resolves against is normally supplied by the Xcode target
// (`SWIFT_ACTIVE_COMPILATION_CONDITIONS: APPSTORE`, see App/project.yml).
// `swift build`/`swift test` in isolation (no flag set) behaves like the
// Developer ID flavor, which is the correct default for package-local
// testing — the App Store flavor is only real inside the AppStore Xcode
// target.
let package = Package(
    name: "MainAppUI",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MainAppUI", targets: ["MainAppUI"])
    ],
    dependencies: [
        .package(path: "../CoreScanEngine"),
        .package(path: "../SafetyRules"),
        .package(path: "../DevToolsDetectors"),
        .package(path: "../MobileDevDetectors"),
        .package(path: "../PowerUserInspectors"),
        .package(path: "../MenuBarAgent"),
        .package(path: "../RemoteControlServer"),
        .package(path: "../VirusTotalClient"),
        .package(path: "../PrivilegedHelperXPC"),
        .package(path: "../UIDesignSystem")
    ],
    targets: [
        .target(
            name: "MainAppUI",
            dependencies: [
                "CoreScanEngine",
                "SafetyRules",
                "DevToolsDetectors",
                "MobileDevDetectors",
                "PowerUserInspectors",
                "MenuBarAgent",
                "RemoteControlServer",
                "VirusTotalClient",
                "PrivilegedHelperXPC",
                "UIDesignSystem"
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MainAppUITests",
            dependencies: ["MainAppUI"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
