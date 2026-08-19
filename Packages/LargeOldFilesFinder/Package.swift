// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LargeOldFilesFinder",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LargeOldFilesFinder", targets: ["LargeOldFilesFinder"])
    ],
    dependencies: [
        .package(path: "../CoreScanEngine")
    ],
    targets: [
        .target(
            name: "LargeOldFilesFinder",
            dependencies: ["CoreScanEngine"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LargeOldFilesFinderTests",
            dependencies: ["LargeOldFilesFinder"]
        )
    ]
)
