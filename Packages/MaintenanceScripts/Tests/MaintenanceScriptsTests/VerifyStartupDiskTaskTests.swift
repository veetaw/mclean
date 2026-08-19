import XCTest
@testable import MaintenanceScripts

final class VerifyStartupDiskTaskTests: XCTestCase {
    func testBuildsVerifyVolumeNotRepairPermissions() async {
        let fake = FakeMaintenanceCommandRunner(outcome: .ok())
        _ = await VerifyStartupDiskTask().run(using: fake)

        let invocations = await fake.invocations
        XCTAssertEqual(invocations.count, 1)
        XCTAssertEqual(invocations[0].executable, "/usr/sbin/diskutil")
        XCTAssertEqual(invocations[0].arguments, ["verifyVolume", "/"])
    }

    func testDoesNotRequireElevation() {
        XCTAssertFalse(VerifyStartupDiskTask().requiresAdministratorPrivileges)
    }

    func testDescriptionExplainsWhyRepairPermissionsIsGone() {
        let description = VerifyStartupDiskTask().description.lowercased()
        XCTAssertTrue(description.contains("repair"))
        XCTAssertTrue(description.contains("10.11") || description.contains("el capitan"))
    }

    func testSuccessSurfacedAsReadOnlyVerification() async {
        let fake = FakeMaintenanceCommandRunner(outcome: .ok("Volume is OK"))
        let result = await VerifyStartupDiskTask().run(using: fake)
        XCTAssertEqual(result.outcome, .success)
        XCTAssertTrue(result.summary.lowercased().contains("verif"))
    }

    func testFailureSurfaced() async {
        let fake = FakeMaintenanceCommandRunner(outcome: .failed(code: 1, stderr: "problems found"))
        let result = await VerifyStartupDiskTask().run(using: fake)
        XCTAssertEqual(result.outcome, .failure)
    }
}
