import XCTest
@testable import MenuBarAgent

final class LowDiskSpaceThresholdTests: XCTestCase {
    func testTriggersOnAbsoluteBytesOnly() {
        let threshold = LowDiskSpaceThreshold(minimumFreeBytes: 10_000, minimumFreeFraction: nil)
        XCTAssertTrue(threshold.isLow(free: 9_999, total: 1_000_000))
        XCTAssertFalse(threshold.isLow(free: 10_000, total: 1_000_000))
    }

    func testTriggersOnFractionOnly() {
        let threshold = LowDiskSpaceThreshold(minimumFreeBytes: nil, minimumFreeFraction: 0.10)
        XCTAssertTrue(threshold.isLow(free: 5, total: 100)) // 5% free
        XCTAssertFalse(threshold.isLow(free: 20, total: 100)) // 20% free
    }

    func testEitherConditionCrossingCountsAsLow() {
        let threshold = LowDiskSpaceThreshold(minimumFreeBytes: 1_000, minimumFreeFraction: 0.50)
        // Passes the byte check (2000 >= 1000) but fails the fraction check (2000/10000 = 20% < 50%).
        XCTAssertTrue(threshold.isLow(free: 2_000, total: 10_000))
    }

    func testBothConditionsMustPassToNotBeLow() {
        let threshold = LowDiskSpaceThreshold(minimumFreeBytes: 1_000, minimumFreeFraction: 0.10)
        XCTAssertFalse(threshold.isLow(free: 5_000, total: 10_000))
    }

    func testNoThresholdsConfiguredNeverTriggers() {
        let threshold = LowDiskSpaceThreshold(minimumFreeBytes: nil, minimumFreeFraction: nil)
        XCTAssertFalse(threshold.isLow(free: 0, total: 1_000))
    }

    func testDefaultThresholdIsTenGBOrTenPercent() {
        let threshold = LowDiskSpaceThreshold.default
        XCTAssertTrue(threshold.isLow(free: 5_000_000_000, total: 1_000_000_000_000)) // < 10 GB absolute
        XCTAssertFalse(threshold.isLow(free: 50_000_000_000, total: 100_000_000_000)) // 50 GB & 50% free -- neither crossed
    }
}
