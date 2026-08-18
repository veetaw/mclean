import XCTest
import CoreScanEngine
@testable import MobileDevDetectors

final class AndroidStudioCacheDetectorTests: TempDirTestCase {
    func testReturnsEmptyWhenNothingInstalled() async throws {
        let detector = AndroidStudioCacheDetector(
            cachesRootPath: tempDir.appendingPathComponent("Caches/Google").path,
            applicationSupportRootPath: tempDir.appendingPathComponent("AppSupport/Google").path
        )
        let items = try await detector.scan(context: ScanContext(roots: []))
        XCTAssertTrue(items.isEmpty)
    }

    func testFlagsCachesDirectoryAndOnlyAppSupportCachesSubdirectory() async throws {
        let cachesRoot = tempDir.appendingPathComponent("Caches/Google")
        let studioCacheDir = cachesRoot.appendingPathComponent("AndroidStudio2023.1")
        try TestSupport.makeFile(at: studioCacheDir.appendingPathComponent("index.dat"), size: 2048)

        let appSupportRoot = tempDir.appendingPathComponent("AppSupport/Google")
        let studioAppSupportDir = appSupportRoot.appendingPathComponent("AndroidStudio2023.1")
        try TestSupport.makeFile(at: studioAppSupportDir.appendingPathComponent("caches/build.dat"), size: 4096)
        // A sibling settings file that must NOT be swept up.
        try TestSupport.makeFile(at: studioAppSupportDir.appendingPathComponent("options/keymap.xml"), size: 32)

        let detector = AndroidStudioCacheDetector(
            cachesRootPath: cachesRoot.path,
            applicationSupportRootPath: appSupportRoot.path
        )
        let items = try await detector.scan(context: ScanContext(roots: []))

        XCTAssertEqual(items.count, 2)
        let paths = Set(items.map(\.path))
        XCTAssertTrue(paths.contains(studioCacheDir.path))
        XCTAssertTrue(paths.contains(studioAppSupportDir.appendingPathComponent("caches").path))
        // The settings directory itself was never reported.
        XCTAssertFalse(paths.contains(studioAppSupportDir.path))

        for item in items {
            XCTAssertEqual(item.sourceDetectorID, "mobile.android.studio-caches")
            XCTAssertNotNil(item.sizeBytes)
        }
    }
}
