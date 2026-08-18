// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DevToolsDetectors",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DevToolsDetectors", targets: ["DevToolsDetectors"])
    ],
    dependencies: [
        .package(path: "../CoreScanEngine")
    ],
    targets: [
        .target(
            name: "DevToolsDetectors",
            dependencies: ["CoreScanEngine"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DevToolsDetectorsTests",
            dependencies: ["DevToolsDetectors"]
        )
    ]
)
