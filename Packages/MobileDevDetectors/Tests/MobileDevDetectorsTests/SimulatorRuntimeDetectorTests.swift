import XCTest
import CoreScanEngine
@testable import MobileDevDetectors

private struct FakeCommandRunner: CommandRunning {
    let runtimesJSON: String
    let devicesJSON: String
    var throwsError = false

    func run(executablePath: String, arguments: [String]) throws -> String {
        if throwsError {
            throw CommandRunningError.nonZeroExit(1, stderr: "simctl unavailable")
        }
        if arguments.contains("runtimes") { return runtimesJSON }
        if arguments.contains("devices") { return devicesJSON }
        return ""
    }
}

final class SimulatorRuntimeDetectorTests: TempDirTestCase {
    // Guaranteed to exist and be executable on every macOS install, used
    // only to pass the detector's "is xcrun present" gate — the actual
    // `simctl` invocation is replaced by `FakeCommandRunner`.
    private let realExecutablePath = "/usr/bin/true"

    func testReturnsEmptyWhenXcrunMissing() async throws {
        let detector = SimulatorRuntimeDetector(
            xcrunPath: tempDir.appendingPathComponent("no-xcrun").path,
            commandRunner: FakeCommandRunner(runtimesJSON: "{}", devicesJSON: "{}")
        )
        let items = try await detector.scan(context: ScanContext(roots: []))
        XCTAssertTrue(items.isEmpty)
    }

    func testReturnsEmptyWhenCommandFails() async throws {
        let detector = SimulatorRuntimeDetector(
            xcrunPath: realExecutablePath,
            commandRunner: FakeCommandRunner(runtimesJSON: "{}", devicesJSON: "{}", throwsError: true)
        )
        let items = try await detector.scan(context: ScanContext(roots: []))
        XCTAssertTrue(items.isEmpty)
    }

    func testFlagsRuntimeWithNoDevicesAndStaleRuntimeButNotFreshRuntime() async throws {
        let oldDataPath = tempDir.appendingPathComponent("old-device-data")
        try TestSupport.makeDirectory(at: oldDataPath, modificationDate: TestSupport.daysAgo(400))

        let freshDataPath = tempDir.appendingPathComponent("fresh-device-data")
        try TestSupport.makeDirectory(at: freshDataPath, modificationDate: Date())

        let runtimesJSON = """
        {"runtimes":[
          {"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-16-4","name":"iOS 16.4","version":"16.4"},
          {"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-17-0","name":"iOS 17.0","version":"17.0"},
          {"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","name":"iOS 18.0","version":"18.0"}
        ]}
        """
        let devicesJSON = """
        {"devices":{
          "com.apple.CoreSimulator.SimRuntime.iOS-17-0":[
            {"udid":"OLD","name":"iPhone 14","state":"Shutdown","dataPath":"\(oldDataPath.path)"}
          ],
          "com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
            {"udid":"FRESH","name":"iPhone 15","state":"Booted","dataPath":"\(freshDataPath.path)"}
          ]
        }}
        """

        let detector = SimulatorRuntimeDetector(
            xcrunPath: realExecutablePath,
            commandRunner: FakeCommandRunner(runtimesJSON: runtimesJSON, devicesJSON: devicesJSON),
            staleThresholdDays: 60
        )
        let items = try await detector.scan(context: ScanContext(roots: []))

        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.contains { $0.reason.contains("iOS-16-4") && $0.reason.contains("No simulator devices") })
        XCTAssertTrue(items.contains { $0.reason.contains("iOS-17-0") })
        XCTAssertFalse(items.contains { $0.reason.contains("iOS-18-0") })

        for item in items {
            XCTAssertEqual(item.sourceDetectorID, "mobile.ios.simulator-runtimes-unused")
        }
    }
}
