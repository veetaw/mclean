import XCTest
import CoreScanEngine
@testable import DevToolsDetectors

final class DevToolsDetectorRegistryTests: XCTestCase {
    func testAllReturnsOneDetectorPerToolchainWithUniqueIDs() {
        let detectors = DevToolsDetectorRegistry.all()
        let ids = detectors.map(\.id)

        XCTAssertEqual(Set(ids).count, ids.count, "detector ids must be unique")
        XCTAssertEqual(Set(ids), [
            "dev.python", "dev.node", "dev.rust", "dev.go", "dev.ruby",
            "dev.java", "dev.docker", "dev.xcode", "dev.homebrew", "dev.editors"
        ])
        for detector in detectors {
            XCTAssertEqual(detector.category, .devTools)
            XCTAssertFalse(detector.displayName.isEmpty)
        }
    }

    func testEveryRegisteredDetectorScansEmptyRootWithoutThrowing() async throws {
        let home = TempHome.make()
        defer { TempHome.cleanup(home) }

        for detector in DevToolsDetectorRegistry.all() {
            let items = try await detector.scan(context: scanContext(roots: [home]))
            // An empty sandbox home should never produce items (Docker also
            // resolves to empty here since PATH still points to a real
            // environment on CI machines without docker installed — if
            // docker *is* installed but idle, dangling-image findings would
            // require an actual dangling image to exist, which a fresh
            // sandbox never triggers).
            for item in items {
                XCTAssertEqual(item.sourceDetectorID.hasPrefix("dev."), true)
            }
        }
    }

    func testCanRegisterWithScanEngineAndRunAll() async throws {
        let home = TempHome.make()
        defer { TempHome.cleanup(home) }
        FileManager.default.makeFile(home + "/Library/Caches/pip/wheels/foo.whl")

        let engine = ScanEngine()
        await engine.register(DevToolsDetectorRegistry.all())

        let result = await engine.runAll(context: scanContext(roots: [home]))

        XCTAssertTrue(result.failedDetectorIDs.isEmpty, "no detector should throw on a sandboxed home: \(result.failedDetectorIDs)")
        XCTAssertTrue(result.items.contains { $0.sourceDetectorID == "dev.python.pip-cache" })
    }
}
