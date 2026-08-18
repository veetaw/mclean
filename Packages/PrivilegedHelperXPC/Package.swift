// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PrivilegedHelperXPC",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PrivilegedHelperXPC", targets: ["PrivilegedHelperXPC"])
    ],
    targets: [
        .target(
            name: "PrivilegedHelperXPC",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PrivilegedHelperXPCTests",
            dependencies: ["PrivilegedHelperXPC"]
        )
    ]
)
