import XCTest
import CoreScanEngine
@testable import PrivacyCleaner

final class PrivacyCleanerRegistryTests: XCTestCase {
    func testAllReturnsOneDetectorPerBrowser() {
        let detectors = PrivacyCleanerRegistry.all()
        XCTAssertEqual(detectors.count, 3)
        XCTAssertEqual(Set(detectors.map(\.id)), ["privacy.safari", "privacy.chrome", "privacy.firefox"])
        XCTAssertTrue(detectors.allSatisfy { $0.category == .privacy })
    }

    func testEveryDetectorIsGracefulOnAnEmptyHome() async throws {
        let home = TempHome.make()
        defer { TempHome.cleanup(home) }

        for detector in PrivacyCleanerRegistry.all() {
            let items = try await detector.scan(context: scanContext(roots: [home]))
            XCTAssertTrue(items.isEmpty, "\(detector.id) should return no items for an empty home directory")
        }
    }
}
