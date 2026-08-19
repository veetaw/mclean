import XCTest
import CoreScanEngine
@testable import PowerUserInspectors

final class InstalledAppsInspectorTests: TempDirTestCase {
    private var applicationsDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        applicationsDir = tempDir.appendingPathComponent("Applications")
        try TestSupport.makeDirectory(at: applicationsDir)
    }

    @discardableResult
    private func makeAppBundle(
        named appName: String,
        bundleIdentifier: String,
        shortVersion: String,
        buildVersion: String = "1",
        payloadSize: Int = 2048
    ) throws -> URL {
        let bundleURL = applicationsDir.appendingPathComponent("\(appName).app")
        let contentsURL = bundleURL.appendingPathComponent("Contents")
        try TestSupport.makeDirectory(at: contentsURL)

        let info: [String: Any] = [
            "CFBundleName": appName,
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleShortVersionString": shortVersion,
            "CFBundleVersion": buildVersion
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))

        try TestSupport.makeBinaryFile(at: contentsURL.appendingPathComponent("MacOS/\(appName)"), size: payloadSize)
        return bundleURL
    }

    func testScanApplicationsReadsBundleMetadataAndSize() async throws {
        try makeAppBundle(named: "Foo", bundleIdentifier: "com.example.foo", shortVersion: "1.2.3", buildVersion: "456", payloadSize: 4096)

        let inspector = InstalledAppsInspector(lastUsedProvider: NullAppLastUsedDateProvider())
        let apps = await inspector.scanApplications(in: [applicationsDir.path])

        XCTAssertEqual(apps.count, 1)
        let app = try XCTUnwrap(apps.first)
        XCTAssertEqual(app.name, "Foo")
        XCTAssertEqual(app.bundleIdentifier, "com.example.foo")
        XCTAssertEqual(app.shortVersion, "1.2.3")
        XCTAssertEqual(app.buildVersion, "456")
        XCTAssertEqual(app.path, applicationsDir.appendingPathComponent("Foo.app").path)
        XCTAssertNotNil(app.sizeBytes)
        XCTAssertGreaterThanOrEqual(app.sizeBytes ?? 0, 4096)
        XCTAssertNil(app.lastUsed)
    }

    func testScanApplicationsSortsByNameAndIgnoresNonAppEntries() async throws {
        try makeAppBundle(named: "Zebra", bundleIdentifier: "com.example.zebra", shortVersion: "1.0")
        try makeAppBundle(named: "Apple", bundleIdentifier: "com.example.apple", shortVersion: "1.0")
        try TestSupport.makeFile(at: applicationsDir.appendingPathComponent("readme.txt"), contents: "not an app")

        let inspector = InstalledAppsInspector(lastUsedProvider: NullAppLastUsedDateProvider())
        let apps = await inspector.scanApplications(in: [applicationsDir.path])

        XCTAssertEqual(apps.map(\.name), ["Apple", "Zebra"])
    }

    func testScanApplicationsFallsBackToFilenameWhenInfoPlistMissing() async throws {
        let bundleURL = applicationsDir.appendingPathComponent("NoPlist.app")
        try TestSupport.makeDirectory(at: bundleURL.appendingPathComponent("Contents/MacOS"))

        let inspector = InstalledAppsInspector(lastUsedProvider: NullAppLastUsedDateProvider())
        let apps = await inspector.scanApplications(in: [applicationsDir.path])

        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps.first?.name, "NoPlist")
        XCTAssertNil(apps.first?.bundleIdentifier)
    }

    func testScanApplicationsAcrossMultipleDirectoriesDeduplicatesIdenticalPaths() async throws {
        try makeAppBundle(named: "Foo", bundleIdentifier: "com.example.foo", shortVersion: "1.0")

        let inspector = InstalledAppsInspector(lastUsedProvider: NullAppLastUsedDateProvider())
        let apps = await inspector.scanApplications(in: [applicationsDir.path, applicationsDir.path])

        XCTAssertEqual(apps.count, 1)
    }

    func testScanApplicationsOnMissingDirectoryReturnsEmpty() async {
        let inspector = InstalledAppsInspector(lastUsedProvider: NullAppLastUsedDateProvider())
        let apps = await inspector.scanApplications(in: [tempDir.appendingPathComponent("NoSuchDir").path])
        XCTAssertEqual(apps, [])
    }

    func testLastUsedProviderResultIsThreadedThroughAsSpotlightEvidence() async throws {
        try makeAppBundle(named: "Foo", bundleIdentifier: "com.example.foo", shortVersion: "1.0")
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        let inspector = InstalledAppsInspector(lastUsedProvider: FixedDateProvider(date: fixedDate))
        let apps = await inspector.scanApplications(in: [applicationsDir.path])

        XCTAssertEqual(apps.first?.lastUsed?.date, fixedDate)
        XCTAssertEqual(apps.first?.lastUsed?.source, .spotlightLastUsedDate)
    }

    // MARK: - Detector adapter

    func testInstalledAppsDetectorProducesDescriptiveScanItems() async throws {
        try makeAppBundle(named: "Foo", bundleIdentifier: "com.example.foo", shortVersion: "1.2.3")

        let detector = InstalledAppsDetector(inspector: InstalledAppsInspector(lastUsedProvider: NullAppLastUsedDateProvider()))
        let items = try await detector.scan(context: ScanContext(roots: [applicationsDir.path]))

        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.sourceDetectorID, "poweruser.apps.installed")
        XCTAssertEqual(item.category, "Installed application")
        XCTAssertTrue(item.reason.contains("com.example.foo"))
        XCTAssertTrue(item.reason.contains("1.2.3"))
        XCTAssertTrue(item.reason.contains("not a cleanup suggestion"))
    }

    func testInstalledAppsDetectorFallsBackToDefaultDirectoriesWhenNoRootsGiven() async throws {
        // No roots given -> falls back to InstalledAppsInspector's real
        // default search directories. On a CI/sandbox machine those may or
        // may not exist; this only asserts it never throws.
        let detector = InstalledAppsDetector(inspector: InstalledAppsInspector(lastUsedProvider: NullAppLastUsedDateProvider()))
        _ = try await detector.scan(context: ScanContext(roots: []))
    }
}

private struct FixedDateProvider: AppLastUsedDateProviding {
    let date: Date
    func lastUsedDate(forBundlePath path: String) async -> Date? { date }
}
