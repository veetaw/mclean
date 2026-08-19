import XCTest
import CoreScanEngine
@testable import Optimization

final class OptimizationRegistryTests: XCTestCase {
    // Deliberately does not call `.scan(context:)` on the detectors this
    // returns: `LaunchAgentDetector`'s default paths point at the real
    // `~/Library/LaunchAgents` / `/Library/LaunchAgents`, and this suite
    // must never touch those (see `LaunchAgentDetectorTests` for scans,
    // which always inject temp-directory paths).
    func testAllReturnsExactlyTheLaunchAgentDetectorWithUniqueIDs() {
        let detectors = OptimizationRegistry.all()
        let ids = detectors.map(\.id)

        XCTAssertEqual(Set(ids).count, ids.count, "detector ids must be unique")
        XCTAssertEqual(Set(ids), ["optimization.launch-agents"])

        for detector in detectors {
            XCTAssertEqual(detector.category, .optimization)
            XCTAssertFalse(detector.displayName.isEmpty)
        }
    }
}
