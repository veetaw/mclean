import XCTest
@testable import Optimization

final class LoginItemsInspectorTests: TempDirTestCase {
    func testBestEffortCandidatesIncludesOnlyRunAtLoadTruePlists() throws {
        let launchAgentsDir = tempDir.appendingPathComponent("LaunchAgents")
        try TestSupport.makeLaunchAgentPlist(
            at: launchAgentsDir.appendingPathComponent("com.example.login.plist"),
            label: "com.example.login",
            runAtLoad: true
        )
        try TestSupport.makeLaunchAgentPlist(
            at: launchAgentsDir.appendingPathComponent("com.example.notlogin.plist"),
            label: "com.example.notlogin",
            runAtLoad: false
        )
        try TestSupport.makeMalformedPlist(
            at: launchAgentsDir.appendingPathComponent("com.example.bad.plist")
        )

        let inspector = LoginItemsInspector()
        let candidates = inspector.bestEffortUserLoginItemCandidates(launchAgentsPath: launchAgentsDir.path)

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.plist.label, "com.example.login")
    }

    func testBestEffortCandidatesReturnsEmptyForMissingDirectory() {
        let inspector = LoginItemsInspector()
        let candidates = inspector.bestEffortUserLoginItemCandidates(
            launchAgentsPath: tempDir.appendingPathComponent("does-not-exist").path
        )
        XCTAssertTrue(candidates.isEmpty)
    }

    #if canImport(ServiceManagement)
    @available(macOS 13.0, *)
    func testMainAppStatusReturnsWithoutThrowingOrCrashing() {
        let inspector = LoginItemsInspector()
        // No assertion on the specific case — under XCTest this process
        // isn't a registered login item, so the exact status is
        // environment-dependent. This only asserts the read-only query
        // completes and yields a recognized value.
        let status = inspector.mainAppStatus()
        XCTAssertFalse(status.rawValue.isEmpty)
    }
    #endif
}
