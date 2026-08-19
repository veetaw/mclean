import XCTest
import CoreScanEngine
@testable import PowerUserInspectors

final class PowerUserInspectorRegistryTests: XCTestCase {
    func testAllDetectorsReturnsInstalledAppsDetectorInThePowerUserCategory() {
        let detectors = PowerUserInspectorRegistry.allDetectors()
        XCTAssertEqual(detectors.map(\.id), ["poweruser.apps.installed"])
        for detector in detectors {
            XCTAssertEqual(detector.category, .powerUser)
            XCTAssertFalse(detector.displayName.isEmpty)
        }
    }

    func testCanRegisterWithScanEngineAndRunAllWithoutThrowing() async throws {
        let engine = ScanEngine()
        await engine.register(PowerUserInspectorRegistry.allDetectors())

        let result = await engine.runAll(context: ScanContext(roots: ["/nonexistent-power-user-inspectors-fixture"]))

        XCTAssertTrue(result.failedDetectorIDs.isEmpty, "no detector should throw: \(result.failedDetectorIDs)")
        XCTAssertEqual(result.items, [])
    }
}
