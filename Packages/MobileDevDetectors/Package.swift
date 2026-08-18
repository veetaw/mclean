// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MobileDevDetectors",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MobileDevDetectors", targets: ["MobileDevDetectors"])
    ],
    dependencies: [
        .package(path: "../CoreScanEngine")
    ],
    targets: [
        .target(
            name: "MobileDevDetectors",
            dependencies: ["CoreScanEngine"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MobileDevDetectorsTests",
            dependencies: ["MobileDevDetectors"]
        )
    ]
)
