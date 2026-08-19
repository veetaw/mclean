import XCTest
@testable import MaintenanceScripts

final class RebuildSpotlightIndexTaskTests: XCTestCase {
    func testBuildsExactFixedAppleScriptElevationCommand() async {
        let fake = FakeMaintenanceCommandRunner(outcome: .ok())
        _ = await RebuildSpotlightIndexTask().run(using: fake)

        let invocations = await fake.invocations
        XCTAssertEqual(invocations.count, 1)
        XCTAssertEqual(invocations[0].executable, "/usr/bin/osascript")
        // Exactly this fixed literal — never built from any input this
        // package doesn't control.
        XCTAssertEqual(invocations[0].arguments, [
            "-e",
            "do shell script \"mdutil -E /\" with administrator privileges"
        ])
    }

    func testDeclaresItRequiresAdministratorPrivileges() {
        XCTAssertTrue(RebuildSpotlightIndexTask().requiresAdministratorPrivileges)
    }

    func testSuccessIsSurfaced() async {
        let fake = FakeMaintenanceCommandRunner(outcome: .ok())
        let result = await RebuildSpotlightIndexTask().run(using: fake)
        XCTAssertEqual(result.outcome, .success)
    }

    func testCancelledPromptOrFailureIsSurfacedNotThrown() async {
        let fake = FakeMaintenanceCommandRunner(outcome: .failed(code: 1, stderr: "User canceled."))
        let result = await RebuildSpotlightIndexTask().run(using: fake)
        XCTAssertEqual(result.outcome, .failure)
        XCTAssertTrue(result.summary.contains("cancelled") || result.summary.contains("cancel"))
    }

    func testTimeoutDoesNotCrash() async {
        let fake = FakeMaintenanceCommandRunner(outcome: .timedOutFake)
        let result = await RebuildSpotlightIndexTask().run(using: fake)
        XCTAssertEqual(result.outcome, .failure)
    }

    func testDescriptionMentionsAdministratorPassword() {
        let description = RebuildSpotlightIndexTask().description
        XCTAssertTrue(description.lowercased().contains("administrator"))
    }
}
