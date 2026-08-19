// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TrashCleaner",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TrashCleaner", targets: ["TrashCleaner"])
    ],
    dependencies: [
        .package(path: "../CoreScanEngine")
    ],
    targets: [
        .target(
            name: "TrashCleaner",
            dependencies: ["CoreScanEngine"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TrashCleanerTests",
            dependencies: ["TrashCleaner"]
        )
    ]
)
