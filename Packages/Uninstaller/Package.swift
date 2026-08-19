// swift-tools-version: 6.0
import PackageDescription

// Depends on PowerUserInspectors for InstalledApp (reuses the same
// installed-apps model InstalledAppsInspector already produces, rather than
// re-scanning /Applications independently).
let package = Package(
    name: "Uninstaller",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Uninstaller", targets: ["Uninstaller"])
    ],
    dependencies: [
        .package(path: "../CoreScanEngine"),
        .package(path: "../PowerUserInspectors")
    ],
    targets: [
        .target(
            name: "Uninstaller",
            dependencies: ["CoreScanEngine", "PowerUserInspectors"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "UninstallerTests",
            dependencies: ["Uninstaller"]
        )
    ]
)
