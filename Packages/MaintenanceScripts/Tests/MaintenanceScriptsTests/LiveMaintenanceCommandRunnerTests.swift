import XCTest
@testable import MaintenanceScripts

/// Exercises the *real* `LiveMaintenanceCommandRunner` — the only place in
/// this test target that actually launches a `Process` — using safe,
/// side-effect-free standin commands (`/bin/echo`, `/bin/sleep`, a
/// deliberately nonexistent path) rather than any of the four real
/// maintenance commands.
///
/// This is judged safe to run for real because none of these standins have
/// any effect on the system, none require elevation, and every case has a
/// short, bounded runtime — unlike, say, `diskutil verifyVolume /`, whose
/// runtime scales with real disk size and isn't safe to assume is fast in
/// CI. Running one of the *actual* maintenance commands for real (even the
/// read-only `VerifyStartupDiskTask`) is deliberately avoided here so
/// `swift test` stays fast and side-effect-free; those tasks are covered
/// against `FakeMaintenanceCommandRunner` instead, in their own test files.
final class LiveMaintenanceCommandRunnerTests: XCTestCase {
    func testCapturesStandardOutputOnCleanExit() async {
        let outcome = await LiveMaintenanceCommandRunner().run(
            executable: "/bin/echo",
            arguments: ["hello-maintenance-scripts"],
            timeout: 5
        )

        XCTAssertTrue(outcome.succeeded)
        XCTAssertTrue(outcome.standardOutput.contains("hello-maintenance-scripts"))
    }

    func testCapturesNonZeroExitCode() async {
        let outcome = await LiveMaintenanceCommandRunner().run(
            executable: "/usr/bin/false",
            arguments: [],
            timeout: 5
        )

        XCTAssertFalse(outcome.succeeded)
        if case .exited(let code) = outcome.status {
            XCTAssertNotEqual(code, 0)
        } else {
            XCTFail("expected a clean non-zero exit, got \(outcome.status)")
        }
    }

    func testHungProcessIsTerminatedAndReportedAsTimedOutRatherThanHanging() async {
        let start = Date()
        let outcome = await LiveMaintenanceCommandRunner().run(
            executable: "/bin/sleep",
            arguments: ["30"],
            timeout: 0.3
        )
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(outcome.status, .timedOut)
        // Generous upper bound so this never flakes under CI load, while
        // still proving the caller wasn't left waiting anywhere near the
        // full 30s the command itself asked for.
        XCTAssertLessThan(elapsed, 10)
    }

    func testMissingExecutableSurfacesLaunchFailedRatherThanThrowing() async {
        let outcome = await LiveMaintenanceCommandRunner().run(
            executable: "/no/such/binary/exists/here",
            arguments: [],
            timeout: 5
        )

        if case .launchFailed = outcome.status {
            // expected
        } else {
            XCTFail("expected launchFailed, got \(outcome.status)")
        }
    }
}
