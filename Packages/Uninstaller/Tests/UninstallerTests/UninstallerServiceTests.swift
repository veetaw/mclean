import Foundation
import XCTest
import CoreScanEngine
import PowerUserInspectors
@testable import Uninstaller

/// Builds a fake `~/Library` tree (plus a fake `/Library`) under a temp
/// directory, laid out like a real one, so `UninstallerService` never has
/// to touch the actual filesystem locations it targets.
final class UninstallerServiceTests: XCTestCase {
    private var home: URL!
    private var systemLibrary: URL!

    override func setUp() {
        super.setUp()
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("UninstallerTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        systemLibrary = home.appendingPathComponent("FakeSystemLibrary", isDirectory: true)
    }

    override func tearDown() {
        if let home { try? FileManager.default.removeItem(at: home) }
        home = nil
        systemLibrary = nil
        super.tearDown()
    }

    /// Creates an empty directory at `path` (and any missing parents).
    private func makeDirectory(_ path: String) {
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    /// Creates an empty regular file at `path` (and any missing parent
    /// directories).
    private func makeFile(_ path: String) {
        let directory = (path as NSString).deletingLastPathComponent
        makeDirectory(directory)
        FileManager.default.createFile(atPath: path, contents: Data("x".utf8))
    }

    private func makeApp(
        name: String,
        bundleIdentifier: String?,
        path: String
    ) -> PowerUserInspectors.InstalledApp {
        makeDirectory(path) // a fake ".app" bundle is just a directory for this test's purposes
        return PowerUserInspectors.InstalledApp(
            name: name,
            bundleIdentifier: bundleIdentifier,
            shortVersion: "1.0",
            buildVersion: "1",
            path: path,
            sizeBytes: nil,
            lastUsed: nil
        )
    }

    private var libraryPath: String { home.appendingPathComponent("Library").path }

    // MARK: - Exact bundle-identifier matches across every location

    func testExactBundleIdentifierMatchesFound() {
        let bundleID = "com.example.myapp"
        let appPath = home.appendingPathComponent("Applications/MyApp.app").path
        let app = makeApp(name: "MyApp", bundleIdentifier: bundleID, path: appPath)

        let library = libraryPath
        makeDirectory("\(library)/Application Support/\(bundleID)")
        makeFile("\(library)/Preferences/\(bundleID).plist")
        makeDirectory("\(library)/Caches/\(bundleID)")
        makeDirectory("\(library)/Saved Application State/\(bundleID).savedState")
        makeFile("\(library)/LaunchAgents/\(bundleID).plist")

        let service = UninstallerService(homeDirectory: home, systemLibraryDirectory: systemLibrary)
        let items = service.relatedFiles(for: app)
        let paths = Set(items.map(\.path))

        XCTAssertTrue(paths.contains(appPath))
        XCTAssertTrue(paths.contains("\(library)/Application Support/\(bundleID)"))
        XCTAssertTrue(paths.contains("\(library)/Preferences/\(bundleID).plist"))
        XCTAssertTrue(paths.contains("\(library)/Caches/\(bundleID)"))
        XCTAssertTrue(paths.contains("\(library)/Saved Application State/\(bundleID).savedState"))
        XCTAssertTrue(paths.contains("\(library)/LaunchAgents/\(bundleID).plist"))
        for item in items {
            XCTAssertEqual(item.sourceDetectorID, UninstallerService.sourceID)
        }
    }

    // MARK: - Helper-process bundle IDs (dot-boundary prefix match)

    func testHelperProcessPrefixMatch() {
        let bundleID = "com.example.myapp"
        let appPath = home.appendingPathComponent("Applications/MyApp.app").path
        let app = makeApp(name: "MyApp", bundleIdentifier: bundleID, path: appPath)

        let library = libraryPath
        makeFile("\(library)/Preferences/\(bundleID).helper.plist")
        makeFile("\(library)/LaunchAgents/\(bundleID).updater.plist")

        let service = UninstallerService(homeDirectory: home, systemLibraryDirectory: systemLibrary)
        let paths = Set(service.relatedFiles(for: app).map(\.path))

        XCTAssertTrue(paths.contains("\(library)/Preferences/\(bundleID).helper.plist"))
        XCTAssertTrue(paths.contains("\(library)/LaunchAgents/\(bundleID).updater.plist"))
    }

    // MARK: - False positive: an unrelated app's files must never be flagged

    func testUnrelatedAppFilesAreNotIncluded() {
        let bundleID = "com.example.myapp"
        let appPath = home.appendingPathComponent("Applications/MyApp.app").path
        let app = makeApp(name: "MyApp", bundleIdentifier: bundleID, path: appPath)

        let library = libraryPath

        // A genuinely unrelated app, stored alongside the target app's files.
        let unrelatedID = "com.other.unrelated"
        makeDirectory("\(library)/Application Support/\(unrelatedID)")
        makeFile("\(library)/Preferences/\(unrelatedID).plist")
        makeDirectory("\(library)/Caches/\(unrelatedID)")

        // A different app whose bundle ID merely shares a string prefix
        // with the target's — must NOT match via the dot-boundary rule.
        let similarID = "com.example.myapp2"
        makeFile("\(library)/Preferences/\(similarID).plist")
        makeDirectory("\(library)/Caches/\(similarID)")
        makeFile("\(library)/LaunchAgents/\(similarID).plist")

        // Also a same-named Application Support directory belonging to the
        // *unrelated* app's own display name, to make sure name-based
        // matching for the target app doesn't accidentally sweep it in.
        makeDirectory("\(library)/Application Support/SomeOtherDisplayName")

        let service = UninstallerService(homeDirectory: home, systemLibraryDirectory: systemLibrary)
        let paths = Set(service.relatedFiles(for: app).map(\.path))

        // Only the app bundle itself should be present — none of the
        // unrelated or merely-prefix-similar files.
        XCTAssertEqual(paths, [appPath])
        XCTAssertFalse(paths.contains("\(library)/Application Support/\(unrelatedID)"))
        XCTAssertFalse(paths.contains("\(library)/Preferences/\(unrelatedID).plist"))
        XCTAssertFalse(paths.contains("\(library)/Caches/\(unrelatedID)"))
        XCTAssertFalse(paths.contains("\(library)/Preferences/\(similarID).plist"))
        XCTAssertFalse(paths.contains("\(library)/Caches/\(similarID)"))
        XCTAssertFalse(paths.contains("\(library)/LaunchAgents/\(similarID).plist"))
        XCTAssertFalse(paths.contains("\(library)/Application Support/SomeOtherDisplayName"))
    }

    // MARK: - The app bundle itself is always included

    func testAppBundleAlwaysIncluded() {
        let appPath = home.appendingPathComponent("Applications/Lonely.app").path
        let app = makeApp(name: "Lonely", bundleIdentifier: "com.example.lonely", path: appPath)

        let service = UninstallerService(homeDirectory: home, systemLibraryDirectory: systemLibrary)
        let items = service.relatedFiles(for: app)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.path, appPath)
        XCTAssertEqual(items.first?.category, "Application bundle")
    }

    // MARK: - Name-based fallback (no bundle identifier) is conservative

    func testNameFallbackIsConservative() {
        let appName = "LegacyApp"
        let appPath = home.appendingPathComponent("Applications/\(appName).app").path
        let app = makeApp(name: appName, bundleIdentifier: nil, path: appPath)

        let library = libraryPath
        makeDirectory("\(library)/Application Support/\(appName)")
        makeDirectory("\(library)/Caches/\(appName)")
        // Reverse-DNS-keyed locations are deliberately NOT matched by name —
        // even if a file happens to exist that a naive guess might hit.
        makeFile("\(library)/Preferences/\(appName).plist")
        makeFile("\(library)/LaunchAgents/\(appName).plist")
        makeDirectory("\(library)/Saved Application State/\(appName).savedState")

        let service = UninstallerService(homeDirectory: home, systemLibraryDirectory: systemLibrary)
        let paths = Set(service.relatedFiles(for: app).map(\.path))

        XCTAssertTrue(paths.contains(appPath))
        XCTAssertTrue(paths.contains("\(library)/Application Support/\(appName)"))
        XCTAssertTrue(paths.contains("\(library)/Caches/\(appName)"))
        // Conservative fallback: these must NOT be included without a bundle ID.
        XCTAssertFalse(paths.contains("\(library)/Preferences/\(appName).plist"))
        XCTAssertFalse(paths.contains("\(library)/LaunchAgents/\(appName).plist"))
        XCTAssertFalse(paths.contains("\(library)/Saved Application State/\(appName).savedState"))
        XCTAssertEqual(paths.count, 3) // app bundle + Application Support + Caches
    }

    // MARK: - System-level LaunchAgents/LaunchDaemons are listed but flagged

    func testSystemLevelItemsAreFlaggedNotSilentlyRemovable() {
        let bundleID = "com.example.daemonapp"
        let appPath = home.appendingPathComponent("Applications/DaemonApp.app").path
        let app = makeApp(name: "DaemonApp", bundleIdentifier: bundleID, path: appPath)

        makeFile(systemLibrary.appendingPathComponent("LaunchAgents/\(bundleID).plist").path)
        makeFile(systemLibrary.appendingPathComponent("LaunchDaemons/\(bundleID).plist").path)

        let service = UninstallerService(homeDirectory: home, systemLibraryDirectory: systemLibrary)
        let items = service.relatedFiles(for: app)

        guard let daemonItem = items.first(where: { $0.category == "LaunchDaemons (system)" }) else {
            XCTFail("expected a LaunchDaemons (system) item")
            return
        }
        XCTAssertTrue(daemonItem.reason.localizedCaseInsensitiveContains("privileges"))

        guard let agentItem = items.first(where: { $0.category == "LaunchAgents (system)" }) else {
            XCTFail("expected a LaunchAgents (system) item")
            return
        }
        XCTAssertTrue(agentItem.reason.localizedCaseInsensitiveContains("privileges"))
    }

    // MARK: - Dot-boundary matcher unit coverage

    func testDotBoundaryMatcher() {
        let id = "com.example.myapp"
        XCTAssertTrue(UninstallerService.isDotBoundaryMatch("com.example.myapp", identifier: id))
        XCTAssertTrue(UninstallerService.isDotBoundaryMatch("com.example.myapp.plist", identifier: id))
        XCTAssertTrue(UninstallerService.isDotBoundaryMatch("com.example.myapp.helper.plist", identifier: id))
        XCTAssertFalse(UninstallerService.isDotBoundaryMatch("com.example.myapp2.plist", identifier: id))
        XCTAssertFalse(UninstallerService.isDotBoundaryMatch("com.example.myappOther", identifier: id))
        XCTAssertFalse(UninstallerService.isDotBoundaryMatch("com.example.other", identifier: id))
    }
}
