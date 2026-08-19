import XCTest
import CoreScanEngine
@testable import CacheCleaner

final class UserLogDetectorTests: XCTestCase {
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

    func testFlagsStaleLog() async throws {
        let log = home + "/Library/Logs/MyApp"
        fm.makeFile(log + "/app.log", contents: "old log line")
        fm.setModificationDate(daysAgo(20), at: log + "/app.log")
        fm.setModificationDate(daysAgo(20), at: log)

        let detector = UserLogDetector(staleAgeThreshold: 7 * 24 * 3600, now: { testReferenceDate })
        let items = try await detector.scan(context: scanContext(roots: [home]))

        let item = items.first { $0.path == log }
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.sourceDetectorID, "junk.logs.user-logs")
        XCTAssertTrue(item?.reason.contains("7+ days") ?? false)
    }

    func testDoesNotFlagRecentlyWrittenLog() async throws {
        let log = home + "/Library/Logs/ActiveApp"
        fm.makeFile(log + "/app.log", contents: "fresh line")
        fm.setModificationDate(testReferenceDate, at: log + "/app.log")
        fm.setModificationDate(testReferenceDate, at: log)

        let detector = UserLogDetector(staleAgeThreshold: 7 * 24 * 3600, now: { testReferenceDate })
        let items = try await detector.scan(context: scanContext(roots: [home]))

        XCTAssertFalse(items.contains { $0.path == log })
    }

    func testDoesNotFlagWhenNestedFileRecentEvenIfTopDirLooksOld() async throws {
        // Simulates an app that keeps appending to a log file inside a
        // subdirectory whose own top-level mtime doesn't reflect that
        // (directory mtime only updates when direct children are added or
        // removed, not when an existing file elsewhere in the tree is
        // written to).
        let log = home + "/Library/Logs/QuietlyActiveApp"
        fm.makeFile(log + "/sub/current.log", contents: "recent line")
        fm.setModificationDate(hoursAgo(2), at: log + "/sub/current.log")
        fm.setModificationDate(daysAgo(30), at: log) // stale-looking top-level mtime

        let detector = UserLogDetector(staleAgeThreshold: 7 * 24 * 3600, now: { testReferenceDate })
        let items = try await detector.scan(context: scanContext(roots: [home]))

        XCTAssertFalse(items.contains { $0.path == log }, "recursive latest-mtime should override the stale-looking top-level directory mtime")
    }

    func testRespectsCancellation() async throws {
        fm.makeFile(home + "/Library/Logs/MyApp/app.log", contents: "x")
        let root = home!

        let task = Task { () -> [ScanItem] in
            try await UserLogDetector().scan(context: ScanContext(roots: [root]))
        }
        task.cancel()
        _ = try await task.value
    }
}
