import XCTest
import CoreScanEngine
@testable import CacheCleaner

final class CacheCleanerRegistryTests: XCTestCase {
    func testAllReturnsOneDetectorPerSubAreaWithUniqueIDs() {
        let detectors = CacheCleanerRegistry.all()
        let ids = detectors.map(\.id)

        XCTAssertEqual(Set(ids).count, ids.count, "detector ids must be unique")
        XCTAssertEqual(Set(ids), [
            "junk.cache.user-app-cache", "junk.logs.user-logs", "junk.temp.temp-files",
            "junk.downloads.incomplete", "junk.languagepacks.unused-lproj"
        ])
        for detector in detectors {
            XCTAssertEqual(detector.category, .systemJunk)
            XCTAssertFalse(detector.displayName.isEmpty)
        }
    }

    func testEveryRegisteredDetectorScansEmptyRootWithoutThrowing() async throws {
        let home = TempHome.make()
        defer { TempHome.cleanup(home) }

        for detector in CacheCleanerRegistry.all() {
            // Not asserting emptiness here: `LanguagePackDetector` and
            // `TempFilesDetector`'s default construction (as used by
            // `CacheCleanerRegistry.all()`) point at the real `/Applications`
            // and the real system temp directory respectively — neither is
            // home-relative, so a sandboxed `home` root doesn't isolate them
            // (see each type's own, fully-hermetic tests for that). Real
            // machine state may legitimately produce items for those two;
            // this test only asserts every detector's own `id` scheme holds
            // and that nothing throws (mirrors
            // `DevToolsDetectorRegistryTests`' tolerance of real-environment
            // interaction at the registry level).
            let items = try await detector.scan(context: scanContext(roots: [home]))
            for item in items {
                XCTAssertTrue(item.sourceDetectorID.hasPrefix("junk."), "unexpected sourceDetectorID: \(item.sourceDetectorID)")
            }
        }
    }

    func testCanRegisterWithScanEngineAndRunAll() async throws {
        let home = TempHome.make()
        defer { TempHome.cleanup(home) }
        let staleCache = home + "/Library/Caches/com.example.myapp"
        FileManager.default.makeFile(staleCache + "/data.bin", contents: "x")
        FileManager.default.setModificationDate(daysAgo(90), at: staleCache + "/data.bin")
        FileManager.default.setModificationDate(daysAgo(90), at: staleCache)

        let engine = ScanEngine()
        await engine.register(CacheCleanerRegistry.all())

        let result = await engine.runAll(context: scanContext(roots: [home]))

        XCTAssertTrue(result.failedDetectorIDs.isEmpty, "no detector should throw on a sandboxed home: \(result.failedDetectorIDs)")
        XCTAssertTrue(result.items.contains { $0.sourceDetectorID == "junk.cache.user-app-cache" })
    }
}
