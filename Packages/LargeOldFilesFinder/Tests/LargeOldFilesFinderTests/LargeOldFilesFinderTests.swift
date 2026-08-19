import XCTest
import CoreScanEngine
@testable import LargeOldFilesFinder

final class LargeOldFilesFinderTests: XCTestCase {
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

    // MARK: - identity

    func testDetectorIdentity() {
        let detector = LargeOldFilesFinder()
        XCTAssertEqual(detector.id, "core.largeOldFiles")
        XCTAssertEqual(detector.category, .largeAndOldFiles)
    }

    // MARK: - config defaults

    func testConfigDefaultsAreSensible() {
        XCTAssertEqual(LargeOldFilesFinderConfig.defaultMinimumSizeBytes, 100 * 1024 * 1024)
        XCTAssertEqual(LargeOldFilesFinderConfig.defaultMinimumAgeDays, 180)
        XCTAssertEqual(
            Set(LargeOldFilesFinderConfig.defaultScopedDirectories),
            ["Downloads", "Desktop", "Documents", "Movies", "Music", "Pictures"]
        )
        // Other detectors' territory must never be part of the default scope.
        XCTAssertFalse(LargeOldFilesFinderConfig.defaultScopedDirectories.contains("Library"))
        XCTAssertTrue(LargeOldFilesFinderConfig.defaultSkippedDirectoryNames.contains("node_modules"))
        XCTAssertTrue(LargeOldFilesFinderConfig.defaultSkippedDirectoryNames.contains(".git"))
        XCTAssertTrue(LargeOldFilesFinderConfig.defaultSkippedDirectoryNames.contains("Library"))
    }

    // MARK: - size filtering

    func testSizeOnlyFilter() async throws {
        fm.makeFile(home + "/Downloads/big.bin", sizeBytes: 2000)
        fm.makeFile(home + "/Downloads/small.bin", sizeBytes: 500)

        let config = LargeOldFilesFinderConfig(minimumSizeBytes: 1000, minimumAgeDays: nil)
        let items = try await LargeOldFilesFinder(config: config, now: { testReferenceDate })
            .scan(context: scanContext(roots: [home]))

        XCTAssertTrue(items.contains { $0.path == home + "/Downloads/big.bin" })
        XCTAssertFalse(items.contains { $0.path == home + "/Downloads/small.bin" })
    }

    // MARK: - age filtering

    func testAgeOnlyFilter() async throws {
        let oldPath = fm.makeFile(home + "/Desktop/old.bin", sizeBytes: 10)
        fm.setModificationDate(daysAgo(40), at: oldPath)
        let newPath = fm.makeFile(home + "/Desktop/new.bin", sizeBytes: 10)
        fm.setModificationDate(daysAgo(5), at: newPath)

        let config = LargeOldFilesFinderConfig(minimumSizeBytes: 0, minimumAgeDays: 30)
        let items = try await LargeOldFilesFinder(config: config, now: { testReferenceDate })
            .scan(context: scanContext(roots: [home]))

        XCTAssertTrue(items.contains { $0.path == oldPath })
        XCTAssertFalse(items.contains { $0.path == newPath })
    }

    // MARK: - combined size + age (the default relationship: AND)

    func testCombinedSizeAndAgeRequiresBoth() async throws {
        let largeOld = fm.makeFile(home + "/Downloads/large-old.bin", sizeBytes: 2000)
        fm.setModificationDate(daysAgo(40), at: largeOld)
        let largeNew = fm.makeFile(home + "/Downloads/large-new.bin", sizeBytes: 2000)
        fm.setModificationDate(daysAgo(5), at: largeNew)
        let smallOld = fm.makeFile(home + "/Downloads/small-old.bin", sizeBytes: 10)
        fm.setModificationDate(daysAgo(40), at: smallOld)

        let config = LargeOldFilesFinderConfig(minimumSizeBytes: 1000, minimumAgeDays: 30)
        let items = try await LargeOldFilesFinder(config: config, now: { testReferenceDate })
            .scan(context: scanContext(roots: [home]))

        XCTAssertEqual(items.map(\.path), [largeOld])
    }

    // MARK: - reason string content

    func testReasonDescribesSizeAndAge() async throws {
        let path = fm.makeFile(home + "/Downloads/movie.mp4", sizeBytes: 5_000_000)
        fm.setModificationDate(daysAgo(400), at: path)

        let config = LargeOldFilesFinderConfig(minimumSizeBytes: 1_000_000, minimumAgeDays: 30)
        let items = try await LargeOldFilesFinder(config: config, now: { testReferenceDate })
            .scan(context: scanContext(roots: [home]))

        guard let item = items.first(where: { $0.path == path }) else {
            return XCTFail("expected movie.mp4 to be reported")
        }
        XCTAssertTrue(item.reason.contains("MB") || item.reason.contains("GB"), item.reason)
        XCTAssertTrue(item.reason.contains("last modified"), item.reason)
        XCTAssertTrue(item.reason.contains("ago"), item.reason)
        XCTAssertEqual(item.lastUsed?.source, .filesystemMTime)
        XCTAssertEqual(item.sizeBytes, 5_000_000)
    }

    // MARK: - type filtering

    func testFileTypeFilter() async throws {
        fm.makeFile(home + "/Downloads/movie.mp4", sizeBytes: 10)
        fm.makeFile(home + "/Downloads/report.pdf", sizeBytes: 10)
        fm.makeFile(home + "/Downloads/archive.zip", sizeBytes: 10)

        let config = LargeOldFilesFinderConfig(
            minimumSizeBytes: 0,
            minimumAgeDays: nil,
            fileTypeFilter: [.video]
        )
        let items = try await LargeOldFilesFinder(config: config, now: { testReferenceDate })
            .scan(context: scanContext(roots: [home]))

        XCTAssertEqual(items.map(\.path), [home + "/Downloads/movie.mp4"])
        XCTAssertEqual(items.first?.category, "Large & Old Files — Video")
    }

