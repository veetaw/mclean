import XCTest
import CoreScanEngine
@testable import MobileDevDetectors

final class AndroidSDKDetectorTests: TempDirTestCase {
    func testReturnsEmptyWhenSDKRootMissing() async throws {
        let detector = AndroidSDKDetector(sdkRootPath: tempDir.appendingPathComponent("no-sdk").path)
        let items = try await detector.scan(context: ScanContext(roots: []))
        XCTAssertTrue(items.isEmpty)
    }

    func testFlagsOnlySupersededPlatformsAndBuildTools() async throws {
        let platformsDir = tempDir.appendingPathComponent("platforms")
        for name in ["android-30", "android-33", "android-34"] {
            try TestSupport.makeDirectory(at: platformsDir.appendingPathComponent(name))
        }

        let buildToolsDir = tempDir.appendingPathComponent("build-tools")
        for name in ["30.0.3", "33.0.0", "34.0.0"] {
            try TestSupport.makeDirectory(at: buildToolsDir.appendingPathComponent(name))
        }

        let detector = AndroidSDKDetector(sdkRootPath: tempDir.path)
        let items = try await detector.scan(context: ScanContext(roots: []))

        let flaggedNames = Set(items.map { URL(fileURLWithPath: $0.path).lastPathComponent })
        XCTAssertEqual(flaggedNames, ["android-30", "android-33", "30.0.3", "33.0.0"])
        XCTAssertFalse(flaggedNames.contains("android-34"))
        XCTAssertFalse(flaggedNames.contains("34.0.0"))

        for item in items {
            XCTAssertEqual(item.sourceDetectorID, "mobile.android.sdk-obsolete-versions")
            XCTAssertTrue(item.reason.contains("superseded"))
        }
    }

    func testDoesNotFlagWhenOnlyOneVersionInstalled() async throws {
        let platformsDir = tempDir.appendingPathComponent("platforms")
        try TestSupport.makeDirectory(at: platformsDir.appendingPathComponent("android-34"))

        let detector = AndroidSDKDetector(sdkRootPath: tempDir.path)
        let items = try await detector.scan(context: ScanContext(roots: []))

        XCTAssertTrue(items.isEmpty)
    }
}
