// swift-tools-version: 6.0
import PackageDescription

// Rule-file parsing: Yams (https://github.com/jpsim/Yams), the standard
// Swift YAML library — small, no transitive dependencies beyond
// libYAML, MIT-licensed. Chosen the same way Swifter was for
// RemoteControlServer: an approved feature (checkpoint 4's rule-file
// format) needs a parser, and this is the established choice rather than
// hand-rolling one. See ARCHITECTURE.md.
let package = Package(
    name: "SafetyRules",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SafetyRules", targets: ["SafetyRules"])
    ],
    dependencies: [
        .package(path: "../CoreScanEngine"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "SafetyRules",
            dependencies: [
                "CoreScanEngine",
                .product(name: "Yams", package: "Yams")
            ],
            resources: [.copy("Resources/official_rules.yaml")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SafetyRulesTests",
            dependencies: ["SafetyRules"]
        )
    ]
)
