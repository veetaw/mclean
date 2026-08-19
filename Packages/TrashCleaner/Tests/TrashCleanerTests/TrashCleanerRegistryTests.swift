import XCTest
import CoreScanEngine
@testable import TrashCleaner

final class TrashCleanerRegistryTests: XCTestCase {
    func testAllReturnsEveryDetectorExactlyOnce() {
        let detectors = TrashCleanerRegistry.all()
        let ids = detectors.map(\.id)

        XCTAssertEqual(Set(ids).count, ids.count, "detector ids must be unique")
        XCTAssertEqual(Set(ids), [
            "trash.finder",
            "trash.mail",
            "trash.photos"
        ])
    }

    func testEveryDetectorIsCategorizedAsTrash() {
        for detector in TrashCleanerRegistry.all() {
            XCTAssertEqual(detector.category, .trash, "\(detector.id) should be categorized as .trash")
        }
    }

    func testEveryDetectorHasANonEmptyDisplayName() {
        for detector in TrashCleanerRegistry.all() {
            XCTAssertFalse(detector.displayName.isEmpty)
        }
    }
}
