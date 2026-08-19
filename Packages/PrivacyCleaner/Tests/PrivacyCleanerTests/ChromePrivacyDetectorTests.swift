import XCTest
import CoreScanEngine
@testable import PrivacyCleaner

final class ChromePrivacyDetectorTests: XCTestCase {
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

    private var chromeDefault: String { home + "/Library/Application Support/Google/Chrome/Default" }

    func testFindsCacheCookiesAndHistoryInDefaultProfile() async throws {
        fm.makeFile(chromeDefault + "/Cache/data_0")
        fm.makeFile(chromeDefault + "/Cookies", contents: "sqlite-bytes")
        fm.makeFile(chromeDefault + "/History", contents: "sqlite-bytes")

        let detector = ChromePrivacyDetector(runningCheck: neverRunning())
        let items = try await detector.scan(context: scanContext(roots: [home]))

        XCTAssertTrue(items.contains { $0.sourceDetectorID == "privacy.chrome.cache" && $0.path == chromeDefault + "/Cache" })
        XCTAssertTrue(items.contains { $0.sourceDetectorID == "privacy.chrome.cookies" })
        XCTAssertTrue(items.contains { $0.sourceDetectorID == "privacy.chrome.history" })
    }

    func testEnumeratesAdditionalProfiles() async throws {
        fm.makeFile(chromeDefault + "/Cookies", contents: "sqlite-bytes")
        fm.makeFile(home + "/Library/Application Support/Google/Chrome/Profile 1/Cookies", contents: "sqlite-bytes")
        fm.makeFile(home + "/Library/Application Support/Google/Chrome/Profile 2/Cookies", contents: "sqlite-bytes")

        let detector = ChromePrivacyDetector(runningCheck: neverRunning())
        let items = try await detector.scan(context: scanContext(roots: [home]))

        let cookiePaths = Set(items.filter { $0.sourceDetectorID == "privacy.chrome.cookies" }.map(\.path))
        XCTAssertEqual(cookiePaths, [
            chromeDefault + "/Cookies",
            home + "/Library/Application Support/Google/Chrome/Profile 1/Cookies",
            home + "/Library/Application Support/Google/Chrome/Profile 2/Cookies"
        ])
    }

    func testMissingChromeProducesNoItems() async throws {
        let detector = ChromePrivacyDetector(runningCheck: neverRunning())
        let items = try await detector.scan(context: scanContext(roots: [home]))
        XCTAssertTrue(items.isEmpty)
    }

    func testIndexedDBPreservedOriginIsExcludedButOthersAreNot() async throws {
        fm.makeFile(chromeDefault + "/IndexedDB/https_example.com_0.indexeddb.leveldb/marker")
        fm.makeFile(chromeDefault + "/IndexedDB/https_other.com_0.indexeddb.leveldb/marker")

        let detector = ChromePrivacyDetector(
            preserveList: SitePreserveList(domains: ["example.com"]),
            runningCheck: neverRunning()
        )
        let items = try await detector.scan(context: scanContext(roots: [home]))

        let indexedDBPaths = Set(items.filter { $0.sourceDetectorID == "privacy.chrome.indexeddb" }.map(\.path))
        XCTAssertEqual(indexedDBPaths, [chromeDefault + "/IndexedDB/https_other.com_0.indexeddb.leveldb"])
    }

    func testIndexedDBWithoutPreserveListIncludesEverySite() async throws {
        fm.makeFile(chromeDefault + "/IndexedDB/https_example.com_0.indexeddb.leveldb/marker")
        fm.makeFile(chromeDefault + "/IndexedDB/https_other.com_0.indexeddb.leveldb/marker")

        let detector = ChromePrivacyDetector(runningCheck: neverRunning())
        let items = try await detector.scan(context: scanContext(roots: [home]))

        let indexedDBPaths = Set(items.filter { $0.sourceDetectorID == "privacy.chrome.indexeddb" }.map(\.path))
        XCTAssertEqual(indexedDBPaths, [
            chromeDefault + "/IndexedDB/https_example.com_0.indexeddb.leveldb",
            chromeDefault + "/IndexedDB/https_other.com_0.indexeddb.leveldb"
        ])
    }

    func testParseIndexedDBOriginExtractsHost() {
        XCTAssertEqual(ChromePrivacyDetector.parseIndexedDBOrigin("https_example.com_0.indexeddb.leveldb"), "example.com")
        XCTAssertEqual(ChromePrivacyDetector.parseIndexedDBOrigin("https_example.com_0.indexeddb.blob"), "example.com")
        XCTAssertNil(ChromePrivacyDetector.parseIndexedDBOrigin("some-unrelated-folder"))
    }

    func testRunningChromeAddsWarningToReason() async throws {
        fm.makeFile(chromeDefault + "/Cookies", contents: "sqlite-bytes")

        let detector = ChromePrivacyDetector(runningCheck: alwaysRunning([BrowserBundleID.chrome]))
        let items = try await detector.scan(context: scanContext(roots: [home]))

        let cookies = items.first { $0.sourceDetectorID == "privacy.chrome.cookies" }
        XCTAssertNotNil(cookies)
        XCTAssertTrue(cookies!.reason.contains("currently running"))
    }
}
