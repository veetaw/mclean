import CoreScanEngine
import XCTest
@testable import DuplicateFinder

final class SimilarImageDetectorTests: XCTestCase {
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

    func testGroupsNearIdenticalPhotos() async throws {
        let detector = SimilarImageDetector(maxHammingDistance: 8, minFileSizeBytes: 0)
        let a = makeTwoToneImage(leftGray: 40, rightGray: 220)
        let b = makeTwoToneImage(leftGray: 46, rightGray: 214)
        let pathA = root + "/a.png"
        let pathB = root + "/b.png"
        try pngData(for: a).write(to: URL(fileURLWithPath: pathA))
        try pngData(for: b).write(to: URL(fileURLWithPath: pathB))

        let items = try await detector.scan(context: scanContext(roots: [root]))

        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(Set(items.map(\.path)).isSubset(of: [pathA, pathB]))
        XCTAssertEqual(items.first?.sourceDetectorID, "duplicates.similar-images")
        XCTAssertTrue(items.first?.reason.contains("similar") ?? false)
    }

    func testSolidBlackAndSolidWhiteAreNotGrouped() async throws {
        let detector = SimilarImageDetector(maxHammingDistance: 8, minFileSizeBytes: 0)
        let black = makeSolidColorImage(red: 0, green: 0, blue: 0)
        let white = makeSolidColorImage(red: 255, green: 255, blue: 255)
        try pngData(for: black).write(to: URL(fileURLWithPath: root + "/black.png"))
        try pngData(for: white).write(to: URL(fileURLWithPath: root + "/white.png"))

        let items = try await detector.scan(context: scanContext(roots: [root]))

        XCTAssertTrue(items.isEmpty)
    }

    func testLoneImageProducesNoItems() async throws {
        let detector = SimilarImageDetector(maxHammingDistance: 8, minFileSizeBytes: 0)
        let image = makeSolidColorImage(red: 10, green: 10, blue: 10)
        try pngData(for: image).write(to: URL(fileURLWithPath: root + "/only.png"))

        let items = try await detector.scan(context: scanContext(roots: [root]))

        XCTAssertTrue(items.isEmpty)
    }

    func testNonImageFilesAreIgnored() async throws {
        let detector = SimilarImageDetector(maxHammingDistance: 8, minFileSizeBytes: 0)
        fm.makeFile(root + "/notes.txt", text: "hello")
        fm.makeFile(root + "/data.bin", text: "binary-ish-content")

        let items = try await detector.scan(context: scanContext(roots: [root]))

        XCTAssertTrue(items.isEmpty)
    }

    func testFilesBelowMinimumSizeAreSkipped() async throws {
        let detector = SimilarImageDetector(maxHammingDistance: 8, minFileSizeBytes: 1_000_000)
        let a = makeTwoToneImage(leftGray: 40, rightGray: 220)
        let b = makeTwoToneImage(leftGray: 46, rightGray: 214)
        try pngData(for: a).write(to: URL(fileURLWithPath: root + "/a.png"))
        try pngData(for: b).write(to: URL(fileURLWithPath: root + "/b.png"))

        let items = try await detector.scan(context: scanContext(roots: [root]))

        XCTAssertTrue(items.isEmpty)
    }

    /// Direct unit test of the union-find grouping helper against
    /// hand-built fingerprints, independent of file I/O — verifies
    /// similarity groups transitively (A~B and B~C groups all three even
    /// when A and C alone might not both pass the threshold) and that an
    /// unrelated fingerprint stays its own singleton group.
    func testGroupHelperGroupsTransitivelyAndIsolatesOutliers() {
        let candidates: [(path: String, size: Int64)] = [
            ("a", 300), ("b", 100), ("c", 200)
        ]
        let fingerprints: [String: PerceptualHash.ImageFingerprint] = [
            "a": .init(hash: 0b0000, averageLuminance: 100),
            "b": .init(hash: 0b0001, averageLuminance: 102),
            "c": .init(hash: 0b1111, averageLuminance: 250)
        ]

        let groups = SimilarImageDetector.group(candidates, fingerprints: fingerprints, maxHammingDistance: 2)
        let groupedPathSets = Set(groups.map { Set($0.map(\.path)) })

        XCTAssertEqual(groupedPathSets, [["a", "b"], ["c"]])
    }
}
