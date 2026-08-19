import XCTest
import CoreScanEngine
@testable import CacheCleaner

final class UserAppCacheDetectorTests: XCTestCase {
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

    func testFlagsStaleCacheDirectory() async throws {
        let cache = home + "/Library/Caches/com.example.myapp"
        fm.makeFile(cache + "/data.bin", contents: "x")
        fm.setModificationDate(daysAgo(30), at: cache + "/data.bin")
        fm.setModificationDate(daysAgo(30), at: cache)

        let detector = UserAppCacheDetector(
            staleAgeThreshold: 14 * 24 * 3600,
            largeSizeThreshold: 100 * 1024 * 1024,
            now: { testReferenceDate }
        )
        let items = try await detector.scan(context: scanContext(roots: [home]))

        let item = items.first { $0.path == cache }
        XCTAssertNotNil(item)
        XCTAssertTrue(item?.reason.contains("touched") ?? false)
        XCTAssertEqual(item?.sourceDetectorID, "junk.cache.user-app-cache")
    }

    func testFlagsLargeCacheDirectoryEvenIfRecentlyTouched() async throws {
        let cache = home + "/Library/Caches/com.example.bigcache"
        let bigContents = String(repeating: "a", count: 5000)
        fm.makeFile(cache + "/blob.bin", contents: bigContents)
        fm.setModificationDate(testReferenceDate, at: cache + "/blob.bin")
        fm.setModificationDate(testReferenceDate, at: cache)

        let detector = UserAppCacheDetector(
            staleAgeThreshold: 14 * 24 * 3600,
            largeSizeThreshold: 1000,
            now: { testReferenceDate }
        )
        let items = try await detector.scan(context: scanContext(roots: [home]))

        let item = items.first { $0.path == cache }
        XCTAssertNotNil(item)
        XCTAssertTrue(item?.reason.contains("grown") ?? false)
    }

    func testDoesNotFlagRecentSmallCache() async throws {
        let cache = home + "/Library/Caches/com.example.freshcache"
        fm.makeFile(cache + "/tiny.txt", contents: "x")
        fm.setModificationDate(testReferenceDate, at: cache + "/tiny.txt")
        fm.setModificationDate(testReferenceDate, at: cache)

        let detector = UserAppCacheDetector(
            staleAgeThreshold: 14 * 24 * 3600,
            largeSizeThreshold: 100 * 1024 * 1024,
            now: { testReferenceDate }
        )
        let items = try await detector.scan(context: scanContext(roots: [home]))

        XCTAssertFalse(items.contains { $0.path == cache })
    }

    func testExcludesDirectoriesOwnedByOtherDetectorPackages() async throws {
        let owned = [
            "pip", "pypoetry", "go-build", "Homebrew", "JetBrains", "Yarn",
            "fastlane", "CocoaPods", "Google", "TemporaryItems"
        ]
        for name in owned {
            let path = home + "/Library/Caches/" + name
            fm.makeFile(path + "/whatever.bin", contents: "x")
            fm.setModificationDate(daysAgo(90), at: path + "/whatever.bin")
            fm.setModificationDate(daysAgo(90), at: path)
        }

        let detector = UserAppCacheDetector(
            staleAgeThreshold: 14 * 24 * 3600,
            largeSizeThreshold: 100 * 1024 * 1024,
            now: { testReferenceDate }
        )
        let items = try await detector.scan(context: scanContext(roots: [home]))

        XCTAssertTrue(items.isEmpty, "should not re-report directories owned by other detector packages: \(items.map(\.path))")
    }

    func testRespectsCancellation() async throws {
        fm.makeFile(home + "/Library/Caches/com.example.myapp/data.bin", contents: "x")
        let root = home!

        let task = Task { () -> [ScanItem] in
            try await UserAppCacheDetector().scan(context: ScanContext(roots: [root]))
        }
        task.cancel()
        _ = try await task.value
    }
}
