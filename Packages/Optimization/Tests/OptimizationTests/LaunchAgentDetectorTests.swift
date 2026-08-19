import XCTest
import CoreScanEngine
@testable import Optimization

final class LaunchAgentDetectorTests: TempDirTestCase {
    func testScanFindsValidPlistsFromBothScopesAndSkipsMalformedOnes() async throws {
        let userDir = tempDir.appendingPathComponent("user/LaunchAgents")
        let systemDir = tempDir.appendingPathComponent("system/LaunchAgents")

        try TestSupport.makeLaunchAgentPlist(
            at: userDir.appendingPathComponent("com.example.runatload.plist"),
            label: "com.example.runatload",
            program: "/usr/local/bin/agent-one",
            runAtLoad: true
        )
        try TestSupport.makeLaunchAgentPlist(
            at: userDir.appendingPathComponent("com.example.norunatload.plist"),
            label: "com.example.norunatload",
            program: "/usr/local/bin/agent-two",
            runAtLoad: false
        )
        try TestSupport.makeMalformedPlist(
            at: userDir.appendingPathComponent("com.example.malformed.plist")
        )
        try TestSupport.makeLaunchAgentPlist(
            at: systemDir.appendingPathComponent("com.example.systemwide.plist"),
            label: "com.example.systemwide",
            runAtLoad: true,
            keepAlive: true
        )

        let detector = LaunchAgentDetector(
            userLaunchAgentsPath: userDir.path,
            systemLaunchAgentsPath: systemDir.path
        )

        let items = try await detector.scan(context: ScanContext(roots: []))

        // Exactly the 3 valid plists — the malformed one is skipped, never
        // crashing the scan.
        XCTAssertEqual(items.count, 3)

        let byLabel = Dictionary(uniqueKeysWithValues: items.map { ($0.reason, $0) })
        XCTAssertTrue(byLabel.keys.contains { $0.contains("com.example.runatload") })

        let userItem = try XCTUnwrap(items.first { $0.path.contains("com.example.runatload.plist") })
        XCTAssertEqual(userItem.sourceDetectorID, "optimization.launch-agents.user")
        XCTAssertEqual(userItem.category, "Launch Agent — user")
        XCTAssertTrue(userItem.reason.contains("RunAtLoad is set"))
        XCTAssertTrue(userItem.reason.contains("com.example.runatload"))
        XCTAssertNotNil(userItem.sizeBytes)
        XCTAssertNotNil(userItem.lastUsed)

        let noRunAtLoadItem = try XCTUnwrap(items.first { $0.path.contains("com.example.norunatload.plist") })
        XCTAssertFalse(noRunAtLoadItem.reason.contains("RunAtLoad is set"))

        let systemItem = try XCTUnwrap(items.first { $0.path.contains("com.example.systemwide.plist") })
        XCTAssertEqual(systemItem.sourceDetectorID, "optimization.launch-agents.system")
        XCTAssertEqual(systemItem.category, "Launch Agent — system-wide (all users)")
        XCTAssertTrue(systemItem.reason.contains("KeepAlive is set"))

        XCTAssertFalse(items.contains { $0.path.contains("malformed") })
    }

    func testScanReturnsEmptyWhenDirectoriesDoNotExist() async throws {
        let detector = LaunchAgentDetector(
            userLaunchAgentsPath: tempDir.appendingPathComponent("no-user").path,
            systemLaunchAgentsPath: tempDir.appendingPathComponent("no-system").path
        )

        let items = try await detector.scan(context: ScanContext(roots: []))

        XCTAssertTrue(items.isEmpty)
    }

    func testUnlabeledPlistStillProducesADescriptiveItem() async throws {
        let userDir = tempDir.appendingPathComponent("LaunchAgents")
        try TestSupport.makeLaunchAgentPlist(
            at: userDir.appendingPathComponent("nolabel.plist"),
            label: nil,
            runAtLoad: false
        )

        let detector = LaunchAgentDetector(
            userLaunchAgentsPath: userDir.path,
            systemLaunchAgentsPath: tempDir.appendingPathComponent("no-system").path
        )

        let items = try await detector.scan(context: ScanContext(roots: []))

        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].reason.contains("no 'Label' key"))
    }

    func testMetadataIsWellFormed() {
        let detector = LaunchAgentDetector()
        XCTAssertEqual(detector.id, "optimization.launch-agents")
        XCTAssertEqual(detector.category, .optimization)
        XCTAssertFalse(detector.displayName.isEmpty)
    }
}
