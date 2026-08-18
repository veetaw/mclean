// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VirusTotalClient",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "VirusTotalClient", targets: ["VirusTotalClient"])
    ],
    targets: [
        .target(
            name: "VirusTotalClient",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "VirusTotalClientTests",
            dependencies: ["VirusTotalClient"]
        )
    ]
)
