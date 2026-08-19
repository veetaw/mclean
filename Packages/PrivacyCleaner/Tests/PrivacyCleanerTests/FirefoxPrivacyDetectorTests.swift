import XCTest
import CoreScanEngine
@testable import PrivacyCleaner

final class FirefoxPrivacyDetectorTests: XCTestCase {
    var home: String!
    let fm = FileManager.default

    override func setUp() {
        super.setUp()
        home = TempHome.make()
    }

    override func tearDown() {
        TempHome.cleanup(home)
        home = nil
        super.tearDown()
    }

    private var profile: String { home + "/Library/Application Support/Firefox/Profiles/abcd1234.default-release" }

    func testFindsCacheCookiesAndHistoryInDefaultProfile() async throws {
        fm.makeFile(profile + "/cache2/entries/marker")
        fm.makeFile(profile + "/cookies.sqlite", contents: "sqlite-bytes")
        fm.makeFile(profile + "/places.sqlite", contents: "sqlite-bytes")

        let detector = FirefoxPrivacyDetector(runningCheck: neverRunning())
        let items = try await detector.scan(context: scanContext(roots: [home]))

        XCTAssertTrue(items.contains { $0.sourceDetectorID == "privacy.firefox.cache" })
        XCTAssertTrue(items.contains { $0.sourceDetectorID == "privacy.firefox.cookies" })
        XCTAssertTrue(items.contains { $0.sourceDetectorID == "privacy.firefox.history" })
    }

    func testHistoryReasonMentionsBookmarksCaveat() async throws {
        fm.makeFile(profile + "/places.sqlite", contents: "sqlite-bytes")

        let detector = FirefoxPrivacyDetector(runningCheck: neverRunning())
        let items = try await detector.scan(context: scanContext(roots: [home]))

        let history = items.first { $0.sourceDetectorID == "privacy.firefox.history" }
        XCTAssertNotNil(history)
        XCTAssertTrue(history!.reason.localizedCaseInsensitiveContains("bookmarks"))
    }

    func testMissingFirefoxProducesNoItems() async throws {
        let detector = FirefoxPrivacyDetector(runningCheck: neverRunning())
        let items = try await detector.scan(context: scanContext(roots: [home]))
        XCTAssertTrue(items.isEmpty)
    }

    func testOriginStoragePreservedSiteIsExcludedButOthersAreNot() async throws {
        fm.makeFile(profile + "/storage/default/https+++example.com/marker")
        fm.makeFile(profile + "/storage/default/https+++other.com/marker")

        let detector = FirefoxPrivacyDetector(
            preserveList: SitePreserveList(domains: ["example.com"]),
            runningCheck: neverRunning()
        )
        let items = try await detector.scan(context: scanContext(roots: [home]))

        let storagePaths = Set(items.filter { $0.sourceDetectorID == "privacy.firefox.origin-storage" }.map(\.path))
        XCTAssertEqual(storagePaths, [profile + "/storage/default/https+++other.com"])
    }

    func testOriginStorageWithoutPreserveListIncludesEverySite() async throws {
        fm.makeFile(profile + "/storage/default/https+++example.com/marker")
        fm.makeFile(profile + "/storage/default/https+++other.com/marker")

        let detector = FirefoxPrivacyDetector(runningCheck: neverRunning())
        let items = try await detector.scan(context: scanContext(roots: [home]))

        let storagePaths = Set(items.filter { $0.sourceDetectorID == "privacy.firefox.origin-storage" }.map(\.path))
        XCTAssertEqual(storagePaths, [
            profile + "/storage/default/https+++example.com",
            profile + "/storage/default/https+++other.com"
        ])
    }

    func testParseStorageOriginExtractsHost() {
        XCTAssertEqual(FirefoxPrivacyDetector.parseStorageOrigin("https+++example.com"), "example.com")
        XCTAssertEqual(FirefoxPrivacyDetector.parseStorageOrigin("https+++example.com+8080"), "example.com")
        XCTAssertEqual(FirefoxPrivacyDetector.parseStorageOrigin("https+++example.com^userContextId=2"), "example.com")
        XCTAssertNil(FirefoxPrivacyDetector.parseStorageOrigin("some-unrelated-folder"))
    }

    func testRunningFirefoxAddsWarningToReason() async throws {
        fm.makeFile(profile + "/cookies.sqlite", contents: "sqlite-bytes")

        let detector = FirefoxPrivacyDetector(runningCheck: alwaysRunning([BrowserBundleID.firefox]))
        let items = try await detector.scan(context: scanContext(roots: [home]))

        let cookies = items.first { $0.sourceDetectorID == "privacy.firefox.cookies" }
        XCTAssertNotNil(cookies)
        XCTAssertTrue(cookies!.reason.contains("currently running"))
    }
}
