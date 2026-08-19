// swift-tools-version: 6.0
import PackageDescription

// No dependency on CoreScanEngine: maintenance scripts are explicit,
// user-initiated actions (flush DNS, rebuild Spotlight index, etc.), not
// scan-and-classify detectors. They never delete arbitrary user files, so
// they don't need SafetyRules either — see ARCHITECTURE.md.
let package = Package(
    name: "MaintenanceScripts",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MaintenanceScripts", targets: ["MaintenanceScripts"])
    ],
    targets: [
        .target(
            name: "MaintenanceScripts",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MaintenanceScriptsTests",
            dependencies: ["MaintenanceScripts"]
        )
    ]
)