    func testFileTypeFilterWithMultipleCategories() async throws {
        fm.makeFile(home + "/Downloads/movie.mkv", sizeBytes: 10)
        fm.makeFile(home + "/Downloads/image.png", sizeBytes: 10)
        fm.makeFile(home + "/Downloads/notes.txt", sizeBytes: 10)

        let config = LargeOldFilesFinderConfig(
            minimumSizeBytes: 0,
            minimumAgeDays: nil,
            fileTypeFilter: [.video, .image]
        )
        let items = try await LargeOldFilesFinder(config: config, now: { testReferenceDate })
            .scan(context: scanContext(roots: [home]))

        XCTAssertEqual(
            Set(items.map(\.path)),
            [home + "/Downloads/movie.mkv", home + "/Downloads/image.png"]
        )
    }

    // MARK: - not re-surfacing other detectors' territory

    func testSkipsOtherDetectorsTerritoryByDefault() async throws {
        // Library is not even part of the default scoped roots.
        fm.makeFile(home + "/Library/Caches/huge-cache-file.bin", sizeBytes: 2000)
        // node_modules nested inside a scoped root IS skipped by name.
        let nested = fm.makeFile(home + "/Downloads/project/node_modules/pkg/huge.bin", sizeBytes: 2000)
        fm.setModificationDate(daysAgo(400), at: nested)

        let config = LargeOldFilesFinderConfig(minimumSizeBytes: 0, minimumAgeDays: nil)
        let items = try await LargeOldFilesFinder(config: config, now: { testReferenceDate })
            .scan(context: scanContext(roots: [home]))

        XCTAssertFalse(items.contains { $0.path.contains("Library/Caches") })
        XCTAssertFalse(items.contains { $0.path.contains("node_modules") })
    }

    func testSkipsBundleDirectoriesByExtension() async throws {
        let insideApp = fm.makeFile(home + "/Downloads/Legacy.app/Contents/Resources/huge.bin", sizeBytes: 2000)
        fm.setModificationDate(daysAgo(400), at: insideApp)

        let config = LargeOldFilesFinderConfig(minimumSizeBytes: 0, minimumAgeDays: nil)
        let items = try await LargeOldFilesFinder(config: config, now: { testReferenceDate })
            .scan(context: scanContext(roots: [home]))

        XCTAssertFalse(items.contains { $0.path == insideApp })
    }

    func testSkipsHiddenFilesByDefault() async throws {
        fm.makeFile(home + "/Downloads/.hidden-big-file", sizeBytes: 2000)

        let config = LargeOldFilesFinderConfig(minimumSizeBytes: 0, minimumAgeDays: nil)
        let items = try await LargeOldFilesFinder(config: config, now: { testReferenceDate })
            .scan(context: scanContext(roots: [home]))

        XCTAssertTrue(items.isEmpty)
    }

    func testDoesNotFollowSymlinks() async throws {
        let outsideDir = home + "/outside-target"
        let outsideFile = fm.makeFile(outsideDir + "/secret.bin", sizeBytes: 2000)
        fm.setModificationDate(daysAgo(400), at: outsideFile)
        fm.makeSymlink(at: home + "/Downloads/link-to-outside", to: outsideDir)

        let config = LargeOldFilesFinderConfig(minimumSizeBytes: 0, minimumAgeDays: nil)
        let items = try await LargeOldFilesFinder(config: config, now: { testReferenceDate })
            .scan(context: scanContext(roots: [home]))

        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - depth bound

    func testRespectsMaxDepth() async throws {
        let shallow = fm.makeFile(home + "/Downloads/a/b/shallow.bin", sizeBytes: 10)
        let deep = fm.makeFile(home + "/Downloads/a/b/c/deep.bin", sizeBytes: 10)

        let config = LargeOldFilesFinderConfig(minimumSizeBytes: 0, minimumAgeDays: nil, maxDepth: 2)
        let items = try await LargeOldFilesFinder(config: config, now: { testReferenceDate })
            .scan(context: scanContext(roots: [home]))

        XCTAssertTrue(items.contains { $0.path == shallow })
        XCTAssertFalse(items.contains { $0.path == deep })
    }

    // MARK: - no matches

    func testReturnsNoItemsWhenNothingQualifies() async throws {
        fm.makeFile(home + "/Downloads/tiny.bin", sizeBytes: 10)

        let items = try await LargeOldFilesFinder().scan(context: scanContext(roots: [home]))
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - cancellation

    func testWalkFilesRespectsCancellationImmediately() {
        fm.makeFile(home + "/Downloads/file.bin", sizeBytes: 10)
        var visited: [String] = []

        LargeOldFilesFS.walkFiles(
            under: home + "/Downloads",
            maxDepth: 12,
            skippingDirectoryNames: [],
            skippingDirectoryExtensions: [],
            includeHidden: false,
            isCancelled: { true }
        ) { path in
            visited.append(path)
        }

        XCTAssertTrue(visited.isEmpty)
    }

    func testScanRespectsCancellation() async throws {
        fm.makeFile(home + "/Downloads/file.bin", sizeBytes: 10)
        let root = home!

        let task = Task { () -> [ScanItem] in
            try await LargeOldFilesFinder(config: LargeOldFilesFinderConfig(minimumSizeBytes: 0, minimumAgeDays: nil))
                .scan(context: scanContext(roots: [root]))
        }
        task.cancel()
        // Should complete promptly without throwing/hanging even when
        // cancelled immediately; content isn't asserted since cancellation
        // may race with the (very fast) scan on a small tree.
        _ = try await task.value
    }
}
