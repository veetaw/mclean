import XCTest
import CoreScanEngine
@testable import MobileDevDetectors

final class FastlaneCacheDetectorTests: TempDirTestCase {
    func testReturnsEmptyWhenNothingPresent() async throws {
        let detector = FastlaneCacheDetector(
            globalCachePath: tempDir.appendingPathComponent("Caches/fastlane").path,
            projectSearchRoots: [tempDir.appendingPathComponent("empty").path]
        )
        let items = try await detector.scan(context: ScanContext(roots: []))
        XCTAssertTrue(items.isEmpty)
    }

    func testFlagsGlobalCache() async throws {
        let globalCache = tempDir.appendingPathComponent("Caches/fastlane")
        try TestSupport.makeFile(at: globalCache.appendingPathComponent("state.json"), size: 128)

        let detector = FastlaneCacheDetector(
            globalCachePath: globalCache.path,
            projectSearchRoots: [tempDir.appendingPathComponent("empty").path]
        )
        let items = try await detector.scan(context: ScanContext(roots: []))

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.category, "Fastlane — global cache")
        XCTAssertEqual(items.first?.sourceDetectorID, "mobile.ios.fastlane-cache")
    }

    func testFindsPerProjectReportAndTestOutput() async throws {
        let projectDir = tempDir.appendingPathComponent("Projects/ProjectA")
        try TestSupport.makeFile(at: projectDir.appendingPathComponent("fastlane/report.xml"), size: 200)
        try TestSupport.makeFile(
            at: projectDir.appendingPathComponent("fastlane/test_output/junit.xml"),
            size: 300
        )

        let detector = FastlaneCacheDetector(
            globalCachePath: tempDir.appendingPathComponent("no-global-cache").path,
            projectSearchRoots: [tempDir.appendingPathComponent("Projects").path]
        )
        let items = try await detector.scan(context: ScanContext(roots: []))

        let categories = Set(items.map(\.category))
        XCTAssertTrue(categories.contains("Fastlane — report output"))
        XCTAssertTrue(categories.contains("Fastlane — test output"))
        XCTAssertTrue(items.allSatisfy { $0.reason.contains("ProjectA") })
    }

    func testSkipsHeavyVendoredDirectories() async throws {
        try TestSupport.makeFile(
            at: tempDir.appendingPathComponent("node_modules/some-pkg/fastlane/report.xml"),
            size: 100
        )

        let detector = FastlaneCacheDetector(
            globalCachePath: tempDir.appendingPathComponent("no-global-cache").path,
            projectSearchRoots: [tempDir.path]
        )
        let items = try await detector.scan(context: ScanContext(roots: []))

        XCTAssertTrue(items.isEmpty)
    }

    func testContextRootsOverrideDefaultProjectSearchRoots() async throws {
        let projectDir = tempDir.appendingPathComponent("ProjectB")
        try TestSupport.makeFile(at: projectDir.appendingPathComponent("fastlane/report.xml"), size: 64)

        let detector = FastlaneCacheDetector(
            globalCachePath: tempDir.appendingPathComponent("no-global-cache").path,
            projectSearchRoots: [tempDir.appendingPathComponent("unrelated-empty-root").path]
        )
        let items = try await detector.scan(context: ScanContext(roots: [tempDir.path]))

        XCTAssertTrue(items.contains { $0.category == "Fastlane — report output" })
    }
}
