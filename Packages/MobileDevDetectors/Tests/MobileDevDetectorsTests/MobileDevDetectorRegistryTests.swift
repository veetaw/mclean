import XCTest
import CoreScanEngine
@testable import MobileDevDetectors

final class MobileDevDetectorRegistryTests: XCTestCase {
    func testAllDetectorsCoversEveryAreaFromTheSpec() {
        let detectors = MobileDevDetectorRegistry.allDetectors()
        let ids = Set(detectors.map(\.id))

        XCTAssertEqual(ids.count, detectors.count, "detector ids must be unique")
        XCTAssertTrue(ids.contains("mobile.android.avd-stale"))
        XCTAssertTrue(ids.contains("mobile.android.sdk-obsolete-versions"))
        XCTAssertTrue(ids.contains("mobile.android.studio-caches"))
        XCTAssertTrue(ids.contains("mobile.android.gradle-wrapper-stale"))
        XCTAssertTrue(ids.contains("mobile.ios.simulator-runtimes-unused"))
        XCTAssertTrue(ids.contains("mobile.ios.simulator-devices-stale"))
        XCTAssertTrue(ids.contains("mobile.ios.cocoapods-cache"))
        XCTAssertTrue(ids.contains("mobile.ios.fastlane-cache"))

        for detector in detectors {
            XCTAssertEqual(detector.category, .mobileDev)
        }
    }

    func testTotalRecoverableBytesSumsOnlyMobileDevItems() {
        let mobileItem1 = ScanItem(
            path: "/tmp/a",
            sizeBytes: 1_000,
            sourceDetectorID: "mobile.ios.cocoapods-cache",
            category: "CocoaPods — pod cache",
            lastUsed: nil,
            reason: "test"
        )
        let mobileItem2 = ScanItem(
            path: "/tmp/b",
            sizeBytes: 2_500,
            sourceDetectorID: "mobile.android.avd-stale",
            category: "Android — AVD emulator image",
            lastUsed: nil,
            reason: "test"
        )
        let mobileItemUnknownSize = ScanItem(
            path: "/tmp/c",
            sizeBytes: nil,
            sourceDetectorID: "mobile.ios.fastlane-cache",
            category: "Fastlane — global cache",
            lastUsed: nil,
            reason: "test"
        )
        let unrelatedItem = ScanItem(
            path: "/tmp/d",
            sizeBytes: 999_999,
            sourceDetectorID: "dev.node.node-modules-stale",
            category: "Node — node_modules",
            lastUsed: nil,
            reason: "test"
        )

        let total = MobileDevDetectorRegistry.totalRecoverableBytes(
            in: [mobileItem1, mobileItem2, mobileItemUnknownSize, unrelatedItem]
        )

        XCTAssertEqual(total, 3_500)
    }

    func testTotalRecoverableBytesIsZeroForEmptyInput() {
        XCTAssertEqual(MobileDevDetectorRegistry.totalRecoverableBytes(in: []), 0)
    }
}
