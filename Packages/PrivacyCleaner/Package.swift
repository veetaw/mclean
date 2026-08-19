// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PrivacyCleaner",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PrivacyCleaner", targets: ["PrivacyCleaner"])
    ],
    dependencies: [
        .package(path: "../CoreScanEngine")
    ],
    targets: [
        .target(
            name: "PrivacyCleaner",
            dependencies: ["CoreScanEngine"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PrivacyCleanerTests",
            dependencies: ["PrivacyCleaner"]
        )
    ]
)
