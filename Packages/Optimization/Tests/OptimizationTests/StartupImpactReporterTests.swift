import XCTest
@testable import Optimization

final class StartupImpactReporterTests: TempDirTestCase {
    func testCandidatesIncludesOnlyRunAtLoadOrKeepAlivePlists() {
        let runsAtLoad = LaunchAgentPlist(
            path: "/tmp/a.plist", label: "a", program: nil, runAtLoad: true, keepAlive: false, scope: .user
        )
        let keepsAlive = LaunchAgentPlist(
            path: "/tmp/b.plist", label: "b", program: nil, runAtLoad: false, keepAlive: true, scope: .user
        )
        let neither = LaunchAgentPlist(
            path: "/tmp/c.plist", label: "c", program: nil, runAtLoad: false, keepAlive: false, scope: .system
        )

        let reporter = StartupImpactReporter()
        let candidates = reporter.candidates(from: [runsAtLoad, keepsAlive, neither])

        XCTAssertEqual(candidates.count, 2)
        XCTAssertTrue(candidates.contains { $0.plist.label == "a" && $0.runsAtLoad && !$0.keepsAlive })
        XCTAssertTrue(candidates.contains { $0.plist.label == "b" && !$0.runsAtLoad && $0.keepsAlive })
        XCTAssertFalse(candidates.contains { $0.plist.label == "c" })
    }

    func testReportCombinesUserAndSystemLocations() throws {
        let userDir = tempDir.appendingPathComponent("user/LaunchAgents")
        let systemDir = tempDir.appendingPathComponent("system/LaunchAgents")

        try TestSupport.makeLaunchAgentPlist(
            at: userDir.appendingPathComponent("com.example.user.plist"),
            label: "com.example.user",
            runAtLoad: true
        )
        try TestSupport.makeLaunchAgentPlist(
            at: systemDir.appendingPathComponent("com.example.system.plist"),
            label: "com.example.system",
            runAtLoad: false,
            keepAlive: true
        )
        try TestSupport.makeLaunchAgentPlist(
            at: userDir.appendingPathComponent("com.example.idle.plist"),
            label: "com.example.idle",
            runAtLoad: false
        )

        let reporter = StartupImpactReporter()
        let candidates = reporter.report(userLaunchAgentsPath: userDir.path, systemLaunchAgentsPath: systemDir.path)

        let labels = Set(candidates.map { $0.plist.label })
        XCTAssertEqual(labels, ["com.example.user", "com.example.system"])
    }

    func testReportReturnsEmptyForMissingDirectories() {
        let reporter = StartupImpactReporter()
        let candidates = reporter.report(
            userLaunchAgentsPath: tempDir.appendingPathComponent("no-user").path,
            systemLaunchAgentsPath: tempDir.appendingPathComponent("no-system").path
        )
        XCTAssertTrue(candidates.isEmpty)
    }
}
