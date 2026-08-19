// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CacheCleaner",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CacheCleaner", targets: ["CacheCleaner"])
    ],
    dependencies: [
        .package(path: "../CoreScanEngine")
    ],
    targets: [
        .target(
            name: "CacheCleaner",
            dependencies: ["CoreScanEngine"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CacheCleanerTests",
            dependencies: ["CacheCleaner"]
        )
    ]
)
