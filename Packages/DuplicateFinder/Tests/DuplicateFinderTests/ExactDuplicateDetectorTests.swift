import CoreScanEngine
import XCTest
@testable import DuplicateFinder

final class ExactDuplicateDetectorTests: XCTestCase {
    var root: String!
    let fm = FileManager.default

    override func setUp() {
        super.setUp()
        root = TempRoot.make()
    }

    override func tearDown() {
        TempRoot.cleanup(root)
        root = nil
        super.tearDown()
    }

    func testIdenticalFilesAreGroupedAsDuplicates() async throws {
        let content = "duplicate-content-".appending(String(repeating: "x", count: 5000))
        fm.makeFile(root + "/a.txt", text: content)
        fm.makeFile(root + "/b.txt", text: content)
        fm.setModificationDate(daysAgo(10), at: root + "/a.txt")
        fm.setModificationDate(daysAgo(1), at: root + "/b.txt")

        let items = try await ExactDuplicateDetector().scan(context: scanContext(roots: [root]))

        // "a.txt" is older, so it's kept as the original; only "b.txt" is flagged.
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.path, root + "/b.txt")
        XCTAssertTrue(items.first?.reason.contains("a.txt") ?? false)
        XCTAssertEqual(items.first?.sourceDetectorID, "duplicates.exact")
    }

    func testDistinctFilesAreNotGrouped() async throws {
        fm.makeFile(root + "/a.txt", text: String(repeating: "a", count: 5000))
        fm.makeFile(root + "/b.txt", text: String(repeating: "b", count: 5000))

        let items = try await ExactDuplicateDetector().scan(context: scanContext(roots: [root]))

        XCTAssertTrue(items.isEmpty)
    }

    func testFilesOfDifferentSizesAreNeverGroupedEvenWithOverlappingContent() async throws {
        let shared = String(repeating: "shared-", count: 1000)
        fm.makeFile(root + "/short.txt", text: shared)
        fm.makeFile(root + "/long.txt", text: shared + "extra-tail-bytes-that-change-the-size")

        let items = try await ExactDuplicateDetector().scan(context: scanContext(roots: [root]))

        // Different sizes -> never hashed against each other -> no items,
        // even though their content overlaps heavily.
        XCTAssertTrue(items.isEmpty)
    }

    func testLoneFileProducesNoItems() async throws {
        fm.makeFile(root + "/only.txt", text: String(repeating: "z", count: 5000))

        let items = try await ExactDuplicateDetector().scan(context: scanContext(roots: [root]))

        XCTAssertTrue(items.isEmpty)
    }

    func testThreeWayDuplicateGroupFlagsOnlyTheTwoNonOriginals() async throws {
        let content = String(repeating: "triple-", count: 2000)
        fm.makeFile(root + "/first.txt", text: content)
        fm.makeFile(root + "/second.txt", text: content)
        fm.makeFile(root + "/third.txt", text: content)
        fm.setModificationDate(daysAgo(30), at: root + "/first.txt")
        fm.setModificationDate(daysAgo(20), at: root + "/second.txt")
        fm.setModificationDate(daysAgo(10), at: root + "/third.txt")

        let items = try await ExactDuplicateDetector().scan(context: scanContext(roots: [root]))

        XCTAssertEqual(Set(items.map(\.path)), [root + "/second.txt", root + "/third.txt"])
        XCTAssertTrue(items.allSatisfy { $0.reason.contains("first.txt") })
    }

    func testFilesSmallerThanMinimumSizeAreSkipped() async throws {
        let detector = ExactDuplicateDetector(minFileSizeBytes: 1_000_000)
        fm.makeFile(root + "/a.txt", text: String(repeating: "x", count: 5000))
        fm.makeFile(root + "/b.txt", text: String(repeating: "x", count: 5000))

        let items = try await detector.scan(context: scanContext(roots: [root]))

        XCTAssertTrue(items.isEmpty)
    }

    func testEmptyRootProducesNoItems() async throws {
        let items = try await ExactDuplicateDetector().scan(context: scanContext(roots: [root]))
        XCTAssertTrue(items.isEmpty)
    }
}
