// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UIDesignSystem",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "UIDesignSystem", targets: ["UIDesignSystem"])
    ],
    targets: [
        .target(
            name: "UIDesignSystem",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "UIDesignSystemTests",
            dependencies: ["UIDesignSystem"]
        )
    ]
)
