// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SafetyRules",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SafetyRules", targets: ["SafetyRules"])
    ],
    dependencies: [
        .package(path: "../CoreScanEngine")
    ],
    targets: [
        .target(
            name: "SafetyRules",
            dependencies: ["CoreScanEngine"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SafetyRulesTests",
            dependencies: ["SafetyRules"]
        )
    ]
)
