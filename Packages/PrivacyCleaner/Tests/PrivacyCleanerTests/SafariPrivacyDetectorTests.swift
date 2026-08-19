import XCTest
import CoreScanEngine
@testable import PrivacyCleaner

final class SafariPrivacyDetectorTests: XCTestCase {
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

    func testFindsCacheCookiesAndHistoryWhenPresent() async throws {
        fm.makeFile(home + "/Library/Caches/com.apple.Safari/fsCachedData/marker")
        fm.makeFile(home + "/Library/Cookies/Cookies.binarycookies", contents: "cookie-bytes")
        fm.makeFile(home + "/Library/Safari/History.db", contents: "sqlite-bytes")

        let detector = SafariPrivacyDetector(runningCheck: neverRunning())
        let items = try await detector.scan(context: scanContext(roots: [home]))

        XCTAssertTrue(items.contains { $0.sourceDetectorID == "privacy.safari.cache" })
        XCTAssertTrue(items.contains { $0.sourceDetectorID == "privacy.safari.cookies" })
        XCTAssertTrue(items.contains { $0.sourceDetectorID == "privacy.safari.history" })
    }

    func testMissingSafariDataProducesNoItems() async throws {
        // `home` exists but has none of Safari's directories/files.
        let detector = SafariPrivacyDetector(runningCheck: neverRunning())
        let items = try await detector.scan(context: scanContext(roots: [home]))
        XCTAssertTrue(items.isEmpty)
    }

    func testCookiesReasonWarnsAboutAllSitesWhenPreserveListNonEmpty() async throws {
        fm.makeFile(home + "/Library/Cookies/Cookies.binarycookies", contents: "cookie-bytes")

        let detector = SafariPrivacyDetector(
            preserveList: SitePreserveList(domains: ["example.com"]),
            runningCheck: neverRunning()
        )
        let items = try await detector.scan(context: scanContext(roots: [home]))

        let cookies = items.first { $0.sourceDetectorID == "privacy.safari.cookies" }
        XCTAssertNotNil(cookies)
        XCTAssertTrue(cookies!.reason.contains("cannot be honored"))
    }

    func testRunningSafariAddsWarningToReason() async throws {
        fm.makeFile(home + "/Library/Caches/com.apple.Safari/fsCachedData/marker")

        let detector = SafariPrivacyDetector(runningCheck: alwaysRunning([BrowserBundleID.safari]))
        let items = try await detector.scan(context: scanContext(roots: [home]))

        let cache = items.first { $0.sourceDetectorID == "privacy.safari.cache" }
        XCTAssertNotNil(cache)
        XCTAssertTrue(cache!.reason.contains("currently running"))
    }

    func testNotRunningSafariDoesNotAddWarning() async throws {
        fm.makeFile(home + "/Library/Caches/com.apple.Safari/fsCachedData/marker")

        let detector = SafariPrivacyDetector(runningCheck: neverRunning())
        let items = try await detector.scan(context: scanContext(roots: [home]))

        let cache = items.first { $0.sourceDetectorID == "privacy.safari.cache" }
        XCTAssertNotNil(cache)
        XCTAssertFalse(cache!.reason.contains("currently running"))
    }
}
