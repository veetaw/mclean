import XCTest
@testable import MaintenanceScripts

final class MaintenanceScriptsRegistryTests: XCTestCase {
    func testAllReturnsOneTaskPerMaintenanceActionWithUniqueIDs() {
        let tasks = MaintenanceScriptsRegistry.all()
        let ids = tasks.map(\.id)

        XCTAssertEqual(Set(ids).count, ids.count, "task ids must be unique")
        XCTAssertEqual(Set(ids), [
            "maintenance.flush-dns",
            "maintenance.rebuild-spotlight-index",
            "maintenance.verify-startup-disk",
            "maintenance.clear-font-cache"
        ])
    }

    func testEveryTaskHasANonEmptyTitleAndDescription() {
        for task in MaintenanceScriptsRegistry.all() {
            XCTAssertFalse(task.title.isEmpty, "\(task.id) needs a title")
            XCTAssertFalse(task.description.isEmpty, "\(task.id) needs a description shown before it can be triggered")
        }
    }

    func testOnlySpotlightRebuildRequiresAdministratorPrivileges() {
        let elevated = MaintenanceScriptsRegistry.all().filter(\.requiresAdministratorPrivileges).map(\.id)
        XCTAssertEqual(elevated, ["maintenance.rebuild-spotlight-index"])
    }
}
