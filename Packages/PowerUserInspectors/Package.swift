// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PowerUserInspectors",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PowerUserInspectors", targets: ["PowerUserInspectors"])
    ],
    dependencies: [
        .package(path: "../CoreScanEngine"),
        .package(path: "../PrivilegedHelperXPC")
    ],
    targets: [
        .target(
            name: "PowerUserInspectors",
            dependencies: ["CoreScanEngine", "PrivilegedHelperXPC"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PowerUserInspectorsTests",
            dependencies: ["PowerUserInspectors"]
        )
    ]
)
