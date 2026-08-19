import XCTest
@testable import MaintenanceScripts

final class FlushDNSCacheTaskTests: XCTestCase {
    func testBuildsExactCommandsInOrder() async {
        let fake = FakeMaintenanceCommandRunner(outcomes: [.ok(), .ok()])
        let result = await FlushDNSCacheTask().run(using: fake)

        let invocations = await fake.invocations
        XCTAssertEqual(invocations.count, 2)
        XCTAssertEqual(invocations[0].executable, "/usr/bin/dscacheutil")
        XCTAssertEqual(invocations[0].arguments, ["-flushcache"])
        XCTAssertEqual(invocations[1].executable, "/usr/bin/killall")
        XCTAssertEqual(invocations[1].arguments, ["-HUP", "mDNSResponder"])
        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.taskID, "maintenance.flush-dns")
    }

    func testStopsAfterFirstCommandFailsAndNeverRunsSecond() async {
        let fake = FakeMaintenanceCommandRunner(outcomes: [.failed(code: 1, stderr: "dscacheutil exploded")])
        let result = await FlushDNSCacheTask().run(using: fake)

        let invocations = await fake.invocations
        XCTAssertEqual(invocations.count, 1, "must not run killall if dscacheutil already failed")
        XCTAssertEqual(result.outcome, .failure)
        XCTAssertTrue(result.summary.contains("dscacheutil"))
    }

    func testSecondCommandFailureIsSurfacedAsFailure() async {
        let fake = FakeMaintenanceCommandRunner(outcomes: [.ok(), .failed(code: 1, stderr: "mDNSResponder missing")])
        let result = await FlushDNSCacheTask().run(using: fake)

        XCTAssertEqual(result.outcome, .failure)
        XCTAssertTrue(result.summary.contains("killall"))
    }

    func testTimeoutIsSurfacedAsFailureNotCrash() async {
        let fake = FakeMaintenanceCommandRunner(outcomes: [.timedOutFake])
        let result = await FlushDNSCacheTask().run(using: fake)

        XCTAssertEqual(result.outcome, .failure)
        XCTAssertTrue(result.summary.lowercased().contains("timed out"))
    }

    func testDescriptionIsNonEmptyAndDoesNotRequireElevation() {
        let task = FlushDNSCacheTask()
        XCTAssertFalse(task.description.isEmpty)
        XCTAssertFalse(task.requiresAdministratorPrivileges)
    }
}
