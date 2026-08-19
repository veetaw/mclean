// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DuplicateFinder",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DuplicateFinder", targets: ["DuplicateFinder"])
    ],
    dependencies: [
        .package(path: "../CoreScanEngine")
    ],
    targets: [
        .target(
            name: "DuplicateFinder",
            dependencies: ["CoreScanEngine"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DuplicateFinderTests",
            dependencies: ["DuplicateFinder"]
        )
    ]
)
