import XCTest
import CoreScanEngine
@testable import CacheCleaner

final class IncompleteDownloadDetectorTests: XCTestCase {
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

    func testFlagsOldCrdownloadFile() async throws {
        let path = home + "/Downloads/movie.mp4.crdownload"
        fm.makeFile(path, contents: "partial bytes")
        fm.setModificationDate(daysAgo(2), at: path)

        let detector = IncompleteDownloadDetector(staleAgeThreshold: 24 * 3600, now: { testReferenceDate })
        let items = try await detector.scan(context: scanContext(roots: [home]))

        let item = items.first { $0.path == path }
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.sourceDetectorID, "junk.downloads.incomplete")
    }

    func testDoesNotFlagRecentCrdownloadFile() async throws {
        let path = home + "/Downloads/movie.mp4.crdownload"
        fm.makeFile(path, contents: "partial bytes")
        fm.setModificationDate(testReferenceDate.addingTimeInterval(-30), at: path) // 30 seconds ago

        let detector = IncompleteDownloadDetector(staleAgeThreshold: 24 * 3600, now: { testReferenceDate })
        let items = try await detector.scan(context: scanContext(roots: [home]))

        XCTAssertFalse(items.contains { $0.path == path }, "a download from 30 seconds ago should look active, not abandoned")
    }

    func testFlagsEveryKnownIncompleteDownloadExtension() async throws {
        let names = ["a.dmg.download", "b.zip.crdownload", "c.iso.part", "d.pkg.partial"]
        for name in names {
            let path = home + "/Downloads/" + name
            fm.makeFile(path, contents: "x")
            fm.setModificationDate(daysAgo(5), at: path)
        }

        let detector = IncompleteDownloadDetector(staleAgeThreshold: 24 * 3600, now: { testReferenceDate })
        let items = try await detector.scan(context: scanContext(roots: [home]))

        let flaggedNames = Set(items.map { ($0.path as NSString).lastPathComponent })
        XCTAssertEqual(flaggedNames, Set(names))
    }

    func testIgnoresCompletedDownloads() async throws {
        let path = home + "/Downloads/report.pdf"
        fm.makeFile(path, contents: "x")
        fm.setModificationDate(daysAgo(5), at: path)

        let detector = IncompleteDownloadDetector(staleAgeThreshold: 24 * 3600, now: { testReferenceDate })
        let items = try await detector.scan(context: scanContext(roots: [home]))

        XCTAssertTrue(items.isEmpty)
    }

    func testRespectsCancellation() async throws {
        fm.makeFile(home + "/Downloads/foo.crdownload", contents: "x")
        let root = home!

        let task = Task { () -> [ScanItem] in
            try await IncompleteDownloadDetector().scan(context: ScanContext(roots: [root]))
        }
        task.cancel()
        _ = try await task.value
    }
}
