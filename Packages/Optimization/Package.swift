// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Optimization",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Optimization", targets: ["Optimization"])
    ],
    dependencies: [
        .package(path: "../CoreScanEngine")
    ],
    targets: [
        .target(
            name: "Optimization",
            dependencies: ["CoreScanEngine"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "OptimizationTests",
            dependencies: ["Optimization"]
        )
    ]
)
