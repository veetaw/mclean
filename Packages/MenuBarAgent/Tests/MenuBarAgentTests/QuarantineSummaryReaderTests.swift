import CoreScanEngine
import Foundation
import SafetyRules
import XCTest
@testable import MenuBarAgent

final class QuarantineSummaryReaderTests: XCTestCase {
    func testSummarizesActiveReceipts() async {
        let item1 = ScanItem(path: "/tmp/a", sizeBytes: 1_000, sourceDetectorID: "x", category: "Test", lastUsed: nil, reason: "r")
        let item2 = ScanItem(path: "/tmp/b", sizeBytes: 2_000, sourceDetectorID: "x", category: "Test", lastUsed: nil, reason: "r")
        let now = Date(timeIntervalSince1970: 0)
        let receipt1 = QuarantineReceipt(originalPath: "/tmp/a", quarantinePath: "/q/a", quarantinedAt: now, policy: .default, sourceItem: item1)
        let receipt2 = QuarantineReceipt(
            originalPath: "/tmp/b",
            quarantinePath: "/q/b",
            quarantinedAt: now.addingTimeInterval(-86_400),
            policy: .default,
            sourceItem: item2
        )

        let manager = FakeQuarantineManaging(receipts: [receipt1, receipt2])
        let reader = QuarantineSummaryReader(manager: manager)

        let summary = await reader.summary()
        XCTAssertEqual(summary.itemCount, 2)
        XCTAssertEqual(summary.totalReclaimableBytes, 3_000)
        XCTAssertEqual(summary.oldestPurgeEligibleAt, receipt2.purgeEligibleAt)
    }

    func testEmptyQuarantineSummarizesToZero() async {
        let manager = FakeQuarantineManaging(receipts: [])
        let reader = QuarantineSummaryReader(manager: manager)

        let summary = await reader.summary()
        XCTAssertEqual(summary.itemCount, 0)
        XCTAssertEqual(summary.totalReclaimableBytes, 0)
        XCTAssertNil(summary.oldestPurgeEligibleAt)
    }

    func testItemsWithNoKnownSizeContributeZeroRatherThanCrashing() async {
        let item = ScanItem(path: "/tmp/a", sizeBytes: nil, sourceDetectorID: "x", category: "Test", lastUsed: nil, reason: "r")
        let receipt = QuarantineReceipt(originalPath: "/tmp/a", quarantinePath: "/q/a", quarantinedAt: Date(), policy: .default, sourceItem: item)
        let manager = FakeQuarantineManaging(receipts: [receipt])
        let reader = QuarantineSummaryReader(manager: manager)

        let summary = await reader.summary()
        XCTAssertEqual(summary.itemCount, 1)
        XCTAssertEqual(summary.totalReclaimableBytes, 0)
    }
}
