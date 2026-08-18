import XCTest
import CoreScanEngine
@testable import MobileDevDetectors

final class AndroidGradleWrapperDetectorTests: TempDirTestCase {
    func testReturnsEmptyWhenWrapperDistsMissing() async throws {
        let detector = AndroidGradleWrapperDetector(wrapperDistsPath: tempDir.appendingPathComponent("nope").path)
        let items = try await detector.scan(context: ScanContext(roots: []))
        XCTAssertTrue(items.isEmpty)
    }

    func testFlagsOnlyOlderGradleDistributions() async throws {
        for name in ["gradle-7.6-bin", "gradle-8.0-bin", "gradle-8.4-bin"] {
            try TestSupport.makeDirectory(at: tempDir.appendingPathComponent(name))
        }

        let detector = AndroidGradleWrapperDetector(wrapperDistsPath: tempDir.path)
        let items = try await detector.scan(context: ScanContext(roots: []))

        let flagged = Set(items.map { URL(fileURLWithPath: $0.path).lastPathComponent })
        XCTAssertEqual(flagged, ["gradle-7.6-bin", "gradle-8.0-bin"])
        for item in items {
            XCTAssertEqual(item.sourceDetectorID, "mobile.android.gradle-wrapper-stale")
            XCTAssertTrue(item.reason.contains("gradle-8.4-bin"))
        }
    }

    func testDoesNotFlagSingleDistribution() async throws {
        try TestSupport.makeDirectory(at: tempDir.appendingPathComponent("gradle-8.4-bin"))
        let detector = AndroidGradleWrapperDetector(wrapperDistsPath: tempDir.path)
        let items = try await detector.scan(context: ScanContext(roots: []))
        XCTAssertTrue(items.isEmpty)
    }
}
