// swift-tools-version: 6.0
import PackageDescription

// UIDesignSystem dependency: unlike the other Phase 5/6 finder packages,
// SpaceLens's deliverable is substantially a SwiftUI view (an interactive
// treemap), not just a data source consumed by MainAppUI's generic
// FindingsListView — so its view code lives here and uses the shared
// Liquid Glass component/token vocabulary directly. See ARCHITECTURE.md.
let package = Package(
    name: "SpaceLens",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SpaceLens", targets: ["SpaceLens"])
    ],
    dependencies: [
        .package(path: "../UIDesignSystem")
    ],
    targets: [
        .target(
            name: "SpaceLens",
            dependencies: ["UIDesignSystem"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SpaceLensTests",
            dependencies: ["SpaceLens"]
        )
    ]
)
