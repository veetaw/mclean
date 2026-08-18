import XCTest
import CoreScanEngine
@testable import MobileDevDetectors

final class AndroidAVDDetectorTests: TempDirTestCase {
    func testReturnsEmptyWhenAVDRootMissing() async throws {
        let detector = AndroidAVDDetector(avdRootPath: tempDir.appendingPathComponent("nope").path)
        let items = try await detector.scan(context: ScanContext(roots: []))
        XCTAssertTrue(items.isEmpty)
    }

    func testFlagsAVDWithStaleUserdataImage() async throws {
        let avdDir = tempDir.appendingPathComponent("Pixel_5_API_33.avd")
        try TestSupport.makeDirectory(at: avdDir)
        try TestSupport.makeFile(
            at: avdDir.appendingPathComponent("userdata-qemu.img"),
            size: 4096,
            modificationDate: TestSupport.daysAgo(200)
        )

        let detector = AndroidAVDDetector(avdRootPath: tempDir.path, staleThresholdDays: 60)
        let items = try await detector.scan(context: ScanContext(roots: []))

        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.path, avdDir.path)
        XCTAssertEqual(item.sourceDetectorID, "mobile.android.avd-stale")
        XCTAssertEqual(item.lastUsed?.source, .filesystemMTime)
        XCTAssertNotNil(item.sizeBytes)
        XCTAssertTrue(item.reason.contains("best-effort") || item.reason.contains("Pixel_5_API_33"))
    }

    func testDoesNotFlagRecentlyActiveAVD() async throws {
        let avdDir = tempDir.appendingPathComponent("Recent_API_34.avd")
        try TestSupport.makeDirectory(at: avdDir)
        try TestSupport.makeFile(
            at: avdDir.appendingPathComponent("userdata-qemu.img"),
            modificationDate: Date()
        )

        let detector = AndroidAVDDetector(avdRootPath: tempDir.path, staleThresholdDays: 60)
        let items = try await detector.scan(context: ScanContext(roots: []))

        XCTAssertTrue(items.isEmpty)
    }

    func testIgnoresNonAVDDirectories() async throws {
        try TestSupport.makeDirectory(at: tempDir.appendingPathComponent("not-an-avd"))

        let detector = AndroidAVDDetector(avdRootPath: tempDir.path, staleThresholdDays: 0)
        let items = try await detector.scan(context: ScanContext(roots: []))

        XCTAssertTrue(items.isEmpty)
    }
}
