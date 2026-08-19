import XCTest
import CoreScanEngine
@testable import CacheCleaner

final class TempFilesDetectorTests: XCTestCase {
    var home: String!
    var systemTemp: String!
    let fm = FileManager.default

    override func setUp() {
        super.setUp()
        home = TempHome.make()
        systemTemp = TempHome.make()
    }

    override func tearDown() {
        TempHome.cleanup(home)
        TempHome.cleanup(systemTemp)
        home = nil
        systemTemp = nil
        super.tearDown()
    }

    func testFlagsOldSystemTempEntry() async throws {
        let entry = systemTemp + "/com.example.stale-work"
        fm.makeFile(entry + "/scratch.dat", contents: "x")
        fm.setModificationDate(daysAgo(10), at: entry + "/scratch.dat")
        fm.setModificationDate(daysAgo(10), at: entry)

        let detector = TempFilesDetector(
            staleAgeThreshold: 3 * 24 * 3600,
            systemTempDirectoryPath: systemTemp,
            now: { testReferenceDate }
        )
        let items = try await detector.scan(context: scanContext(roots: [home]))

        let item = items.first { $0.path == entry }
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.sourceDetectorID, "junk.temp.system-temp-directory")
    }

    func testDoesNotFlagRecentSystemTempEntry() async throws {
        let entry = systemTemp + "/com.example.active-work"
        fm.makeFile(entry + "/scratch.dat", contents: "x")
        fm.setModificationDate(testReferenceDate, at: entry + "/scratch.dat")
        fm.setModificationDate(testReferenceDate, at: entry)

        let detector = TempFilesDetector(
            staleAgeThreshold: 3 * 24 * 3600,
            systemTempDirectoryPath: systemTemp,
            now: { testReferenceDate }
        )
        let items = try await detector.scan(context: scanContext(roots: [home]))

        XCTAssertFalse(items.contains { $0.path == entry })
    }

    func testFlagsOldTemporaryItemsEntry() async throws {
        let entry = home + "/Library/Caches/TemporaryItems/leftover"
        fm.makeFile(entry, contents: "x")
        fm.setModificationDate(daysAgo(10), at: entry)

        let detector = TempFilesDetector(
            staleAgeThreshold: 3 * 24 * 3600,
            systemTempDirectoryPath: systemTemp,
            now: { testReferenceDate }
        )
        let items = try await detector.scan(context: scanContext(roots: [home]))

        let item = items.first { $0.path == entry }
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.sourceDetectorID, "junk.temp.temporary-items")
    }

    func testDoesNotFlagWhenActiveProcessStillWritingInsideOldLookingDirectory() async throws {
        let entry = systemTemp + "/com.example.long-running-job"
        fm.makeFile(entry + "/progress.log", contents: "in progress")
        fm.setModificationDate(hoursAgo(1), at: entry + "/progress.log")
        fm.setModificationDate(daysAgo(30), at: entry)

        let detector = TempFilesDetector(
            staleAgeThreshold: 3 * 24 * 3600,
            systemTempDirectoryPath: systemTemp,
            now: { testReferenceDate }
        )
        let items = try await detector.scan(context: scanContext(roots: [home]))

        XCTAssertFalse(items.contains { $0.path == entry })
    }

    func testRespectsCancellation() async throws {
        fm.makeFile(systemTemp + "/entry/file.dat", contents: "x")
        let root = home!
        let temp = systemTemp!

        let task = Task { () -> [ScanItem] in
            try await TempFilesDetector(systemTempDirectoryPath: temp).scan(context: ScanContext(roots: [root]))
        }
        task.cancel()
        _ = try await task.value
    }
}
