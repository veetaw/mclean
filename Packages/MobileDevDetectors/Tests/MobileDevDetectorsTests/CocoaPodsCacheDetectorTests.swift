import XCTest
import CoreScanEngine
@testable import MobileDevDetectors

final class CocoaPodsCacheDetectorTests: TempDirTestCase {
    func testReturnsEmptyWhenNeitherPathExists() async throws {
        let detector = CocoaPodsCacheDetector(
            cachesPath: tempDir.appendingPathComponent("Caches/CocoaPods").path,
            dotCocoaPodsPath: tempDir.appendingPathComponent(".cocoapods").path
        )
        let items = try await detector.scan(context: ScanContext(roots: []))
        XCTAssertTrue(items.isEmpty)
    }

    func testReportsBothCachesWhenPresent() async throws {
        let cachesPath = tempDir.appendingPathComponent("Caches/CocoaPods")
        try TestSupport.makeFile(at: cachesPath.appendingPathComponent("Pods/SomePod/1.0/pod.zip"), size: 1024)

        let dotCocoaPodsPath = tempDir.appendingPathComponent(".cocoapods")
        try TestSupport.makeFile(at: dotCocoaPodsPath.appendingPathComponent("repos/master/README.md"), size: 512)

        let detector = CocoaPodsCacheDetector(cachesPath: cachesPath.path, dotCocoaPodsPath: dotCocoaPodsPath.path)
        let items = try await detector.scan(context: ScanContext(roots: []))

        XCTAssertEqual(items.count, 2)
        let paths = Set(items.map(\.path))
        XCTAssertTrue(paths.contains(cachesPath.path))
        XCTAssertTrue(paths.contains(dotCocoaPodsPath.path))

        for item in items {
            XCTAssertEqual(item.sourceDetectorID, "mobile.ios.cocoapods-cache")
            XCTAssertNotNil(item.sizeBytes)
            XCTAssertGreaterThan(item.sizeBytes ?? 0, 0)
        }

        let homeReport = items.first { $0.path == dotCocoaPodsPath.path }
        XCTAssertTrue(homeReport?.reason.contains("trunk credentials") ?? false)
    }

    func testReportsOnlyExistingPath() async throws {
        let cachesPath = tempDir.appendingPathComponent("Caches/CocoaPods")
        try TestSupport.makeFile(at: cachesPath.appendingPathComponent("pod.zip"), size: 256)

        let detector = CocoaPodsCacheDetector(
            cachesPath: cachesPath.path,
            dotCocoaPodsPath: tempDir.appendingPathComponent(".cocoapods").path
        )
        let items = try await detector.scan(context: ScanContext(roots: []))

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.path, cachesPath.path)
    }
}
