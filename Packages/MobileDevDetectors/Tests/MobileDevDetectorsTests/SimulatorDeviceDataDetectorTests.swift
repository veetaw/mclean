import XCTest
import CoreScanEngine
@testable import MobileDevDetectors

final class SimulatorDeviceDataDetectorTests: TempDirTestCase {
    func testReturnsEmptyWhenDevicesRootMissing() async throws {
        let detector = SimulatorDeviceDataDetector(devicesRootPath: tempDir.appendingPathComponent("nope").path)
        let items = try await detector.scan(context: ScanContext(roots: []))
        XCTAssertTrue(items.isEmpty)
    }

    func testFlagsStaleUnbootedDeviceAndUsesPlistName() async throws {
        let deviceDir = tempDir.appendingPathComponent("11111111-2222-3333-4444-555555555555")
        try TestSupport.makeDirectory(
            at: deviceDir.appendingPathComponent("data"),
            modificationDate: TestSupport.daysAgo(200)
        )

        let plist: [String: Any] = ["name": "iPhone 15 Pro", "UDID": "11111111-2222-3333-4444-555555555555"]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: deviceDir.appendingPathComponent("device.plist"))

        let detector = SimulatorDeviceDataDetector(devicesRootPath: tempDir.path, staleThresholdDays: 90)
        let items = try await detector.scan(context: ScanContext(roots: []))

        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.path, deviceDir.path)
        XCTAssertEqual(item.sourceDetectorID, "mobile.ios.simulator-devices-stale")
        XCTAssertTrue(item.reason.contains("iPhone 15 Pro"))
        XCTAssertEqual(item.lastUsed?.source, .filesystemMTime)
    }

    func testDoesNotFlagRecentlyUsedDevice() async throws {
        let deviceDir = tempDir.appendingPathComponent("AAAA")
        try TestSupport.makeDirectory(at: deviceDir.appendingPathComponent("data"), modificationDate: Date())

        let detector = SimulatorDeviceDataDetector(devicesRootPath: tempDir.path, staleThresholdDays: 90)
        let items = try await detector.scan(context: ScanContext(roots: []))

        XCTAssertTrue(items.isEmpty)
    }

    func testDegradesGracefullyWithoutDevicePlist() async throws {
        let deviceDir = tempDir.appendingPathComponent("NoPlistDevice")
        try TestSupport.makeDirectory(
            at: deviceDir.appendingPathComponent("data"),
            modificationDate: TestSupport.daysAgo(200)
        )

        let detector = SimulatorDeviceDataDetector(devicesRootPath: tempDir.path, staleThresholdDays: 90)
        let items = try await detector.scan(context: ScanContext(roots: []))

        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].reason.contains("NoPlistDevice"))
    }
}
