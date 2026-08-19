import XCTest
@testable import MaintenanceScripts

final class ClearFontCacheTaskTests: XCTestCase {
    func testBuildsExactCommand() async {
        let fake = FakeMaintenanceCommandRunner(outcome: .ok())
        _ = await ClearFontCacheTask().run(using: fake)

        let invocations = await fake.invocations
        XCTAssertEqual(invocations.count, 1)
        XCTAssertEqual(invocations[0].executable, "/usr/bin/atsutil")
        XCTAssertEqual(invocations[0].arguments, ["databases", "-remove"])
    }

    func testDoesNotRequireElevation() {
        XCTAssertFalse(ClearFontCacheTask().requiresAdministratorPrivileges)
    }

    func testDescriptionMentionsLogoutOrRestartCaveat() {
        let description = ClearFontCacheTask().description.lowercased()
        XCTAssertTrue(description.contains("log out") || description.contains("restart") || description.contains("relaunch"))
    }

    func testSuccessSurfaced() async {
        let fake = FakeMaintenanceCommandRunner(outcome: .ok())
        let result = await ClearFontCacheTask().run(using: fake)
        XCTAssertEqual(result.outcome, .success)
    }

    func testFailureSurfacedWithStderr() async {
        let fake = FakeMaintenanceCommandRunner(outcome: .failed(code: 2, stderr: "atsutil: permission denied"))
        let result = await ClearFontCacheTask().run(using: fake)
        XCTAssertEqual(result.outcome, .failure)
        XCTAssertTrue(result.output.contains("permission denied"))
    }
}
